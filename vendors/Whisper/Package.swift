// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Whisper",
    platforms: [.macOS(.v12)],
    products: [
        .library(name: "WhisperFramework", targets: ["WhisperFramework"])
    ],
    targets: [
        .binaryTarget(
            name: "WhisperFramework",
            url: "https://github.com/ggml-org/whisper.cpp/releases/download/v1.7.6/whisper-v1.7.6-xcframework.zip",
            checksum: "9fcb28106d0b94a525e59bec057e35b57033195ac7408d7e1ab8e4b597cdfeb5"
        )
    ]
)
