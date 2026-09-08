// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "CardGeometry",
    products: [.library(name: "CardGeometry", targets: ["CardGeometry"])],
    targets: [
        .target(name: "CardGeometry", path: "ios-perspective-correction/Processing", sources: ["CardGeometry.swift", "PhotoroomClient.swift", "CameraCalibration.swift", "AutoCaptureGate.swift"]),
        .testTarget(name: "CardGeometryTests", dependencies: ["CardGeometry"], path: "Tests/CardGeometryTests")
    ]
)
