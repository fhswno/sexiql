import Foundation
import SQLDrivers

public struct StreamingAdapter: Sendable {
    public static let defaultMaxRows = 1_000_000

    public var batchSize: Int
    public var maxRows: Int

    public init(batchSize: Int = 250, maxRows: Int = StreamingAdapter.defaultMaxRows) {
        self.batchSize = batchSize
        self.maxRows = maxRows
    }

    public func consume(
        _ rows: RowStream,
        initialColumns: [GridColumn],
        onUpdate: @escaping @Sendable @MainActor (ResultSetModel) -> Void
    ) async -> Result<ResultSetModel, Error> {
        var model = ResultSetModel(columns: initialColumns)
        var pending: [SQLRow] = []
        pending.reserveCapacity(batchSize)
        var buffered = 0
        var reachedCap = false
        var discardedRow = false

        do {
            for try await row in rows {
                if Task.isCancelled {
                    model.append(contentsOf: pending)
                    model.finish()
                    await MainActor.run { onUpdate(model) }
                    return .failure(SQLDriverError.cancelled)
                }
                if reachedCap {
                    discardedRow = true
                    continue
                }
                pending.append(row)
                buffered += 1
                if model.rows.count + pending.count >= maxRows {
                    reachedCap = true
                    model.append(contentsOf: pending)
                    pending.removeAll(keepingCapacity: true)
                    buffered = 0
                    await MainActor.run { onUpdate(model) }
                    await Task.yield()
                    continue
                }
                if buffered >= batchSize {
                    model.append(contentsOf: pending)
                    pending.removeAll(keepingCapacity: true)
                    buffered = 0
                    await MainActor.run { onUpdate(model) }
                    await Task.yield()
                }
            }
            model.append(contentsOf: pending)
            if reachedCap && discardedRow {
                model.markTruncated()
                model.finish(totalRowCount: maxRows)
            } else {
                model.finish()
            }
            await MainActor.run { onUpdate(model) }
            return .success(model)
        } catch is CancellationError {
            model.append(contentsOf: pending)
            model.finish()
            await MainActor.run { onUpdate(model) }
            return .failure(SQLDriverError.cancelled)
        } catch {
            model.append(contentsOf: pending)
            model.finish()
            await MainActor.run { onUpdate(model) }
            return .failure(error)
        }
    }
}
