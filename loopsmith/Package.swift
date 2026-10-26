// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Loopsmith",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "Loopsmith",
            path: "Sources/Loopsmith"
        )
    ]
)
