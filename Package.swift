// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NotchBar",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "NotchBar",
            path: "Sources/NotchBar",
            exclude: ["Info.plist"],
            resources: [
                .process("Resources")
            ],
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-sectcreate", "-Xlinker", "__TEXT", "-Xlinker", "__info_plist", "-Xlinker", "Sources/NotchBar/Info.plist"])
            ]
        )
    ]
)
