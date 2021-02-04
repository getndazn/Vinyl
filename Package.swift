// swift-tools-version:5.3
import PackageDescription

let package = Package(
    name: "Vinyl",
    platforms: [
        .iOS(.v10),
        .tvOS(.v10),
        .macOS(.v10_11)
    ],
    products: [
        .library(name: "Vinyl", targets: ["Vinyl"])
    ],
    dependencies: [
        .package(url: "https://github.com/typelift/SwiftCheck.git", from: "0.12.0")
    ],
    targets: [
        .target(name: "Vinyl",
                path: "Vinyl",
                exclude: ["Info.plist"]),
        .testTarget(name: "VinylTests",
                    dependencies: ["SwiftCheck", "Vinyl"],
                    path: "VinylTests",
                    exclude: ["Info.plist"],
                    resources: [
                        .process("Fixtures/vinyl_multiple.json"),
                        .process("Fixtures/dvr_single.json"),
                        .process("Fixtures/vinyl_single.json"),
                        .process("Fixtures/vinyl_upload.json"),
                        .process("Fixtures/dvr_multiple.json"),
                        .process("Fixtures/vinyl_single_1.json"),
                        .process("Fixtures/vinyl_single_2.json"),
                        
                    ]
        )
    ]
)

