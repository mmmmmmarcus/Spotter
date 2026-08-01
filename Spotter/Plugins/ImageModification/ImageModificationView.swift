import AppKit
import SwiftUI

struct ImageModificationView: View {
    @ObservedObject var manager: ImageModificationManager

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("Operation", selection: $manager.request.operation) {
                    ForEach(ImageOperation.allCases) { operation in
                        Label(operation.title, systemImage: operation.systemImage).tag(operation)
                    }
                }
                .frame(width: 260)
                Spacer()
                Picker("Output", selection: $manager.request.output) {
                    ForEach(ImageOutputLocation.allCases) { Text($0.title).tag($0) }
                }
                .frame(width: 230)
            }
            .padding(Theme.Spacing.xl)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                    if manager.request.operation != .create { inputCard }
                    optionsCard
                    if let error = manager.errorMessage {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .textSelection(.enabled)
                    }
                    if !manager.results.isEmpty { resultCard }
                }
                .padding(Theme.Spacing.xl)
            }
            .overlayScroller()
            Divider()
            HStack {
                Text(manager.request.operation == .removeBackground ? "Processed locally with Vision" : "Processed locally on this Mac")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Run \(manager.request.operation.title)") { manager.run() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(manager.isRunning || (manager.inputs.isEmpty && manager.request.operation != .create))
                if manager.isRunning { ProgressView().controlSize(.small) }
            }
            .padding(Theme.Spacing.xl)
        }
        .frame(minWidth: 680, minHeight: 500)
    }

    private var inputCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack {
                Text("Images").font(Theme.Typography.sectionHeader).foregroundStyle(.secondary)
                Spacer()
                Button("Use Clipboard") { manager.loadClipboardFiles() }
                Button("Choose Files…") { manager.chooseFiles() }
            }
            if manager.inputs.isEmpty {
                ContentUnavailableView("No Images", systemImage: "photo.on.rectangle.angled", description: Text("Copy images or files, or choose them from disk."))
                    .frame(height: 120)
            } else {
                ForEach(manager.inputs, id: \.self) { url in
                    HStack {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 28, height: 28)
                        Text(url.lastPathComponent).lineLimit(1)
                        Spacer()
                        Button { manager.removeInput(url) } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(Theme.Spacing.xl)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.card).fill(Theme.Colors.cardFill))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card).stroke(Theme.Colors.cardStroke))
    }

    @ViewBuilder private var optionsCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            Text("Options").font(Theme.Typography.sectionHeader).foregroundStyle(.secondary)
            switch manager.request.operation {
            case .filter:
                optionRow("Filter") { Picker("", selection: $manager.request.filterName) { ForEach(ImageFilterCatalog.available) { Text($0.title).tag($0.name) } }.labelsHidden().frame(width: 240) }
            case .convert:
                formatRow
            case .create:
                dimensionRows
                optionRow("Generator") { Picker("", selection: $manager.request.generator) { ForEach(ImageGenerator.allCases) { Text($0.title).tag($0) } }.labelsHidden() }
                optionRow("Start Color") { TextField("#000000", text: $manager.request.colorHex).frame(width: 140) }
                optionRow("End Color") { TextField("#4F46E5", text: $manager.request.secondColorHex).frame(width: 140) }
                formatRow
            case .optimize:
                optionRow("Quality") { Slider(value: $manager.request.quality, in: 0.1...1).frame(width: 220); Text("\(Int(manager.request.quality * 100))%").monospacedDigit().frame(width: 42) }
            case .pad:
                optionRow("Padding") { TextField("40", value: $manager.request.padding, format: .number).frame(width: 90); Text("px").foregroundStyle(.secondary) }
                optionRow("Color") { TextField("#00000000", text: $manager.request.colorHex).frame(width: 140) }
            case .resize:
                dimensionRows
                optionRow("Preserve Aspect Ratio") { Toggle("", isOn: $manager.request.preserveAspect).labelsHidden().toggleStyle(.switch) }
            case .rotate:
                optionRow("Angle") { TextField("90", value: $manager.request.angle, format: .number).frame(width: 90); Text("degrees").foregroundStyle(.secondary) }
            case .scale:
                optionRow("Scale") { Slider(value: $manager.request.scale, in: 0.05...4).frame(width: 220); Text("\(manager.request.scale, specifier: "%.2f")×").monospacedDigit().frame(width: 48) }
            case .flipHorizontal, .flipVertical, .removeBackground, .stripMetadata:
                Text(description).font(.callout).foregroundStyle(.secondary)
            }
        }
        .padding(Theme.Spacing.xl)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.card).fill(Theme.Colors.cardFill))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card).stroke(Theme.Colors.cardStroke))
    }

    private var dimensionRows: some View {
        Group {
            optionRow("Width") { TextField("1200", value: $manager.request.width, format: .number).frame(width: 90); Text("px").foregroundStyle(.secondary) }
            optionRow("Height") { TextField("800", value: $manager.request.height, format: .number).frame(width: 90); Text("px").foregroundStyle(.secondary) }
        }
    }

    private var formatRow: some View {
        optionRow("Format") { Picker("", selection: $manager.request.format) { ForEach(ImageFormat.allCases) { Text($0.title).tag($0) } }.labelsHidden() }
    }

    private func optionRow<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack { Text(title); Spacer(); content() }
    }

    private var description: String {
        switch manager.request.operation {
        case .removeBackground: "Vision detects foreground subjects and writes a transparent background."
        case .stripMetadata: "Re-encodes pixels without EXIF, GPS, camera, or other source metadata."
        case .flipHorizontal: "Mirrors every image from left to right."
        case .flipVertical: "Mirrors every image from top to bottom."
        default: ""
        }
    }

    private var resultCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Results").font(Theme.Typography.sectionHeader).foregroundStyle(.secondary)
            ForEach(manager.results, id: \.output) { result in
                HStack {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text(result.output.lastPathComponent).lineLimit(1)
                    Spacer()
                    Button("Reveal") { NSWorkspace.shared.activateFileViewerSelecting([result.output]) }
                }
            }
        }
    }
}
