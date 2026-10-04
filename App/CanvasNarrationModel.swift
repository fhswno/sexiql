import Foundation
import Observation
import SQLCanvas

@MainActor
@Observable
final class CanvasNarrationModel {
    public private(set) var segments: [NarrationSegment] = []
    public var currentIndex = 0
    public private(set) var isStreaming = false
    public private(set) var streamingTail = ""
    public private(set) var error: String?
    public private(set) var isActive = false

    var currentSegment: NarrationSegment? {
        segments.indices.contains(currentIndex) ? segments[currentIndex] : nil
    }

    private var parser: CanvasNarrationParser?
    private var task: Task<Void, Never>?

    func begin(
        knownTableIDs: Set<String>,
        knownEdgeIDs: Set<String>,
        system: String,
        user: String,
        modelName: String,
        baseURLString: String
    ) {
        cancel()
        isActive = true
        isStreaming = true
        segments = []
        currentIndex = 0
        streamingTail = ""
        error = nil
        parser = CanvasNarrationParser(knownTableIDs: knownTableIDs, knownEdgeIDs: knownEdgeIDs)

        let client = OllamaClient(baseURLString: baseURLString)
        task = Task { [weak self] in
            guard let self else { return }
            defer { self.isStreaming = false }
            do {
                try await client.chatStream(model: modelName, system: system, user: user) { delta in
                    Task { @MainActor [weak self] in
                        self?.appendDelta(delta)
                    }
                }
                let tailSegments = self.parser?.finish() ?? []
                for segment in tailSegments {
                    self.segments.append(segment)
                }
                if self.segments.isEmpty, self.error == nil {
                    self.error = "The model returned nothing usable. Try again or pick a different model in Settings → AI."
                }
            } catch is CancellationError {
                // Exit mid-stream
            } catch let error as OllamaClient.ClientError where error == .cancelled {
                // User-cancelled.
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        isActive = false
        isStreaming = false
    }

    func jump(to index: Int) {
        guard !segments.isEmpty else { return }
        currentIndex = min(max(index, 0), segments.count - 1)
    }

    func step(_ delta: Int) {
        jump(to: currentIndex + delta)
    }

    private func appendDelta(_ delta: String) {
        streamingTail = String((streamingTail + delta).suffix(400))
        let newSegments = parser?.ingest(delta) ?? []
        for segment in newSegments {
            segments.append(segment)
        }
    }
}
