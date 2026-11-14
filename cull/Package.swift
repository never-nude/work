// swift-tools-version:5.9
import PackageDescription

// CullCore is Foundation-only so the scan/delete engine can be tested anywhere.
// The SwiftUI app only exists on macOS.
var targets: [Target] = [
    .target(name: "CullCore", path: "Sources/CullCore"),
    .executableTarget(name: "cull", dependencies: ["CullCore"], path: "Sources/cull"),
    .testTarget(name: "CullCoreTests", dependencies: ["CullCore"], path: "Tests/CullCoreTests"),
    .testTarget(name: "CullCommandTests", dependencies: ["cull", "CullCore"], path: "Tests/CullCommandTests"),
]

#if os(macOS)
targets.append(
    .executableTarget(name: "CullApp", dependencies: ["CullCore"], path: "Sources/CullApp")
)
#endif

let package = Package(
    name: "Cull",
    platforms: [.macOS(.v14)],
    targets: targets
)
