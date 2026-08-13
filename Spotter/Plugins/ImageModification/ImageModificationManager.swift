import AppKit
import UniformTypeIdentifiers

@MainActor
final class ImageModificationManager {
    private struct Inputs {
        let urls: [URL]
        let arePersistent: Bool
    }

    private struct ProgressUpdate: Sendable {
        let completed: Int
        let total: Int
        let input: URL?
    }

    private var task: Task<Void, Never>?
    private var backgroundTaskID: UUID?
    var onTaskStarted: ((ImageOperation, Int) -> UUID)?
    var onTaskProgress: ((UUID, String, Double) -> Void)?
    var onTaskFinished: ((UUID, Bool, String) -> Void)?
    var onTaskCancelled: ((UUID) -> Void)?

    func run(operation: ImageOperation, sourceApp: NSRunningApplication?) {
        precondition(operation != .convert, "Convert Image requires an explicit target format")
        start(operation: operation, format: nil, sourceApp: sourceApp)
    }

    func convert(to format: ImageFormat, sourceApp: NSRunningApplication?) {
        start(operation: .convert, format: format, sourceApp: sourceApp)
    }

    private func start(
        operation: ImageOperation, format: ImageFormat?, sourceApp: NSRunningApplication?
    ) {
        guard task == nil else { return }
        task = Task { [weak self] in
            guard let self else { return }
            await execute(operation: operation, format: format, sourceApp: sourceApp)
            task = nil
        }
    }

    func cancel() {
        task?.cancel()
        if let backgroundTaskID { onTaskCancelled?(backgroundTaskID) }
        backgroundTaskID = nil
    }

    private func execute(
        operation: ImageOperation, format: ImageFormat?, sourceApp: NSRunningApplication?
    ) async {
        do {
            let inputs = operation == .create
                ? Inputs(urls: [], arePersistent: false)
                : try await resolveInputs(sourceApp: sourceApp)
            guard !Task.isCancelled, operation == .create || !inputs.urls.isEmpty else { return }

            let configuredOutput = ImageOutputLocation(
                rawValue: UserDefaults.standard.string(forKey: "image-modification.output") ?? "alongside"
            ) ?? .alongside
            let configuredFormat = format ?? ImageFormat(
                rawValue: UserDefaults.standard.string(forKey: "image-modification.format") ?? "png"
            ) ?? .png
            let request = ImageModificationRequest.commandDefaults(
                operation: operation, output: configuredOutput, format: configuredFormat,
                hasPersistentInput: inputs.arePersistent)

            if request.output == .replace,
                !confirmReplacement(count: inputs.urls.count, sourceApp: sourceApp)
            {
                return
            }

            let total = operation == .create ? 1 : inputs.urls.count
            let taskID = onTaskStarted?(operation, total)
            backgroundTaskID = taskID
            let temporaryDirectory = temporaryDirectory
            let (progress, continuation) = AsyncStream.makeStream(of: ProgressUpdate.self)
            let processing = Task.detached(priority: .userInitiated) {
                defer { continuation.finish() }
                return try ImageModificationEngine.process(
                    request: request, inputs: inputs.urls, temporaryDirectory: temporaryDirectory
                ) { completed, total, input in
                    continuation.yield(
                        ProgressUpdate(completed: completed, total: total, input: input))
                }
            }
            for await update in progress {
                guard let taskID else { continue }
                let name = update.input?.lastPathComponent ?? "Generated image"
                onTaskProgress?(
                    taskID, "Processed \(name)",
                    Double(update.completed) / Double(update.total))
            }
            let results = try await processing.value
            guard !Task.isCancelled else {
                discardBackgroundTask(taskID)
                return
            }
            finishOutput(results, location: request.output)
            backgroundTaskID = nil
            if let taskID {
                onTaskFinished?(
                    taskID, true,
                    total == 1 ? "Processed 1 image." : "Processed \(total) images.")
            }
        } catch {
            let taskID = backgroundTaskID
            backgroundTaskID = nil
            guard !Task.isCancelled else {
                discardBackgroundTask(taskID)
                return
            }
            if let taskID { onTaskFinished?(taskID, false, error.localizedDescription) }
            presentFailure(operation: operation, error: error, sourceApp: sourceApp)
        }
    }

    private func discardBackgroundTask(_ taskID: UUID?) {
        backgroundTaskID = nil
        if let taskID { onTaskCancelled?(taskID) }
    }

    private func resolveInputs(sourceApp: NSRunningApplication?) async throws -> Inputs {
        if sourceApp?.bundleIdentifier == "com.apple.finder" {
            let selected = await Self.selectedFinderImages()
            if !selected.isEmpty { return Inputs(urls: selected, arePersistent: true) }
        }
        if let clipboard = try clipboardInputs() { return clipboard }
        guard let selected = chooseFiles(sourceApp: sourceApp) else {
            return Inputs(urls: [], arePersistent: true)
        }
        return Inputs(urls: selected, arePersistent: true)
    }

    private func clipboardInputs() throws -> Inputs? {
        let pasteboard = NSPasteboard.general
        if let urls = pasteboard.readObjects(
            forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] {
            let images = urls.filter {
                UTType(filenameExtension: $0.pathExtension)?.conforms(to: .image) == true
            }
            if !images.isEmpty { return Inputs(urls: images, arePersistent: true) }
        }
        guard let data = pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff)
        else { return nil }
        let url = temporaryDirectory.appendingPathComponent("clipboard-\(UUID().uuidString).png")
        try data.write(to: url, options: .atomic)
        return Inputs(urls: [url], arePersistent: false)
    }

    private func chooseFiles(sourceApp: NSRunningApplication?) -> [URL]? {
        NSApp.activate(ignoringOtherApps: true)
        defer { sourceApp?.activate() }
        let panel = NSOpenPanel()
        panel.message = "Choose images to process"
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.image]
        guard panel.runModal() == .OK else { return nil }
        return panel.urls
    }

    private func confirmReplacement(count: Int, sourceApp: NSRunningApplication?) -> Bool {
        NSApp.activate(ignoringOtherApps: true)
        defer { sourceApp?.activate() }
        let alert = NSAlert()
        alert.messageText = "Replace the original images?"
        alert.informativeText = "This writes processed pixels over \(count) original file\(count == 1 ? "" : "s")."
        alert.alertStyle = .warning
        let replace = alert.addButton(withTitle: "Replace")
        replace.hasDestructiveAction = true
        replace.keyEquivalent = ""
        alert.addButton(withTitle: "Cancel").keyEquivalent = "\r"
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func presentFailure(
        operation: ImageOperation, error: Error, sourceApp: NSRunningApplication?
    ) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Couldn’t \(operation.title)"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
        sourceApp?.activate()
    }

    private var temporaryDirectory: URL {
        let root = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "com.spotter.app1", isDirectory: true)
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
            pasteboard.declareTypes([.tiff, ClipboardManager.internalType], owner: nil)
            pasteboard.setData(tiff, forType: .tiff)
            pasteboard.setData(Data(), forType: ClipboardManager.internalType)
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
