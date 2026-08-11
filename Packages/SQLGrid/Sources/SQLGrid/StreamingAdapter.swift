import Foundation
import SQLDrivers

public struct StreamingAdapter: Sendable {
    public var batchSize: Int

    public init(batchSize: Int = 250) {
        self.batchSize = batchSize
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

        do {
            for try await row in rows {
                if Task.isCancelled {
                    model.append(contentsOf: pending)
                    model.finish()
                    await MainActor.run { onUpdate(model) }
                    return .failure(SQLDriverError.cancelled)
                }
                pending.append(row)
                buffered += 1
                if buffered >= batchSize {
                    model.append(contentsOf: pending)
                    pending.removeAll(keepingCapacity: true)
                    buffered = 0
                    await MainActor.run { onUpdate(model) }
                    await Task.yield()
                }
            }
            model.append(contentsOf: pending)
            model.finish()
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
