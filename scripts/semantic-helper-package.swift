// swift-tools-version: 6.2
import PackageDescription

// Build only DigUp's native CLI, without its application or updater dependencies.
let package = Package(
    name: "SpotterEmbeddingHelper",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "digup", targets: ["digup"])],
    targets: [
        .target(name: "DigUpKit"),
        .systemLibrary(name: "CLlama", path: "Sources/CLlama"),
        .target(name: "LlamaRuntime", dependencies: ["CLlama", "DigUpKit"],
            linkerSettings: [.unsafeFlags(["-L\(Context.packageDirectory)/Vendor/llama/lib"])]),
        .executableTarget(name: "digup", dependencies: ["DigUpKit", "LlamaRuntime"])
    ])
