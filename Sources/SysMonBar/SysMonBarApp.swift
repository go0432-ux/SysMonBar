import SwiftUI
import AppKit
import Charts

@main
struct SysMonBarApp: App {
    @StateObject private var monitor = SystemMonitor()

    var body: some Scene {
        MenuBarExtra {
            MonitorView(monitor: monitor)
        } label: {
            menuBarLabel
        }
        .menuBarExtraStyle(.window)
    }

    // A single template image preserves symbols across the native status-item bridge.
    private var menuBarLabel: some View {
        Image(nsImage: MenuBarLabelImage.make(metrics: menuBarMetrics))
            .accessibilityLabel(menuBarMetrics.map { "\($0.name) \(Int($0.usage.rounded()))%" }.joined(separator: ", "))
    }

    private var menuBarMetrics: [MenuBarLabelImage.Metric] {
        switch monitor.menuBarDisplayMode {
        case .both:
            return [.init(name: "CPU", symbol: "cpu", usage: monitor.cpuUsage),
                    .init(name: "RAM", symbol: "memorychip", usage: monitor.memUsage)]
        case .cpuOnly:
            return [.init(name: "CPU", symbol: "cpu", usage: monitor.cpuUsage)]
        case .memOnly:
            return [.init(name: "RAM", symbol: "memorychip", usage: monitor.memUsage)]
        }
    }
}

// MARK: - 圖表用的指標種類

enum MetricType: String, CaseIterable, Identifiable, Hashable {
    case cpu = "CPU"
    case mem = "MEM"
    case diskRead = "READ"
    case diskWrite = "WRITE"

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .cpu: return .green
        case .mem: return .blue
        case .diskRead: return .purple
        case .diskWrite: return .pink
        }
    }

    /// CPU / 記憶體是百分比，硬碟讀寫是速度 (bytes/sec)，兩者的座標軸範圍要分開處理
    var isPercentage: Bool {
        self == .cpu || self == .mem
    }
}

// MARK: - 主視窗

struct MonitorView: View {
    @ObservedObject var monitor: SystemMonitor
    @ObservedObject private var loc = LocalizationManager.shared
    @State private var visibleMetrics: Set<MetricType> = [.cpu, .mem, .diskRead, .diskWrite]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            MetricRow(title: "CPU", icon: "cpu", percent: monitor.cpuUsage, detail: nil)
            MetricRow(
                title: L("metric.mem"), icon: "memorychip", percent: monitor.memUsage,
                detail: String(format: "%.1f / %.1f GB   ", monitor.memUsedGB, monitor.memTotalGB)
                    + String(format: L("mem.wired_format"), monitor.wiredMemGB)
            )
            MetricRow(
                title: L("metric.disk"), icon: "internaldrive", percent: monitor.diskUsage,
                detail: String(format: "%.0f / %.0f GB", monitor.diskUsedGB, monitor.diskTotalGB)
            )

            Divider()

            topMemorySection

            Divider()

            historyChart

            Divider()

            settingsSection

            Divider()

