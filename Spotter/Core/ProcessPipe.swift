import Foundation

extension Pipe {
    // Foundation can retain Process and its pipes after exit; descriptor lifetime must be explicit.
    func closeHandles() {
        try? fileHandleForReading.close()
        try? fileHandleForWriting.close()
    }
}
