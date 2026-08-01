import AppKit
import UniformTypeIdentifiers

@MainActor
final class ImageModificationManager: ObservableObject {
    @Published var request = ImageModificationRequest()
    @Published var inputs: [URL] = []
    @Published private(set) var results: [ImageModificationResult] = []
    @Published private(set) var isRunning = false
    @Published var errorMessage: String?

    func prepare(operation: ImageOperation, sourceApp: NSRunningApplication?) {
        request.operation = operation
        request.output = ImageOutputLocation(
            rawValue: UserDefaults.standard.string(forKey: "image-modification.output") ?? "alongside"
        ) ?? .alongside
        request.format = ImageFormat(
            rawValue: UserDefaults.standard.string(forKey: "image-modification.format") ?? "png"
        ) ?? .png
        results = []
        errorMessage = nil
        loadClipboardFiles()
        guard sourceApp?.bundleIdentifier == "com.apple.finder" else { return }
        Task {
            let selected = await Self.selectedFinderImages()
            if !selected.isEmpty { inputs = selected }
        }
    }

    func chooseFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.image]
        if panel.runModal() == .OK { inputs = panel.urls }
    }

    func loadClipboardFiles() {
        let pasteboard = NSPasteboard.general
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            inputs = urls.filter { UTType(filenameExtension: $0.pathExtension)?.conforms(to: .image) == true }
            if !inputs.isEmpty { return }
        }
        guard let data = pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff) else { return }
        let url = temporaryDirectory.appendingPathComponent("clipboard-\(UUID().uuidString).png")
        do { try data.write(to: url, options: .atomic); inputs = [url] }
        catch { errorMessage = error.localizedDescription }
    }

    func removeInput(_ url: URL) { inputs.removeAll { $0 == url } }

    func run() {
        guard !isRunning else { return }
        if request.operation != .create, inputs.isEmpty { errorMessage = ImageModificationFailure.noInput.localizedDescription; return }
        if request.output == .replace {
            let alert = NSAlert()
            alert.messageText = "Replace the original images?"
            alert.informativeText = "This writes processed pixels over \(inputs.count) original file\(inputs.count == 1 ? "" : "s")."
            alert.alertStyle = .warning
            let replace = alert.addButton(withTitle: "Replace")
            replace.hasDestructiveAction = true
            replace.keyEquivalent = ""
            alert.addButton(withTitle: "Cancel").keyEquivalent = "\r"
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        isRunning = true
        errorMessage = nil
        let request = request
        let inputs = inputs
        let temporaryDirectory = temporaryDirectory
        Task {
            do {
                let output = try await Task.detached(priority: .userInitiated) {
                    try ImageModificationEngine.process(request: request, inputs: inputs, temporaryDirectory: temporaryDirectory)
                }.value
                results = output
                finishOutput(output, location: request.output)
            } catch { errorMessage = error.localizedDescription }
            isRunning = false
        }
    }

    private var temporaryDirectory: URL {
        let root = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "com.spotter.app", isDirectory: true)
            .appendingPathComponent("ImageModification", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func finishOutput(_ results: [ImageModificationResult], location: ImageOutputLocation) {
        guard !results.isEmpty else { return }
        if location == .preview {
            for result in results { NSWorkspace.shared.open(result.output) }
        } else if location == .clipboard, let first = results.first,
            let image = NSImage(contentsOf: first.output), let tiff = image.tiffRepresentation
        {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setData(tiff, forType: .tiff)
        }
    }

    private static func selectedFinderImages() async -> [URL] {
        let script = """
        tell application "Finder" to set selectedItems to selection as alias list
        set output to ""
        repeat with selectedItem in selectedItems
            set output to output & POSIX path of selectedItem & linefeed
        end repeat
        return output
        """
        let text = await Task.detached(priority: .userInitiated) {
            let process = Process()
            let output = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", script]
            process.standardOutput = output
            process.standardError = Pipe()
            guard (try? process.run()) != nil else { return "" }
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return "" }
            return String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        }.value
        return text.split(whereSeparator: \Character.isNewline).map { URL(fileURLWithPath: String($0)) }
            .filter { UTType(filenameExtension: $0.pathExtension)?.conforms(to: .image) == true }
    }
}
