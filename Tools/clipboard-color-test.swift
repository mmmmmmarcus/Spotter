import Foundation

@main
enum ClipboardColorTests {
    static func main() {
        precondition(ClipboardColor.parse("#FF5733") == ClipboardColor(red: 1, green: 87.0 / 255, blue: 51.0 / 255, alpha: 1))
        precondition(ClipboardColor.parse("#0f08")?.alpha == 136.0 / 255)
        precondition(ClipboardColor.parse("rgb(255, 0, 128)")?.blue == 128.0 / 255)
        precondition(ClipboardColor.parse("hsl(120, 100%, 50%)")?.green == 1)
        precondition(ClipboardColor.parse("report.pdf") == nil)
        print("Clipboard color tests passed")
    }
}
