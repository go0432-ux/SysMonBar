import AppKit
import Foundation

@main
struct MonitorLifecycleChecks {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.finishLaunching()
        let monitor = SystemMonitor()
        monitor.interval = 1
        monitor.start()
        defer { monitor.stop() }
        let initialSamples = monitor.samples.count
        RunLoop.current.run(until: Date().addingTimeInterval(2.2))
        precondition(monitor.samples.count >= initialSamples + 2, "Hidden core sampling must continue")
        precondition(!monitor.processSnapshotAvailable && monitor.allMemoryApps.isEmpty,
                     "Starting hidden must not scan processes")

        let anchor = ProcessPanelVisibilityView()
        var states: [Bool] = []
        anchor.onChange = { visible in
            if states.last != visible { states.append(visible) }
            monitor.setProcessListVisible(visible)
        }
        let window = NSWindow(contentRect: NSRect(x: -3000, y: 0, width: 100, height: 100),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = anchor
        window.orderFront(nil)
        waitUntil { monitor.processSnapshotAvailable }
        precondition(!monitor.allMemoryApps.isEmpty, "Opening the exact window must immediately refresh apps")

        let sentinel = AppMemoryInfo(id: "cached-row", name: "cached-row", pids: [], residentBytes: 1)
        monitor.allMemoryApps = [sentinel]
        monitor.setProcessListVisible(true)
        precondition(monitor.allMemoryApps.first?.id == sentinel.id,
                     "Repeated visible notifications must not rescan")

        window.orderOut(nil)
        waitUntil { states.last == false }
        monitor.allMemoryApps = [sentinel]
        let closedSamples = monitor.samples.count
        RunLoop.current.run(until: Date().addingTimeInterval(2.2))
        precondition(monitor.allMemoryApps.first?.id == sentinel.id,
                     "A retained but hidden native window must keep cached rows without scanning")
        precondition(monitor.samples.count >= closedSamples + 2,
                     "Closing the panel must preserve CPU, memory, disk and history sampling")

        window.orderFront(nil)
        waitUntil { monitor.allMemoryApps.first?.id != sentinel.id }
        precondition(monitor.processSnapshotAvailable, "Reopening must refresh the process list")
        window.orderOut(nil)
        waitUntil { states.last == false }
        precondition(states == [false, true, false, true, false], "Native visibility transitions must be exact")
        precondition(monitor.topMemoryApps.count <= 5 && monitor.allMemoryApps.count >= monitor.topMemoryApps.count)
        window.orderFront(nil)
        anchor.stopObserving()
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        precondition(states.last == false, "Dismantled anchors must ignore queued visibility callbacks")
        window.orderOut(nil)
        print("PASS: closed-window scan suppression, continued history, immediate reopen, idempotent visibility, native KVO")
    }

    @MainActor static func waitUntil(_ condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(3)
        while !condition() && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
        precondition(condition(), "Lifecycle condition did not become true")
    }
}
