import Foundation

@main
struct RaycastImportTests {
    static func main() throws {
        let payload = #"{"snippets":{"snippets":[{"title":"Greeting","text":"Hello {date}","keyword":"hi"}]},"quicklinks":{"quicklinks":[{"name":"Search","link":"https://example.com?q={Query}"}]}}"#
        let result = try RaycastLibraryImport.parse(Data(payload.utf8))
        precondition(result.snippets.count == 1)
        precondition(result.snippets[0].content == "Hello {date}")
        precondition(result.quicklinks.count == 1)
        precondition(result.quicklinks[0].link == "https://example.com?q={argument}")
        precondition(!RaycastDecoder.isExport(Data("plain json".utf8)))
        print("Raycast import tests passed")
    }
}
