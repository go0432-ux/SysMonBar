import Foundation

func XCTAssertEqual<T: Equatable>(_ left: T, _ right: T) { precondition(left == right) }
func XCTAssertNotEqual<T: Equatable>(_ left: T, _ right: T) { precondition(left != right) }
func XCTAssertTrue(_ value: Bool) { precondition(value) }
func XCTAssertFalse(_ value: Bool) { precondition(!value) }
func XCTAssertNil<T>(_ value: T?) { precondition(value == nil) }
func XCTUnwrap<T>(_ value: T?) throws -> T { precondition(value != nil); return value! }

@main
struct MemoryChecks {
    static func main() throws {
        testNestedHelpersAreRankedWithTheirOuterApp()
        testOtherIncludesAppsOutsideTopFiveAndStandaloneProcesses()
        testDistinctBundlesWithSameNameAreNotMerged()
        testParserRejectsInvalidRowsAndPreservesSpaces()
        testMemoryBreakdownUsesPhysicalCompressorPagesOnce()
        testExpandedListRetainsEveryAppAndStandaloneProcess()
        try testQuitCannotTargetProtectedPIDsOrAnUnrelatedBundle()
        print("PASS: 7 memory grouping, expansion, accounting, parsing and safe termination checks")
    }

    static func testNestedHelpersAreRankedWithTheirOuterApp() {
        // The same snapshot retains full results for expansion without resampling.
        let processes = AppMemorySnapshot.parse("""
        10 1024 /Applications/Brave Browser.app/Contents/MacOS/Brave Browser
        11 2048 /Applications/Brave Browser.app/Contents/Frameworks/Helper.app/Contents/MacOS/Helper
        12 2500 /Applications/Other.app/Contents/MacOS/Other
        13 512 /usr/libexec/service
        """)
        let snapshot = AppMemorySnapshot.make(processes: processes)
        XCTAssertEqual(snapshot.apps.map(\.name), ["Brave Browser", "Other"])
        XCTAssertEqual(snapshot.apps.first?.pids, [10, 11])
        XCTAssertEqual(snapshot.apps.first?.residentBytes, 3072 * 1024)
        XCTAssertEqual(snapshot.otherResidentBytes, 512 * 1024)
    }

    static func testOtherIncludesAppsOutsideTopFiveAndStandaloneProcesses() {
        var processes = (1...6).map {
            ProcessMemorySample(pid: Int32($0 + 20), executable: "/Applications/App\($0).app/Contents/MacOS/main",
                                residentBytes: Double($0) * 1024)
        }
        processes.append(.init(pid: 100, executable: "/usr/libexec/service", residentBytes: 500))
        let snapshot = AppMemorySnapshot.make(processes: processes)
        XCTAssertEqual(snapshot.apps.count, 5)
        XCTAssertEqual(snapshot.apps.first?.name, "App6")
        XCTAssertEqual(snapshot.otherResidentBytes, 1024 + 500)
        XCTAssertEqual(snapshot.apps.reduce(0) { $0 + $1.residentBytes } + snapshot.otherResidentBytes,
                       processes.reduce(0) { $0 + $1.residentBytes })
    }

    static func testExpandedListRetainsEveryAppAndStandaloneProcess() {
        var processes = (1...8).map {
            ProcessMemorySample(pid: Int32($0 + 20), executable: "/Applications/App\($0).app/Contents/MacOS/main",
                                residentBytes: Double($0) * 1024)
        }
        processes += [
            .init(pid: 100, executable: "/usr/libexec/background", residentBytes: 900),
            .init(pid: 101, executable: "/usr/bin/worker", residentBytes: 500)
        ]
        let snapshot = AppMemorySnapshot.make(processes: processes)
        XCTAssertEqual(snapshot.apps.count, 5)
        XCTAssertEqual(snapshot.allApps.count, 8)
        XCTAssertEqual(snapshot.apps.map(\.id), Array(snapshot.allApps.prefix(5)).map(\.id))
        XCTAssertEqual(snapshot.allApps.last?.name, "App1")
        XCTAssertEqual(snapshot.standaloneProcesses.map(\.pid), [100, 101])
        XCTAssertEqual(snapshot.allApps.reduce(0) { $0 + $1.residentBytes }
                       + snapshot.standaloneProcesses.reduce(0) { $0 + $1.residentBytes },
                       processes.reduce(0) { $0 + $1.residentBytes })
        XCTAssertEqual(AppMemorySnapshot.make(processes: []).allApps.count, 0)
        XCTAssertEqual(AppMemorySnapshot.make(processes: []).standaloneProcesses.count, 0)
    }

    static func testDistinctBundlesWithSameNameAreNotMerged() {
        let snapshot = AppMemorySnapshot.make(processes: [
            .init(pid: 10, executable: "/Applications/Browser.app/Contents/MacOS/main", residentBytes: 10),
            .init(pid: 11, executable: "/Users/test/Browser.app/Contents/MacOS/main", residentBytes: 10)
        ])
        XCTAssertEqual(snapshot.apps.count, 2)
        XCTAssertNotEqual(snapshot.apps[0].id, snapshot.apps[1].id)
    }

    static func testParserRejectsInvalidRowsAndPreservesSpaces() {
        let samples = AppMemorySnapshot.parse("""
        invalid
        10 -1 /bad.app/main
        11 nan /bad.app/main
        12 500 /Applications/Has Spaces.app/Contents/MacOS/Has Spaces
        """)
        XCTAssertEqual(samples.count, 1)
        XCTAssertEqual(samples[0].appPath, "/Applications/Has Spaces.app")
        XCTAssertEqual(AppMemorySnapshot.make(processes: []).otherResidentBytes, 0)
    }

    static func testMemoryBreakdownUsesPhysicalCompressorPagesOnce() {
        let breakdown = MemoryBreakdown(anonymousPages: 100, purgeablePages: 20,
            wiredPages: 10, compressorPages: 30, pageSize: 4096)
        XCTAssertEqual(breakdown.appBytes, 80 * 4096)
        XCTAssertEqual(breakdown.systemBytes, 10 * 4096)
        XCTAssertEqual(breakdown.compressedBytes, 30 * 4096)
        XCTAssertEqual(breakdown.usedBytes, 120 * 4096)
        let changingSnapshot = MemoryBreakdown(anonymousPages: 10, purgeablePages: 20,
            wiredPages: 1, compressorPages: 2, pageSize: 4096)
        XCTAssertEqual(changingSnapshot.appBytes, 0)
    }

    static func testQuitCannotTargetProtectedPIDsOrAnUnrelatedBundle() throws {
        XCTAssertNil(ProcessTerminationTarget.capture(pid: 0))
        XCTAssertNil(ProcessTerminationTarget.capture(pid: 1))
        XCTAssertNil(ProcessTerminationTarget.capture(pid: ProcessInfo.processInfo.processIdentifier))
        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/bin/sleep")
        child.arguments = ["60"]
        try child.run()
        defer { if child.isRunning { child.terminate(); child.waitUntilExit() } }
        let target = try XCTUnwrap(ProcessTerminationTarget.capture(pid: child.processIdentifier))
        XCTAssertFalse(target.requestAppTermination(bundlePath: "/Applications/Unrelated.app"))
        XCTAssertTrue(child.isRunning)
        let stale = ProcessTerminationTarget(pid: target.pid, startedSeconds: target.startedSeconds + 1,
                                             startedMicroseconds: target.startedMicroseconds)
        XCTAssertFalse(stale.requestAppTermination(bundlePath: "/Applications/Unrelated.app"))
    }
}
