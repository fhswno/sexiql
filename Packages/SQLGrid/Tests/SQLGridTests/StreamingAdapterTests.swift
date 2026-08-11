import XCTest
@testable import SQLGrid
import SQLDrivers

final class StreamingAdapterTests: XCTestCase {
    private func makeColumns() -> [GridColumn] {
        [GridColumn(ordinal: 0, name: "n", dataType: "int4")]
    }

    private func makeStream(_ rows: [SQLRow], error: Error? = nil) -> RowStream {
        RowStream { continuation in
            for row in rows {
                continuation.yield(row)
            }
            if let error {
                continuation.finish(throwing: error)
            } else {
                continuation.finish()
            }
        }
    }

    func testBatchBoundariesAndCompletion() async {
        let rows = (1...600).map { SQLRow(values: [.int(Int64($0))]) }
        let adapter = StreamingAdapter(batchSize: 250)
        let updates = MutexCounter()

        let result = await adapter.consume(makeStream(rows), initialColumns: makeColumns()) { _ in
            updates.increment()
        }
        guard case .success(let model) = result else {
            XCTFail("expected success")
            return
        }
        XCTAssertEqual(model.rows.count, 600)
        XCTAssertEqual(model.totalRowCount, 600)
        XCTAssertTrue(model.isComplete)
        XCTAssertEqual(updates.value, 3)
    }

    func testEmptyStreamFinishesImmediately() async {
        let adapter = StreamingAdapter(batchSize: 100)
        let result = await adapter.consume(makeStream([]), initialColumns: makeColumns()) { _ in }
        guard case .success(let model) = result else {
            XCTFail("expected success")
            return
        }
        XCTAssertTrue(model.isComplete)
        XCTAssertEqual(model.totalRowCount, 0)
    }

    func testErrorSurfacedWithPartialRows() async {
        let rows = (1...300).map { SQLRow(values: [.int(Int64($0))]) }
        let adapter = StreamingAdapter(batchSize: 200)
        let failure = SQLDriverError.connectionFailed(message: "mid-stream failure")

        let result = await adapter.consume(makeStream(rows, error: failure), initialColumns: makeColumns()) { _ in }
        guard case .failure(let error) = result else {
            XCTFail("expected failure")
            return
        }
        XCTAssertEqual(error as? SQLDriverError, failure)
    }
}

final class MutexCounter: @unchecked Sendable {
    private let lock = NSRecursiveLock()
    private var _value = 0

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return _value
    }

    func increment() {
        lock.lock()
        defer { lock.unlock() }
        _value += 1
    }
}
