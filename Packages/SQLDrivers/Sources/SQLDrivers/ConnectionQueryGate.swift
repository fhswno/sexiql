import Foundation

public actor ConnectionQueryGate {
    private var held = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    public init() {}

    public func acquire() async {
        if held {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                waiters.append(continuation)
            }
        }
        held = true
    }

    public func release() {
        if let next = waiters.first {
            waiters.removeFirst()
            next.resume()
        } else {
            held = false
        }
    }

    public func reset() {
        held = false
        let pending = waiters
        waiters = []
        for waiter in pending {
            waiter.resume()
        }
    }
}
