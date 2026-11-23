import AppKit
import Darwin

struct ProcessTerminationTarget: Equatable {
    let pid: pid_t
    let startedSeconds: UInt64
    let startedMicroseconds: UInt64

    static func capture(pid: pid_t) -> Self? {
        guard pid > 1, pid != getpid() else { return nil }
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size,
              info.pbi_uid == getuid() else { return nil }
        return Self(pid: pid, startedSeconds: info.pbi_start_tvsec,
                    startedMicroseconds: info.pbi_start_tvusec)
    }

    func requestAppTermination(bundlePath: String) -> Bool {
        // Revalidate the process identity after confirmation, since PIDs are reused.
        guard Self.capture(pid: pid) == self,
              let app = NSRunningApplication(processIdentifier: pid),
              app.activationPolicy == .regular,
              app.bundleURL?.path == bundlePath else { return false }
        return app.terminate()
    }
}
