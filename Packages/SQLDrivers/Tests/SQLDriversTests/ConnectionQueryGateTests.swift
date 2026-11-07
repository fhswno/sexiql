import XCTest
@testable import SQLDrivers

final class ConnectionQueryGateTests: XCTestCase {
    private actor PeakCounter {
        private var inside = 0
        private(set) var maximum = 0
        func enter() {
            inside += 1
            maximum = max(maximum, inside)
        }
        func exit() {
            inside -= 1
        }
    }

    private actor Flag {
        private var value = false
        func set() { value = true }
        func get() -> Bool { value }
    }

    func testConcurrentAcquiresAreSerialized() async {
        let gate = ConnectionQueryGate()
        let counter = PeakCounter()

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<50 {
                group.addTask {
                    await gate.acquire()
                    await counter.enter()
                    try? await Task.sleep(for: .microseconds(200))
                    await counter.exit()
                    await gate.release()
                }
            }
        }

        let peak = await counter.maximum
        XCTAssertEqual(peak, 1, "at most one operation may hold the gate at a time")
    }

    func testReleaseHandsOwnershipToOneWaiter() async {
        let gate = ConnectionQueryGate()
        let secondAcquired = Flag()

        await gate.acquire()

        async let second: Void = {
            await gate.acquire()
            await secondAcquired.set()
            await gate.release()
        }()

        try? await Task.sleep(for: .milliseconds(100))
        let early = await secondAcquired.get()
        XCTAssertFalse(early, "waiter must not acquire before release")

        await gate.release()

        for _ in 0..<20 {
            if await secondAcquired.get() { break }
            try? await Task.sleep(for: .milliseconds(25))
        }
        let handed = await secondAcquired.get()
        XCTAssertTrue(handed, "waiter must acquire after release")
        await second
    }

    func testResetResumesAllWaiters() async {
        let gate = ConnectionQueryGate()
        let resumedCount = Flag()
        let first = Flag()
        let second = Flag()

        await gate.acquire()

        async let _: Void = { await gate.acquire(); await first.set() }()
        async let _: Void = { await gate.acquire(); await second.set() }()

        try? await Task.sleep(for: .milliseconds(100))
        await gate.reset()

        for _ in 0..<40 {
            if await first.get(), await second.get() { break }
            try? await Task.sleep(for: .milliseconds(25))
        }

        let f = await first.get()
        let s = await second.get()
        XCTAssertTrue(f, "first waiter must be resumed by reset")
        XCTAssertTrue(s, "second waiter must be resumed by reset")
        _ = resumedCount
    }
}
