// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "JBoardCore",
    platforms: [.macOS(.v13), .iOS(.v16)],
    products: [.library(name: "JBoardCore", targets: ["JBoardCore"])],
    targets: [
        .target(name: "JBoardCore", path: "Core", resources: [.process("Resources")]),
        .testTarget(name: "JBoardCoreTests", dependencies: ["JBoardCore"], path: "Tests/CoreTests")
    ]
)
