// Offline semantic-orientation regression. No API key or network request.
import AppKit
import CoreImage

@main struct VerifyCardOrientation {
    static func main() async throws {
        let size = NSSize(width: 600, height: 840)
        let fixtures = [
            ["TRADING CARD", "Water Energy", "Health Points 120", "Collect and trade", "A beautiful creature", "Adventure begins", "Special ability", "Card number 125"],
            ["ポケモンカード", "みずのエネルギー", "相手のポケモン", "カードを引く", "特別なわざ", "自分の番に使う", "ダメージを与える", "トレーナーズ"]
        ]
        for lines in fixtures {
            let canvas = NSImage(size: size)
            canvas.lockFocus()
            NSColor.white.setFill(); NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()
            for (i, line) in lines.enumerated() {
                (line as NSString).draw(at: NSPoint(x: 45, y: 750 - i * 85), withAttributes: [
                    .font: NSFont.systemFont(ofSize: 32), .foregroundColor: NSColor.black
                ])
            }
            canvas.unlockFocus()
            let original = canvas.cgImage(forProposedRect: nil, context: nil, hints: nil)!
            let context = CIContext(), processor = CardProcessor()
            for turn in 0..<4 {
                let rotated = CIImage(cgImage: original).oriented([.up, .right, .down, .left][turn])
                let input = context.createCGImage(rotated, from: rotated.extent)!
                let detected = try await processor.uprightQuarterTurns(input)
                precondition(detected == (4 - turn) % 4, "Wrong upright correction for rotation \(turn): \(detected)")
                let w = Double(input.width), h = Double(input.height)
                let result = CardResult(original: input, corrected: input,
                                        detection: CardDetection(corners: [CardPoint(x: 0, y: 0), CardPoint(x: w, y: 0), CardPoint(x: w, y: h), CardPoint(x: 0, y: h)], confidence: 1),
                                        pngData: Data(), cutout: CIImage(cgImage: input), automaticRatio: AspectRatioEstimate(widthOverHeight: w/h, relativeUncertainty: 0.01),
                                        aspectRatio: w/h, quarterTurns: 0)
                let corrected = try await processor.orientContent(result)
                precondition(corrected.corrected.width == original.width && corrected.corrected.height == original.height)
                precondition(abs(corrected.automaticRatio!.widthOverHeight - 600.0/840) < 1e-8)
                let rerendered = try await processor.render(corrected, aspectRatio: corrected.aspectRatio)
                let rerenderTurns = try await processor.uprightQuarterTurns(rerendered.corrected)
                precondition(rerenderTurns == 0, "Changing proportions must preserve upright orientation")
                let scene = try await processor.sceneImage(corrected)
                let sceneTurns = try await processor.uprightQuarterTurns(scene)
                precondition(sceneTurns == 0, "Blur scene must share upright corner ordering")
                print("PASS: \(lines[0]), rotation \(turn), upright card, matching ratio, local rerender and blur scene")
            }
        }
    }
}
