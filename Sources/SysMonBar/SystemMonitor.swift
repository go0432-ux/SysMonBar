import Foundation
import Darwin
import IOKit
import IOKit.storage

/// 一筆歷史紀錄樣本，用於畫 60 分鐘趨勢圖
struct Sample: Identifiable {
    let id = UUID()
    let time: Date
    let cpu: Double
    let mem: Double
    let diskReadBps: Double
    let diskWrittenBps: Double
}

/// 單一程式的記憶體用量資訊（用於「記憶體使用量最高」列表）
struct ProcessMemoryInfo: Identifiable {
    let id = UUID()
    let pid: Int32
    let name: String
    let rssMB: Double
    let percent: Double
}

/// 選單列要顯示的主要指標
enum MenuBarDisplayMode: String, CaseIterable, Identifiable, Hashable {
    case both
    case cpuOnly
    case memOnly

    var id: String { rawValue }
}

/// 使用原生 Mach / POSIX / IOKit API 讀取系統狀態，避免每次刷新都 spawn 子行程 (top/vm_stat/df)，
/// 藉此把資源消耗壓到最低。（Top-5 記憶體程式列表例外——這項本來就得讀取行程清單，
/// 用一次輕量的 `ps` 呼叫取得，比自己 walk sysctl 行程表簡單可靠很多。）
final class SystemMonitor: ObservableObject {

    static let defaultInterval: TimeInterval = 10
    static let availableIntervals: [TimeInterval] = [1, 2, 5, 10, 30, 60]
    private static let intervalDefaultsKey = "SysMonBar.refreshInterval"
    private static let displayModeDefaultsKey = "SysMonBar.menuBarDisplayMode"
    private static let historyWindow: TimeInterval = 60 * 60   // 60 分鐘

    @Published var cpuUsage: Double = 0

    @Published var memUsage: Double = 0
    @Published var memUsedGB: Double = 0
    @Published var memTotalGB: Double = 0
    @Published var wiredMemGB: Double = 0

    @Published var diskUsage: Double = 0
    @Published var diskUsedGB: Double = 0
    @Published var diskTotalGB: Double = 0
    @Published var diskReadPerSec: Double = 0      // bytes/sec
    @Published var diskWrittenPerSec: Double = 0   // bytes/sec

    @Published var samples: [Sample] = []
    @Published var topMemoryProcesses: [ProcessMemoryInfo] = []

    /// 使用者可調整的刷新頻率（秒）；所有指標（CPU / 記憶體 / 硬碟 I/O / Top-5 記憶體程式）
    /// 都是同一個 Timer 觸發、同一個 update() 裡依序更新，所以全部都會照這個頻率刷新。
    @Published var interval: TimeInterval {
        didSet {
            guard interval != oldValue else { return }
            UserDefaults.standard.set(interval, forKey: Self.intervalDefaultsKey)
            if started { restartTimer() }
        }
    }

    /// 選單列要顯示 CPU、記憶體，還是兩者都顯示
    @Published var menuBarDisplayMode: MenuBarDisplayMode {
        didSet {
            UserDefaults.standard.set(menuBarDisplayMode.rawValue, forKey: Self.displayModeDefaultsKey)
        }
    }

    private var timer: Timer?
    private var prevCPUTicks: (user: UInt32, system: UInt32, idle: UInt32, nice: UInt32)?
    private var prevDiskIOBytes: (read: UInt64, written: UInt64)?
    private var prevDiskIOTime: Date?
    private var started = false

    init() {
        let savedInterval = UserDefaults.standard.double(forKey: Self.intervalDefaultsKey)
        self.interval = savedInterval > 0 ? savedInterval : Self.defaultInterval

        let savedMode = UserDefaults.standard.string(forKey: Self.displayModeDefaultsKey)
        self.menuBarDisplayMode = MenuBarDisplayMode(rawValue: savedMode ?? "") ?? .both
    }

    func start() {
        guard !started else { return }
        started = true
        update()
        restartTimer()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        started = false
    }

