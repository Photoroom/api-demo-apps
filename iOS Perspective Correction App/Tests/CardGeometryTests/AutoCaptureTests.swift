import Foundation
import Testing
@testable import CardGeometry

private let steadyCard = [CardPoint(x: 0.3, y: 0.2), CardPoint(x: 0.7, y: 0.2),
                          CardPoint(x: 0.7, y: 0.8), CardPoint(x: 0.3, y: 0.8)]

private func assess(_ gate: inout AutoCaptureGate, _ time: Double, corners: [CardPoint]? = steadyCard,
                    sharpness: Double = 100, adjusting: Bool = false, brightness: Double = 0.5) -> AutoCaptureGate.Status {
    gate.assess(time: time, corners: corners, sharpness: sharpness, brightness: brightness, adjusting: adjusting)
}

@Test func autoCaptureAcceptsSharpFrameDespiteHandMovement() {
    var gate = AutoCaptureGate()
    #expect(assess(&gate, 0) == .holding)
    #expect(assess(&gate, 0.2, sharpness: 10) == .holding)
    let moved = steadyCard.map { CardPoint(x: $0.x + 0.08, y: $0.y - 0.06) }
    #expect(assess(&gate, 0.6, corners: moved) == .holding)
    #expect(assess(&gate, 0.8, corners: steadyCard) == .capture)
    gate.reset()
    #expect(assess(&gate, 1) == .holding)
}

@Test func missedDetectionDoesNotRestartAimingPeriod() {
    var gate = AutoCaptureGate()
    #expect(assess(&gate, 0) == .holding)
    #expect(assess(&gate, 0.2, corners: nil) == .searching)
    #expect(assess(&gate, 0.6) == .holding)
    #expect(assess(&gate, 0.8) == .capture)
}

@Test func autoCaptureStillRequiresCurrentSharpVisibleCard() {
    var gate = AutoCaptureGate()
    _ = assess(&gate, 0)
    for time in [0.6, 0.8, 1.2, 1.6, 2.0, 2.4] {
        #expect(assess(&gate, time, sharpness: 10) == .soft)
    }
    #expect(assess(&gate, 2.6, corners: nil) == .searching)
    #expect(assess(&gate, 2.8, brightness: 0.02) == .light)
    #expect(assess(&gate, 3, sharpness: .nan) == .soft)
    #expect(assess(&gate, 3.2) == .holding)
    #expect(assess(&gate, 3.4) == .capture)
}

@Test func continuousFocusCannotBlockSharpFrameForever() {
    var gate = AutoCaptureGate()
    _ = assess(&gate, 0, adjusting: true)
    #expect(assess(&gate, 0.6, adjusting: true) == .focusing)
    #expect(assess(&gate, 0.8, adjusting: true) == .focusing)
    #expect(assess(&gate, 1.3, sharpness: 10, adjusting: true) == .soft)
    #expect(assess(&gate, 1.5, adjusting: true) == .holding)
    #expect(assess(&gate, 1.7, adjusting: true) == .capture)
}

@Test func prolongedCardLossRestartsAimingPeriod() {
    var gate = AutoCaptureGate()
    _ = assess(&gate, 0)
    #expect(assess(&gate, 0.4, corners: nil) == .searching)
    #expect(assess(&gate, 1, corners: nil) == .searching)
    #expect(assess(&gate, 1.2) == .holding)
    #expect(assess(&gate, 1.4) == .holding)
    #expect(assess(&gate, 1.6) == .holding)
    #expect(assess(&gate, 1.9) == .holding)
    #expect(assess(&gate, 2.1) == .capture)
}

@Test func detailMeasurementSeparatesCrispAndBlurredTexture() {
    let w = 64, h = 64
    let crisp: [UInt8] = (0..<(w * h)).map { (($0 % w) / 4 + ($0 / w) / 4) % 2 == 0 ? 60 : 200 }
    var blurred = crisp
    for _ in 0..<6 {
        let source = blurred
        for y in 1..<(h - 1) {
            for x in 1..<(w - 1) {
                let i = y * w + x
                blurred[i] = UInt8((Int(source[i]) * 4 + Int(source[i-1]) + Int(source[i+1]) + Int(source[i-w]) + Int(source[i+w])) / 8)
            }
        }
    }
    let sharp = FrameDetail.measure(crisp, width: w, height: h)
    let soft = FrameDetail.measure(blurred, width: w, height: h)
    #expect(sharp.sharpness > 80)
    #expect(soft.sharpness < sharp.sharpness / 10)
    #expect(FrameDetail.measure([UInt8](repeating: 128, count: w * h), width: w, height: h).sharpness == 0)
}

@Test func oneSharpFrameCannotTriggerAndSoftFramesResetSharpCheck() {
    var gate = AutoCaptureGate()
    _ = assess(&gate, 0)
    #expect(assess(&gate, 0.6) == .holding)
    #expect(assess(&gate, 0.8, sharpness: 60) == .soft)
    #expect(assess(&gate, 1.0) == .holding)
    #expect(assess(&gate, 1.2) == .capture)
}
