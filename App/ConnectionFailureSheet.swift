import AppKit
import SwiftUI
import SQLUI

struct ConnectionFailureSheet: View {
    @Environment(WorkspaceModel.self) private var model
    let failure: ConnectionFailure

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: SexiQLSpace.lg) {
                    meta
                    messageBlock
                    if failure.technicalDetail != failure.message {
                        technicalBlock
                    }
                }
                .padding(SexiQLSpace.xl)
            }
            Divider()
            footer
        }
        .frame(width: 480, height: 360)
    }

    private var header: some View {
        HStack(spacing: SexiQLSpace.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title2)
                .foregroundStyle(SexiQLColors.failed)
            VStack(alignment: .leading, spacing: 2) {
                Text("Connection Failed")
                    .font(.headline)
                Text(failure.connectionName)
                    .font(SexiQLType.rowSubtitle)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(SexiQLSpace.xl)
    }

    private var meta: some View {
        VStack(alignment: .leading, spacing: SexiQLSpace.sm) {
            KeyValueRow(label: "Engine", value: failure.engineName)
            if let endpoint = failure.endpoint, !endpoint.isEmpty {
                KeyValueRow(label: "Endpoint", value: endpoint)
            }
        }
    }

    private var messageBlock: some View {
        VStack(alignment: .leading, spacing: SexiQLSpace.sm) {
            Text("What happened")
                .font(SexiQLType.sectionHeader)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Text(failure.message)
                .font(.body)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(SexiQLSpace.lg)
                .background {
                    RoundedRectangle(cornerRadius: SexiQLRadius.md, style: .continuous)
                        .fill(SexiQLColors.failed.opacity(0.10))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: SexiQLRadius.md, style: .continuous)
                        .strokeBorder(SexiQLColors.failed.opacity(0.25), lineWidth: 1)
                }
        }
    }

    private var technicalBlock: some View {
        VStack(alignment: .leading, spacing: SexiQLSpace.sm) {
            Text("Technical detail")
                .font(SexiQLType.sectionHeader)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Text(failure.technicalDetail)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var footer: some View {
        HStack(spacing: SexiQLSpace.md) {
            Button("Copy Error") {
                copyError()
            }
            Spacer()
            Button("Dismiss") {
                model.dismissConnectionFailure()
            }
            .keyboardShortcut(.cancelAction)
            Button("Edit…") {
                model.editConnection(for: failure.profileID)
            }
            Button("Retry") {
                model.retryConnection(for: failure.profileID)
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
        }
        .padding(SexiQLSpace.xl)
    }

    private func copyError() {
        var lines = [
            "Connection: \(failure.connectionName)",
            "Engine: \(failure.engineName)",
        ]
        if let endpoint = failure.endpoint {
            lines.append("Endpoint: \(endpoint)")
        }
        lines.append("")
        lines.append(failure.message)
        if failure.technicalDetail != failure.message {
            lines.append("")
            lines.append("Technical detail:")
            lines.append(failure.technicalDetail)
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(lines.joined(separator: "\n"), forType: .string)
    }
}
