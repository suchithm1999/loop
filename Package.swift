// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Loop",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Loop",
            path: "Sources/Loop",
            swiftSettings: [
                .unsafeFlags(["-parse-as-library"])
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("CoreMedia"),
                .linkedFramework("IOKit"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("QuartzCore"),
                .linkedFramework("ScreenSaver"),
            ]
        )
    ]
)

