// swift-tools-version:5.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "TTS",
    platforms: [
        .macOS(.v10_15), .iOS(.v13), .tvOS(.v13)
    ],
    products: [
        .library(
            name: "TTS",
            targets: ["TTS"])
    ],
    dependencies: [
        .package(name: "FFTPublisher", url: "https://github.com/helsingborg-stad/spm-fft-publisher.git", from: "0.1.0"),
        .package(name: "AudioSwitchboard", url: "https://github.com/helsingborg-stad/spm-audio-switchboard.git", from: "0.1.0")
    ],
    targets: [
        .target(
            name: "TTS",
            dependencies: ["AudioSwitchboard"]),
        .testTarget(
            name: "TTSTests",
            dependencies: ["TTS"])
    ]
)
