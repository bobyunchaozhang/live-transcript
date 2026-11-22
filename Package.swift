// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LiveTranscript",
    platforms: [.macOS(.v15)],
    products: [.executable(name: "LiveTranscript", targets: ["LiveTranscript"])],
    targets: [
        .target(name: "AudioCaptureRing"),
        .target(name: "BilingualASR", cSettings: [.headerSearchPath("Vendor")]),
        .target(
            name: "EchoDSP",
            exclude: ["Vendor/COPYING", "Vendor/README.md"],
            cSettings: [.define("HAVE_CONFIG_H"), .headerSearchPath("Vendor")]
        ),
        .executableTarget(name: "LiveTranscript", dependencies: ["AudioCaptureRing", "BilingualASR", "EchoDSP"]),
        .testTarget(name: "LiveTranscriptTests", dependencies: ["LiveTranscript", "AudioCaptureRing", "EchoDSP"]),
    ]
)
