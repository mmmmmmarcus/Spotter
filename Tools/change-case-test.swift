import Foundation

@main
struct ChangeCaseTests {
    static func main() {
        var failures = 0
        func check(_ message: String, _ expected: String, _ actual: String) {
            if expected == actual { print("PASS  \(message)") }
            else { failures += 1; print("FAIL  \(message): expected \(expected), got \(actual)") }
        }

        check("camel", "helloWorld", ChangeCaseEngine.transform("hello world", as: .camel))
        check("camel boundary", "xmlHttpRequest", ChangeCaseEngine.transform("XMLHttpRequest", as: .camel))
        check("constant", "HELLO_WORLD", ChangeCaseEngine.transform("helloWorld", as: .constant))
        check("pascal snake", "Hello_World", ChangeCaseEngine.transform("hello-world", as: .pascalSnake))
        check("path", "hello/world", ChangeCaseEngine.transform("Hello World", as: .path))
        check("multiline", "Hello world\nSecond line", ChangeCaseEngine.transform("HELLO_WORLD\nsecondLine", as: .sentence))
        check("upper first", "Hello WORLD", ChangeCaseEngine.transform("hello WORLD", as: .upperFirst))
        check("swap", "hELLO wORLD", ChangeCaseEngine.transform("Hello World", as: .swap))

        var options = ChangeCaseOptions(exceptions: ["macOS"])
        check("title exception", "Using macOS Today", ChangeCaseEngine.transform("using macOS today", as: .title, options: options))
        options.prefixCharacters = "_"
        options.suffixCharacters = "_"
        check("retained edges", "__helloWorld_", ChangeCaseEngine.transform("__hello_world_", as: .camel, options: options))
        options = ChangeCaseOptions(preserveCase: false)
        check("pre-lowercase", "foobar", ChangeCaseEngine.transform("fooBar", as: .camel, options: options))
        options = ChangeCaseOptions(preservePunctuation: true)
        check("punctuation", "hello, world!", ChangeCaseEngine.transform("Hello, World!", as: .lower, options: options))

        print(failures == 0 ? "\nALL PASSED" : "\n\(failures) FAILED")
        exit(failures == 0 ? 0 : 1)
    }
}
