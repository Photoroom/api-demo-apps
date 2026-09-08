// Compile with the app's Processing/*.swift and CardProcessor.swift.
// Run from the repository root with PHOTOROOM_API_KEY in the environment.
// Each example makes one segmentation and two image-edit requests.
import Foundation

@main struct GenerateReadmeExamples {
    static func main() async throws {
        guard let key = ProcessInfo.processInfo.environment["PHOTOROOM_API_KEY"], !key.isEmpty else {
            throw NSError(domain: "Examples", code: 1, userInfo: [NSLocalizedDescriptionKey: "Set PHOTOROOM_API_KEY before running."])
        }
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let output = root.appendingPathComponent("docs/examples")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let processor = CardProcessor()
        for (index, name) in ["charizard", "mew", "the-rock"].enumerated() {
            let sample = String(format: "ios-perspective-correction/Samples/trading-card-sample-%02d.jpg", index + 1)
            let detected = try await processor.process(Data(contentsOf: root.appendingPathComponent(sample)), apiKey: key)
            // Library samples have no synchronized camera calibration: select the app's Standard card preset.
            let result = try await processor.render(detected, aspectRatio: 2.5 / 3.5)
            try result.pngData.write(to: output.appendingPathComponent("\(name)-transparent.png"), options: .atomic)
            try await processor.originalPhotoData(result).write(to: output.appendingPathComponent("\(name)-original.jpg"), options: .atomic)
            let blurred = try await processor.blurredFinish(result, apiKey: key)
            try blurred.data.write(to: output.appendingPathComponent("\(name)-blurred.jpg"), options: .atomic)
            print("Generated \(name): original, transparent, and blurred.")
        }
    }
}