            footerButtons
        }
        .padding(16)
        .frame(width: 300)
        .onAppear {
            monitor.start()
        }
    }

    private var header: some View {
        HStack {
            Image(systemName: "gauge.medium")
                .foregroundStyle(.secondary)
            Text(L("app.title"))
                .font(.headline)
            Spacer()
        }
    }

    // MARK: 記憶體使用量最高的 5 個程式
    // 跟其他指標共用同一個 Timer，會依照「刷新頻率」設定同步更新。

    private var topMemorySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L("topmem.title"))
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(spacing: 4) {
                if monitor.topMemoryProcesses.isEmpty {
                    Text("…")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                } else {
                    ForEach(Array(monitor.topMemoryProcesses.enumerated()), id: \.element.id) { index, proc in
                        HStack(spacing: 6) {
                            Text("\(index + 1)")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(width: 12, alignment: .trailing)
                            Text(proc.name)
                                .font(.system(size: 11))
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Text(String(format: "%.0f MB", proc.rssMB))
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.secondary)
                            Text(String(format: "%.1f%%", proc.percent))
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.blue)
                                .frame(width: 38, alignment: .trailing)
                        }
                    }
                }
            }
        }
    }

    // MARK: 60 分鐘歷史走勢圖
    // CPU / MEM / 硬碟讀取 / 硬碟寫入，各自獨立一條「小型走勢圖」（像 Activity Monitor 的做法），
    // 而不是疊在同一張圖上——這樣數值再接近也不會互相交疊。
    // 只用 LineMark、不用 AreaMark：樣本點太少時，面積填色會在兩點之間撐出一大塊實心色塊。
    private var historyChart: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L("chart.title"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                metricToggles
            }

            VStack(spacing: 8) {
                ForEach(MetricType.allCases) { metric in
                    if visibleMetrics.contains(metric) {
                        metricLane(metric)
                    }
                }
            }

            if !monitor.samples.isEmpty {
                HStack {
                    Text(L("chart.start"))
                    Spacer()
                    Text(L("chart.now"))
                }
                .font(.system(size: 8))
                .foregroundStyle(.tertiary)
            }
        }
    }

    private func metricLane(_ metric: MetricType) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Circle().fill(metric.color).frame(width: 6, height: 6)
                Text(metric.rawValue)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(formattedCurrentValue(for: metric))
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(metric.color)
            }
            Chart(monitor.samples) { sample in
                LineMark(
                    x: .value("Time", sample.time),
                    y: .value(metric.rawValue, value(for: metric, sample: sample))
                )
                .foregroundStyle(metric.color)
                .interpolationMethod(.catmullRom)
                .lineStyle(StrokeStyle(lineWidth: 1.5))
            }
            .chartYScale(domain: 0...yAxisMax(for: metric))
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .frame(height: 36)
            .background(Color.gray.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 4))
        }
    }

    private func value(for metric: MetricType, sample: Sample) -> Double {
        switch metric {
        case .cpu: return sample.cpu
        case .mem: return sample.mem
        case .diskRead: return sample.diskReadBps
        case .diskWrite: return sample.diskWrittenBps
        }
    }

    private func yAxisMax(for metric: MetricType) -> Double {
        if metric.isPercentage { return 100 }
        let maxVal = monitor.samples.map { value(for: metric, sample: $0) }.max() ?? 0
        return max(maxVal * 1.2, 1_048_576)   // 讀寫速度沒有固定上限，動態抓最大值；至少留 1MB/s 的空間避免圖表太平
    }

    private func formattedCurrentValue(for metric: MetricType) -> String {
        switch metric {
        case .cpu: return String(format: "%.0f%%", monitor.cpuUsage)
        case .mem: return String(format: "%.0f%%", monitor.memUsage)
        case .diskRead: return formatBytesPerSec(monitor.diskReadPerSec)
        case .diskWrite: return formatBytesPerSec(monitor.diskWrittenPerSec)
        }
    }

    private func formatBytesPerSec(_ bps: Double) -> String {
        if bps >= 1_048_576 {
            return String(format: "%.1f MB/s", bps / 1_048_576)
        } else if bps >= 1024 {
            return String(format: "%.0f KB/s", bps / 1024)
        } else {
            return String(format: "%.0f B/s", bps)
        }
    }

    private var metricToggles: some View {
        HStack(spacing: 6) {
            ForEach(MetricType.allCases) { metric in
                Button {
                    if visibleMetrics.contains(metric) {
                        visibleMetrics.remove(metric)
                    } else {
                        visibleMetrics.insert(metric)
                    }
                } label: {
                    HStack(spacing: 3) {
                        Circle().fill(metric.color).frame(width: 6, height: 6)
                        Text(metric.rawValue).font(.system(size: 9, weight: .medium))
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        visibleMetrics.contains(metric)
                            ? metric.color.opacity(0.15)
                            : Color.gray.opacity(0.12)
                    )
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .opacity(visibleMetrics.contains(metric) ? 1 : 0.45)
            }
        }
    }

    // MARK: 設定：刷新頻率 + 選單列主要顯示 + 語言

    private var settingsSection: some View {
        VStack(spacing: 10) {
            HStack {
                Text(L("settings.refresh"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Picker("", selection: $monitor.interval) {
                    ForEach(SystemMonitor.availableIntervals, id: \.self) { seconds in
                        Text(String(format: L("settings.seconds_format"), Int(seconds)))
                            .tag(seconds)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 90)
            }

            HStack {
                Text(L("settings.menubar_primary"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Picker("", selection: $monitor.menuBarDisplayMode) {
                    Text(L("settings.menubar_both")).tag(MenuBarDisplayMode.both)
                    Text(L("settings.menubar_cpu_only")).tag(MenuBarDisplayMode.cpuOnly)
                    Text(L("settings.menubar_mem_only")).tag(MenuBarDisplayMode.memOnly)
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 130)
            }

            HStack {
                Text(L("lang.title"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Picker("", selection: $loc.languageCode) {
                    ForEach(LocalizationManager.options) { option in
                        Text(option.displayName ?? L("lang.system_default"))
                            .tag(option.code)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 130)
            }
        }
    }

    // MARK: 底部按鈕
    // 「解除安裝」點下去直接執行，不再跳確認框。

    private var footerButtons: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                monitor.selfUninstall()
                NSApplication.shared.terminate(nil)
            } label: {
                HStack {
                    Image(systemName: "trash")
                    Text(L("uninstall.button"))
                    Spacer()
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.red)
            .font(.caption)

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                HStack {
                    Image(systemName: "power")
                    Text(L("quit.button"))
                    Spacer()
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .font(.caption)
        }
    }
}

// MARK: - 單一指標列（含進度條）

struct MetricRow: View {
    let title: String
    let icon: String
    let percent: Double
    let detail: String?

    private var color: Color {
        if percent >= 85 { return .red }
        if percent >= 60 { return .orange }
        return .green
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label {
                    Text(title)
                } icon: {
                    Image(systemName: icon)
                }
                .font(.system(size: 13, weight: .medium))
                Spacer()
                Text(String(format: "%.0f%%", percent))
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(color)
            }
            ProgressView(value: min(max(percent, 0), 100), total: 100)
                .tint(color)
            if let detail {
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
