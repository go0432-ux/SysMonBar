import Foundation

struct ProcessMemorySample: Identifiable {
    let pid: Int32
    let executable: String
    let residentBytes: Double
    var id: Int32 { pid }
    var name: String { (executable as NSString).lastPathComponent }

    var appPath: String? {
        // Use the outer bundle so Chromium's nested helper apps share one entry.
        guard let range = executable.range(of: ".app/", options: .caseInsensitive) else { return nil }
        return String(executable[..<range.upperBound].dropLast())
    }
}

struct AppMemoryInfo: Identifiable {
    let id: String
    var name: String
    var pids: [Int32]
    var residentBytes: Double
    var terminationTarget: ProcessTerminationTarget?
}

struct AppMemorySnapshot {
    let apps: [AppMemoryInfo]
    let allApps: [AppMemoryInfo]
    let standaloneProcesses: [ProcessMemorySample]
    let otherResidentBytes: Double

    static func parse(_ output: String) -> [ProcessMemorySample] {
        output.split(separator: "\n").compactMap { line in
            let fields = line.split(maxSplits: 2, omittingEmptySubsequences: true, whereSeparator: { $0.isWhitespace })
            guard fields.count == 3, let pid = Int32(fields[0]), pid > 0,
                  let rss = Double(fields[1]), rss.isFinite, rss >= 0 else { return nil }
            return ProcessMemorySample(pid: pid, executable: String(fields[2]), residentBytes: rss * 1024)
        }
    }

    static func make(processes: [ProcessMemorySample], limit: Int = 5) -> Self {
        var groups: [String: AppMemoryInfo] = [:]
        var total: Double = 0
        for process in processes {
            total += process.residentBytes
            guard let path = process.appPath else { continue }
            var app = groups[path] ?? AppMemoryInfo(id: path,
                name: URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent,
                pids: [], residentBytes: 0)
            app.pids.append(process.pid)
            app.residentBytes += process.residentBytes
            groups[path] = app
        }
        let allApps = groups.values.sorted {
            $0.residentBytes == $1.residentBytes ? $0.id < $1.id : $0.residentBytes > $1.residentBytes
        }
        let apps = Array(allApps.prefix(max(0, limit)))
        let standalone = processes.filter { $0.appPath == nil }.sorted {
            $0.residentBytes == $1.residentBytes ? $0.pid < $1.pid : $0.residentBytes > $1.residentBytes
        }
        return Self(apps: apps, allApps: allApps, standaloneProcesses: standalone,
                    otherResidentBytes: max(0, total - apps.reduce(0) { $0 + $1.residentBytes }))
    }
}

struct MemoryBreakdown {
    let appBytes: Double
    let systemBytes: Double
    let compressedBytes: Double
    var usedBytes: Double { appBytes + systemBytes + compressedBytes }

    init(anonymousPages: UInt64, purgeablePages: UInt64, wiredPages: UInt64,
         compressorPages: UInt64, pageSize: UInt64) {
        appBytes = Double(anonymousPages - min(anonymousPages, purgeablePages)) * Double(pageSize)
        systemBytes = Double(wiredPages) * Double(pageSize)
        compressedBytes = Double(compressorPages) * Double(pageSize)
    }
}
