import Foundation
import HairballUI
import Hairball

/// Manages per-item `StreamingMarkdownRenderer` instances so streaming deltas
/// flow through `append()` and the continuous token reveal works from the first
/// token.
@MainActor
final class StreamingRendererCoordinator {
    static let shared = StreamingRendererCoordinator()

    private var renderers: [String: StreamingMarkdownRenderer] = [:]
    private var activeItemId: String?
    private var pendingDeltas: [String: String] = [:]
    private var flushTask: Task<Void, Never>?

    // MARK: - Delta feeding

    func appendDelta(_ delta: String, for itemId: String, seedText: @autoclosure () -> String? = nil) {
        guard !delta.isEmpty else { return }
        if renderers[itemId] == nil {
            // The view may not exist yet, and its snapshot can lag the token
            // stream. Seed once from the snapshot plus its unflushed deltas,
            // before queuing this new delta. Never buffer against an unknown
            // baseline: a later full snapshot already contains those bytes.
            guard let seed = seedText() else { return }
            _ = renderer(for: itemId, currentText: seed)
        }
        if activeItemId != itemId {
            if let oldId = activeItemId {
                flushPendingDeltas(for: oldId)
                renderers[oldId]?.finish()
            }
            activeItemId = itemId
        }
        // Batch renderer work so streamed tokens do not compete with composer input.
        pendingDeltas[itemId, default: ""] += delta
        scheduleFlush()
        // Only the flush path appends. Appending here as well would render
        // every chunk twice when the batching timer fires.
    }

    // MARK: - Renderer access

    func renderer(for itemId: String, currentText: String) -> StreamingMarkdownRenderer {
        if let existing = renderers[itemId] {
            return existing
        }
        let r = makeRenderer(for: itemId)
        if !currentText.isEmpty {
            r.append(currentText)
        }
        return r
    }

    func finish(itemId: String) {
        flushPendingDeltas(for: itemId)
        if let r = renderers.removeValue(forKey: itemId) {
            r.finish()
        }
    }

    // MARK: - Streaming lifecycle

    func finishActive() {
        flushAllPendingDeltas()
        for (_, r) in renderers {
            if !r.isFinished { r.finish() }
        }
        activeItemId = nil
    }

    func reset() {
        flushTask?.cancel()
        flushTask = nil
        pendingDeltas.removeAll()
        for (_, r) in renderers { r.finish() }
        renderers.removeAll()
        activeItemId = nil
    }

    // MARK: - Private

    private func scheduleFlush() {
        guard flushTask == nil else { return }
        flushTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 16_000_000)
            guard !Task.isCancelled, let self else { return }
            self.flushAllPendingDeltas()
            self.flushTask = nil
        }
    }

    private func flushPendingDeltas(for itemId: String) {
        guard let delta = pendingDeltas.removeValue(forKey: itemId), !delta.isEmpty else { return }
        renderers[itemId]?.append(delta)
    }

    private func flushAllPendingDeltas() {
        flushTask?.cancel()
        flushTask = nil
        let deltas = pendingDeltas
        pendingDeltas.removeAll()
        for (itemId, delta) in deltas where !delta.isEmpty {
            renderers[itemId]?.append(delta)
        }
    }

    private func makeRenderer(for itemId: String) -> StreamingMarkdownRenderer {
        let r = StreamingMarkdownRenderer(
            processors: [LatexTransformer()],
            throttleInterval: 0.016
        )
        renderers[itemId] = r
        return r
    }
}
