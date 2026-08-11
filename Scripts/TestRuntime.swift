@_exported import Foundation

@MainActor
open class XCTestCase {
    public init() {}
    open func setUp() async throws {}
    open func tearDown() async throws {}
}

public enum TestFailure {
    nonisolated(unsafe) public static var failures: [String] = []
}

public func recordFailure(_ message: String, file: StaticString = #filePath, line: UInt = #line) {
    TestFailure.failures.append("\(file):\(line): \(message)")
}

public func XCTFail(_ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    recordFailure(message.isEmpty ? "XCTFail" : message, file: file, line: line)
}

public func XCTAssertTrue(_ expression: @autoclosure () throws -> Bool, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    do {
        if try !expression() { recordFailure(message.isEmpty ? "XCTAssertTrue failed" : message, file: file, line: line) }
    } catch {
        recordFailure("XCTAssertTrue threw: \(error)", file: file, line: line)
    }
}

public func XCTAssertFalse(_ expression: @autoclosure () throws -> Bool, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    do {
        if try expression() { recordFailure(message.isEmpty ? "XCTAssertFalse failed" : message, file: file, line: line) }
    } catch {
        recordFailure("XCTAssertFalse threw: \(error)", file: file, line: line)
    }
}

public func XCTAssertNil(_ expression: @autoclosure () throws -> Any?, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    do {
        if try expression() != nil { recordFailure(message.isEmpty ? "XCTAssertNil failed" : message, file: file, line: line) }
    } catch {
        recordFailure("XCTAssertNil threw: \(error)", file: file, line: line)
    }
}

public func XCTAssertNotNil(_ expression: @autoclosure () throws -> Any?, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    do {
        if try expression() == nil { recordFailure(message.isEmpty ? "XCTAssertNotNil failed" : message, file: file, line: line) }
    } catch {
        recordFailure("XCTAssertNotNil threw: \(error)", file: file, line: line)
    }
}

public func XCTAssertEqual<T: Equatable>(_ expression1: @autoclosure () throws -> T?, _ expression2: @autoclosure () throws -> T?, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    do {
        let lhs = try expression1()
        let rhs = try expression2()
        if lhs != rhs {
            recordFailure(message.isEmpty ? "XCTAssertEqual failed: \(String(describing: lhs)) != \(String(describing: rhs))" : message, file: file, line: line)
        }
    } catch {
        recordFailure("XCTAssertEqual threw: \(error)", file: file, line: line)
    }
}

public func XCTAssertNotEqual<T: Equatable>(_ expression1: @autoclosure () throws -> T?, _ expression2: @autoclosure () throws -> T?, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    do {
        let lhs = try expression1()
        let rhs = try expression2()
        if lhs == rhs {
            recordFailure(message.isEmpty ? "XCTAssertNotEqual failed: both are \(String(describing: lhs))" : message, file: file, line: line)
        }
    } catch {
        recordFailure("XCTAssertNotEqual threw: \(error)", file: file, line: line)
    }
}

public func XCTAssertThrowsError<T>(_ expression: @autoclosure () throws -> T, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    do {
        _ = try expression()
        recordFailure(message.isEmpty ? "XCTAssertThrowsError failed: no error thrown" : message, file: file, line: line)
    } catch {
        // expected
    }
}

public func XCTAssertThrowsError<T>(
    _ expression: @autoclosure () throws -> T,
    _ message: String = "",
    file: StaticString = #filePath,
    line: UInt = #line,
    _ errorHandler: (Error) -> Void
) {
    do {
        _ = try expression()
        recordFailure(message.isEmpty ? "XCTAssertThrowsError failed: no error thrown" : message, file: file, line: line)
    } catch {
        errorHandler(error)
    }
}

@MainActor
public func runSuite<T: XCTestCase>(_ instance: T, tests: [(T) async throws -> Void]) async -> Int {
    var failures = 0
    let suiteName = String(describing: type(of: instance))
    for test in tests {
        do {
            try await instance.setUp()
        } catch {
            print("FAIL \(suiteName): setUp threw: \(error)")
            failures += 1
            continue
        }
        let before = TestFailure.failures.count
        do {
            try await test(instance)
        } catch {
            print("FAIL \(suiteName): test threw: \(error)")
            failures += 1
            try? await instance.tearDown()
            continue
        }
        do {
            try await instance.tearDown()
        } catch {
            print("FAIL \(suiteName): tearDown threw: \(error)")
            failures += 1
            continue
        }
        let suiteFailures = TestFailure.failures.count - before
        if suiteFailures > 0 {
            for index in before..<TestFailure.failures.count {
                print("FAIL \(suiteName): \(TestFailure.failures[index])")
            }
            failures += suiteFailures
        } else {
            print("PASS \(suiteName)")
        }
    }
    return failures
}