    private func restartTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.update()
        }
    }

    // Timer 已經在主執行緒 RunLoop 上觸發，這裡的讀取呼叫都是同步、極快的系統呼叫，
    // 不需要再包一層 DispatchQueue.main.async，同時也讓 recordSample() 能拿到最新的值。
    private func update() {
        updateCPU()
        updateMemory()
        updateDiskCapacity()
        updateDiskIO()
        updateTopMemoryProcesses()
        recordSample()
    }

    private func recordSample() {
        samples.append(Sample(
            time: Date(),
            cpu: cpuUsage,
            mem: memUsage,
            diskReadBps: diskReadPerSec,
            diskWrittenBps: diskWrittenPerSec
        ))
        let cutoff = Date().addingTimeInterval(-Self.historyWindow)
        if let firstValidIndex = samples.firstIndex(where: { $0.time >= cutoff }) {
            if firstValidIndex > 0 {
                samples.removeFirst(firstValidIndex)
            }
        }
    }

    // MARK: - CPU

    private func updateCPU() {
        var cpuLoad = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)

        let result = withUnsafeMutablePointer(to: &cpuLoad) { ptr -> kern_return_t in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, intPtr, &count)
            }
        }
        guard result == KERN_SUCCESS else { return }

        let user = cpuLoad.cpu_ticks.0
        let system = cpuLoad.cpu_ticks.1
        let idle = cpuLoad.cpu_ticks.2
        let nice = cpuLoad.cpu_ticks.3

        if let prev = prevCPUTicks {
            let userDiff = Double(user &- prev.user)
            let sysDiff = Double(system &- prev.system)
            let idleDiff = Double(idle &- prev.idle)
            let niceDiff = Double(nice &- prev.nice)
            let total = userDiff + sysDiff + idleDiff + niceDiff
            if total > 0 {
                cpuUsage = (userDiff + sysDiff + niceDiff) / total * 100
            }
        }
        prevCPUTicks = (user, system, idle, nice)
    }

    // MARK: - Memory

    private func updateMemory() {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)

        let result = withUnsafeMutablePointer(to: &stats) { ptr -> kern_return_t in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, intPtr, &count)
            }
        }
        guard result == KERN_SUCCESS else { return }

        let pageSize = UInt64(vm_kernel_page_size)
        let wired = UInt64(stats.wire_count) * pageSize
        let used = (UInt64(stats.active_count) + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)) * pageSize
        let total = ProcessInfo.processInfo.physicalMemory

        wiredMemGB = Double(wired) / 1_073_741_824
        memUsedGB = Double(used) / 1_073_741_824
        memTotalGB = Double(total) / 1_073_741_824
        memUsage = total > 0 ? Double(used) / Double(total) * 100 : 0
    }

    // MARK: - Disk 容量（給頂部「硬碟」列使用）

    private func updateDiskCapacity() {
        let path = URL(fileURLWithPath: "/")
        guard let values = try? path.resourceValues(forKeys: [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey
        ]),
        let total = values.volumeTotalCapacity,
        let available = values.volumeAvailableCapacityForImportantUsage else { return }

        let totalD = Double(total)
        let usedD = totalD - Double(available)

        diskTotalGB = totalD / 1_073_741_824
        diskUsedGB = usedD / 1_073_741_824
        diskUsage = totalD > 0 ? usedD / totalD * 100 : 0
    }

    // MARK: - Disk 讀寫速度（給歷史走勢圖使用）
    // 用 IOKit 讀取每個 IOBlockStorageDriver 累積的讀/寫 bytes 數（跟 Activity Monitor 內部做法一樣），
    // 兩次刷新之間取差值除以經過秒數，就是即時讀寫速度 (bytes/sec)。

    private func updateDiskIO() {
        guard let current = cumulativeDiskIOBytes() else { return }
        let now = Date()

        if let prevBytes = prevDiskIOBytes, let prevTime = prevDiskIOTime {
            let elapsed = now.timeIntervalSince(prevTime)
            if elapsed > 0 {
                let readDelta = current.read >= prevBytes.read ? current.read - prevBytes.read : 0
                let writtenDelta = current.written >= prevBytes.written ? current.written - prevBytes.written : 0
                diskReadPerSec = Double(readDelta) / elapsed
                diskWrittenPerSec = Double(writtenDelta) / elapsed
            }
        }

        prevDiskIOBytes = current
        prevDiskIOTime = now
    }

    private func cumulativeDiskIOBytes() -> (read: UInt64, written: UInt64)? {
        var iterator: io_iterator_t = 0
        let matchingDict = IOServiceMatching("IOBlockStorageDriver")
        let kr = IOServiceGetMatchingServices(kIOMasterPortDefault, matchingDict, &iterator)
        guard kr == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }

        var totalRead: UInt64 = 0
        var totalWritten: UInt64 = 0

        var service = IOIteratorNext(iterator)
        while service != 0 {
            var props: Unmanaged<CFMutableDictionary>?
            if IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
               let dict = props?.takeRetainedValue() as? [String: Any],
               let stats = dict[kIOBlockStorageDriverStatisticsKey] as? [String: Any] {
                if let read = stats[kIOBlockStorageDriverStatisticsBytesReadKey] as? NSNumber {
                    totalRead += read.uint64Value
                }
                if let written = stats[kIOBlockStorageDriverStatisticsBytesWrittenKey] as? NSNumber {
                    totalWritten += written.uint64Value
                }
            }
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }

        return (totalRead, totalWritten)
    }

    // MARK: - Top 5 記憶體使用量最高的程式

    private func updateTopMemoryProcesses() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/bash")
        // rss 欄位單位是 KB；用 sort -rn -k2 依記憶體用量由高到低排序，取前 5 筆
        task.arguments = ["-c", "ps -Ao pid,rss,comm | tail -n +2 | sort -rn -k2 | head -n 5"]

        let outPipe = Pipe()
        task.standardOutput = outPipe
        task.standardError = Pipe()

        do {
            try task.run()
        } catch {
            return
        }
        task.waitUntilExit()

        let data = outPipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return }

        let totalBytes = Double(ProcessInfo.processInfo.physicalMemory)
        var results: [ProcessMemoryInfo] = []

        for rawLine in output.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            let parts = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
            guard parts.count >= 3,
                  let pid = Int32(parts[0]),
                  let rssKB = Double(parts[1]) else { continue }

            let fullName = String(parts[2])
            let shortName = (fullName as NSString).lastPathComponent
            let rssMB = rssKB / 1024
            let percent = totalBytes > 0 ? (rssKB * 1024) / totalBytes * 100 : 0

            results.append(ProcessMemoryInfo(pid: pid, name: shortName, rssMB: rssMB, percent: percent))
        }

        topMemoryProcesses = results
    }

    // MARK: - Uninstall

    /// 自我解除安裝：先用一個獨立於本行程的 shell 指令延遲刪除 .app（避免刪自己正在執行的檔案造成問題），
    /// 接著立刻結束程式。點擊選單裡的按鈕會直接執行，不會再跳確認框。
    func selfUninstall() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/bash")
        task.arguments = ["-c", "sleep 1; rm -rf '/Applications/SysMonBar.app'"]
        try? task.run()
    }
}
