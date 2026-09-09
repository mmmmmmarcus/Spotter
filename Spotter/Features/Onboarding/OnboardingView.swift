import AppKit
import Combine
import SwiftUI

/// First-launch wizard: set the palette shortcut, offer Accessibility + launch-at-login, then drop into the launcher. Re-runnable from Settings. Reuses the app's own controls (`ShortcutRecorder`, `PanelCard`) so it looks and behaves like the rest of Spotter.
struct OnboardingView: View {
    @State private var step = 0
    @ObservedObject private var settings = AppCore.shared.settings
    @ObservedObject private var hotKeys = AppCore.shared.hotKeys

    @State private var accessibilityTrusted = Permissions.isAccessibilityTrusted()
    private let refreshTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private static let lastStep = 2
    /// Fixed content size; also the window size in `AppCore.showOnboarding()`. A hard frame keeps `NSHostingView` from sizing the window to the content's unbounded ideal height.
    static let windowSize = CGSize(width: 520, height: 400)

    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            hero
            stepContent
                .frame(maxHeight: .infinity, alignment: .top)
            footer
        }
        .padding(.top, Theme.Spacing.xxl)
        .padding([.horizontal, .bottom], Theme.Spacing.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LinearGradient(
                colors: [Theme.Colors.surfaceGlow, Color.clear],
                startPoint: .top, endPoint: .center)
        )
        // Extend under the transparent titlebar (top padding clears the traffic lights) so the window height equals the fixed content height.
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.2), value: step)
        .onAppear { accessibilityTrusted = Permissions.isAccessibilityTrusted() }
        .onReceive(refreshTimer) { _ in
            let trusted = Permissions.isAccessibilityTrusted()
            if trusted != accessibilityTrusted { accessibilityTrusted = trusted }
        }
    }

    // MARK: - Hero (icon/glyph + title + subtitle)

    private var hero: some View {
        VStack(spacing: Theme.Spacing.md) {
            heroMark
            VStack(spacing: Theme.Spacing.xs) {
                Text(title)
                    .font(.title2.weight(.bold))
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var heroMark: some View {
        if step == 0 {
            Image(nsImage: Self.appIcon)
                .resizable()
                .frame(width: 60, height: 60)
        } else {
            Image(systemName: heroSymbol)
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(heroTint)
                .frame(width: 60, height: 60)
                .background(Circle().fill(heroTint.opacity(0.14)))
        }
    }

    private var title: String {
        switch step {
        case 0: "Welcome to Spotter"
        case 1: "Enable Pasting"
        default: "You're all set"
        }
    }

    private var subtitle: String {
        switch step {
        case 0: "Set a shortcut to summon the launcher from anywhere."
        case 1: "Let Spotter paste items back into the app you were using."
        default: readyMessage
        }
    }

    private var heroSymbol: String {
        switch step {
        case 1: "accessibility"
        default: "checkmark"
        }
    }

    private var heroTint: Color {
        switch step {
        case 1: .blue
        default: .green
        }
    }

    private var readyMessage: String {
        if let caps = hotKeys.shortcut(for: .togglePalette)?.keycaps {
            return "Press \(caps.joined()) anytime to start using Spotter."
        }
        return "Spotter is ready. Set a shortcut in Settings to summon it."
    }

    // MARK: - Step content

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case 0: shortcutStep
        case 1: accessibilityStep
        default: doneStep
        }
    }

    private var shortcutStep: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            PanelCard {
                PanelCardRow(
                    title: "App Launcher", subtitle: "Press this shortcut to open Spotter."
                ) {
                    ShortcutRecorder(action: .togglePalette)
                }
                PanelCardDivider()
                PanelCardRow(
                    title: "Launch at login",
                    subtitle: "Start Spotter automatically when you log in."
                ) {
                    Toggle("", isOn: $settings.launchAtLogin)
                        .labelsHidden().toggleStyle(.switch).controlSize(.small)
                }
            }
            caption("You can change these anytime in Settings.")
        }
    }

    private var accessibilityStep: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            PanelCard {
                PanelCardRow(
                    title: "Accessibility",
                    subtitle:
                        "Without it Spotter can still copy, but it can't paste a clipboard or emoji item back into the app you were using."
                ) {
                    statusBadge
                }
            }
            caption("Optional — you can enable this later in Settings › Permissions.")
        }
    }

    private var doneStep: some View {
        caption("Everything's ready. Hit Get Started to open the launcher.")
            .frame(maxWidth: .infinity, alignment: .center)
    }

    // MARK: - Footer (step dots + navigation)

    private var footer: some View {
        VStack(spacing: Theme.Spacing.lg) {
            HStack(spacing: Theme.Spacing.sm) {
                ForEach(0...Self.lastStep, id: \.self) { index in
                    Circle()
                        .fill(index == step ? Color.primary : Color.primary.opacity(0.2))
                        .frame(width: 7, height: 7)
                }
            }
            HStack {
                if step > 0 {
                    Button {
                        step -= 1
                    } label: {
                        Label("Back", systemImage: "chevron.left")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                if showsSkip {
                    Button("Skip") { advance() }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                }
                Button(primaryTitle, action: primaryAction)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private var showsSkip: Bool {
        step == 1 && !accessibilityTrusted
    }

    private var primaryTitle: String {
        switch step {
        case 0: "Continue"
        case 1: accessibilityTrusted ? "Continue" : "Grant Access"
        default: "Get Started"
        }
    }

    private func primaryAction() {
        switch step {
        case 1 where !accessibilityTrusted:
            Permissions.openAccessibilitySettings()
        case Self.lastStep:
            AppCore.shared.finishOnboarding()
        default:
            advance()
        }
    }

    private func advance() {
        step = min(step + 1, Self.lastStep)
    }

    // MARK: - Shared bits

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.tertiary)
            .padding(.horizontal, Theme.Spacing.xs)
    }

    private var statusBadge: some View {
        HStack(spacing: Theme.Spacing.xs + 1) {
            Image(
                systemName: accessibilityTrusted
                    ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
            Text(accessibilityTrusted ? "Granted" : "Not granted")
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(accessibilityTrusted ? Color.green : Color.orange)
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.xs)
        .background(
            Capsule().fill((accessibilityTrusted ? Color.green : Color.orange).opacity(0.14)))
    }

    // Read the bundled .icns directly: `NSApp.applicationIconImage` is the generic placeholder until LaunchServices registers the app (it hasn't when run from `build/`).
    private static let appIcon: NSImage = {
        if let name = Bundle.main.infoDictionary?["CFBundleIconFile"] as? String,
            let url = Bundle.main.url(forResource: name, withExtension: "icns"),
            let image = NSImage(contentsOf: url)
        {
            return image
        }
        return NSApp.applicationIconImage
    }()
}
