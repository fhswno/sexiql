import AppKit
import SQLUI
import SwiftUI

struct WelcomeView: View {
    @Environment(WorkspaceModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var appeared = false

    static let repoURL = URL(string: "https://github.com/fhswno/sexiql")!

    var body: some View {
        ZStack {
            backdrop
            VStack(spacing: 26) {
                brandBlock
                callsToAction
                    .opacity(appeared ? 1 : 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .accessibilityLabel("SexiQL welcome")
        .onAppear { appear() }
    }

    private func appear() {
        if reduceMotion {
            appeared = true
        } else {
            withAnimation(.easeOut(duration: 0.45).delay(0.25)) {
                appeared = true
            }
        }
    }

    // MARK: - Backdrop

    private var backdrop: some View {
        ZStack {
            Rectangle().fill(.regularMaterial)
            Rectangle()
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.45))
            LinearGradient(
                colors: [
                    Color.primary.opacity(colorScheme == .dark ? 0.04 : 0.015),
                    .clear,
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
    }

    // MARK: - Brand

    private var brandBlock: some View {
        VStack(spacing: 14) {
            if let icon = appIcon {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 84, height: 84)
                    .shadow(color: .black.opacity(colorScheme == .dark ? 0.45 : 0.18), radius: 14, y: 5)
            }
            Text("SexiQL")
                .font(.system(size: 34, weight: .semibold))
                .tracking(0.2)
        }
        .padding(.bottom, 6)
    }

    private var callsToAction: some View {
        VStack(spacing: 18) {
            HStack(spacing: 12) {
                Button {
                    openRepository()
                } label: {
                    Label("Star on GitHub", systemImage: "star.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .pointerCursor()
                .keyboardShortcut(.defaultAction)

                Button("Get Started") {
                    model.dismissWelcome()
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .pointerCursor()

                Button("Skip") {
                    model.dismissWelcome()
                }
                .keyboardShortcut(.cancelAction)
                .opacity(0)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
            }
            Text(Self.repoURL.absoluteURL.host.map { "\($0)\(Self.repoURL.path)" } ?? "")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.top, 10)
    }

    private func openRepository() {
        NSWorkspace.shared.open(Self.repoURL)
        model.dismissWelcome()
    }

    private var appIcon: NSImage? {
        let name = colorScheme == .dark ? "AppIcon-dark" : "AppIcon-light"
        let url = Bundle.main.url(forResource: name, withExtension: "png")
            ?? Bundle.main.url(forResource: "AppIcon", withExtension: "png")
        guard let url else { return nil }
        return NSImage(contentsOf: url)
    }
}

