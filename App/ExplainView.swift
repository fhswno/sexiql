import SwiftUI
import AppKit
import SQLExplainer
import SQLUI

struct ExplainView: View {
    @Environment(WorkspaceModel.self) private var model
    let tabID: UUID
    let plan: ExplainNode

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: SexiQLSpace.md) {
                Label("Query Plan", systemImage: "point.3.connected.trianglepath.dotted")
                    .font(.callout.weight(.semibold))
                Spacer()
                Button {
                    copyPlan()
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .help("Copy plan as text")
                Button("Back to Results") {
                    model.clearExplain(tabID)
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.bar)

            if let summary = planSummary {
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(nsColor: .controlBackgroundColor).opacity(0.6))
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    planNode(plan, depth: 0)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var planSummary: String? {
        let leaves = collectLeaves(plan)
        guard leaves.count == 1, let leaf = leaves.first else { return nil }
        let detail = leaf.detail["Detail"] ?? leaf.nodeType
        let upper = detail.uppercased()
        if upper.contains("USING INDEX") || upper.contains("SEARCH ") {
            return "Uses an index lookup."
        }
        if upper.hasPrefix("SCAN ") || leaf.nodeType.uppercased() == "SCAN" || leaf.nodeType.uppercased().contains("SEQ SCAN") {
            let rel = leaf.relation.map { " on \($0)" } ?? ""
            return "Full table scan\(rel) — no covering index used for this access path."
        }
        return nil
    }

    private func collectLeaves(_ node: ExplainNode) -> [ExplainNode] {
        if node.children.isEmpty { return [node] }
        if node.nodeType == "QUERY PLAN" {
            return node.children.flatMap { collectLeaves($0) }
        }
        return node.children.flatMap { collectLeaves($0) }
    }

    private func planNode(_ node: ExplainNode, depth: Int) -> AnyView {
        if node.children.isEmpty {
            return AnyView(nodeCard(node))
        }
        return AnyView(
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(node.children) { child in
                        planNode(child, depth: depth + 1)
                    }
                }
                .padding(.leading, 14)
            } label: {
                nodeCard(node)
            }
            .tint(.secondary)
        )
    }

    private func nodeCard(_ node: ExplainNode) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: iconName(for: node))
                    .font(.caption)
                    .foregroundStyle(iconColor(for: node))
                    .frame(width: 14)

                Text(node.nodeType)
                    .font(.callout.weight(.semibold))

                if let relation = node.relation, !relation.isEmpty {
                    Text(relation)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Color.secondary.opacity(0.12), in: Capsule())
                }

                Spacer(minLength: 8)

                if let cost = node.totalCost {
                    metric("cost", String(format: "%.2f", cost))
                }
                if let rows = node.actualRows ?? node.planRows {
                    metric("rows", String(format: "%.0f", rows))
                }
            }

            if let detail = node.detail["Detail"], !detail.isEmpty,
               detail != node.nodeType,
               detail != "\(node.nodeType) \(node.relation ?? "")".trimmingCharacters(in: .whitespaces) {
                Text(detail)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }

            let extras = node.detail
                .filter { $0.key != "Detail" && !$0.value.isEmpty }
                .sorted { $0.key < $1.key }
            if !extras.isEmpty {
                FlowMetrics(pairs: extras.map { ($0.key, $0.value) })
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .textSelection(.enabled)
    }

    private func metric(_ label: String, _ value: String) -> some View {
        Text("\(label) \(value)")
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.tertiary)
    }

    private func iconName(for node: ExplainNode) -> String {
        let t = node.nodeType.uppercased()
        if t.contains("SCAN") { return "tablecells" }
        if t.contains("SEARCH") || t.contains("INDEX") { return "magnifyingglass" }
        if t.contains("JOIN") { return "arrow.triangle.merge" }
        if t.contains("SORT") { return "arrow.up.arrow.down" }
        if t.contains("LIMIT") { return "scissors" }
        return "arrow.triangle.branch"
    }

    private func iconColor(for node: ExplainNode) -> Color {
        let t = node.nodeType.uppercased()
        let detail = (node.detail["Detail"] ?? "").uppercased()
        if t.contains("SCAN") && !detail.contains("USING INDEX") && !t.contains("INDEX") {
            return .orange
        }
        if t.contains("INDEX") || t.contains("SEARCH") {
            return .green
        }
        return .secondary
    }

    private func copyPlan() {
        let text = formatPlan(plan, indent: 0)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func formatPlan(_ node: ExplainNode, indent: Int) -> String {
        let pad = String(repeating: "  ", count: indent)
        var line = "\(pad)\(node.nodeType)"
        if let relation = node.relation { line += " \(relation)" }
        if let detail = node.detail["Detail"], detail != node.nodeType {
            line += " — \(detail)"
        }
        if let cost = node.totalCost {
            line += String(format: "  [cost %.2f]", cost)
        }
        if let rows = node.actualRows ?? node.planRows {
            line += String(format: "  [%.0f rows]", rows)
        }
        var lines = [line]
        for child in node.children {
            lines.append(formatPlan(child, indent: indent + 1))
        }
        return lines.joined(separator: "\n")
    }
}

private struct FlowMetrics: View {
    let pairs: [(String, String)]

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(pairs.enumerated()), id: \.offset) { _, pair in
                Text("\(pair.0): \(pair.1)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .textSelection(.enabled)
            }
        }
    }
}
