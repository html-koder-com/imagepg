// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "ImagePG",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "ImagePG", targets: ["ImagePG"])],
    targets: [.executableTarget(name: "ImagePG", path: "Sources/ImagePG")]
)
