import Foundation

@main
enum DynamicTemplateTests {
    static func main() {
        let now = Date(timeIntervalSince1970: 0)
        let context = DynamicTemplateContext(selection: "  Hello ", clipboardHistory: ["A&B", "older"],
            now: now, calendar: Calendar(identifier: .gregorian), locale: Locale(identifier: "en_US_POSIX"),
            arguments: ["Person": "Marcus"], snippets: ["sign": "Regards, {argument name=\"Person\"}"],
            makeUUID: { UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")! })
        precondition(DynamicTemplate.expand("{selection | trim | uppercase}", context: context).text == "HELLO")
        precondition(DynamicTemplate.expand("{clipboard}", context: context, encoding: .percent).text == "A%26B")
        precondition(DynamicTemplate.expand("{clipboard offset=1}", context: context).text == "older")
        precondition(DynamicTemplate.expand("{snippet:Sign}", context: context).text == "Regards, Marcus")
        precondition(DynamicTemplate.expand("x{cursor}y", context: context).cursorOffset == 1)
        precondition(DynamicTemplate.expand("{argument name=\"Missing\"}", context: context).missingArguments == ["Missing"])
        print("Dynamic template tests passed")
    }
}
