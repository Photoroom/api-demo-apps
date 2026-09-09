import SwiftUI

/// GPU projective animation of the existing corrected pixels; no image processing or API calls per frame.
struct DewarpPreview: View {
    let result: CardResult
    let edited: CGImage
    let showingOriginal: Bool
    let replay: UUID
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var progress: CGFloat = 0
    @State private var animating = true
    @State private var backdropVisible = true
    @State private var fromFullPhoto = true
    @State private var hasPlayed = false

    private struct Playback: Equatable {
        let image: ObjectIdentifier
        let original: Bool
        let reducedMotion: Bool
        let replay: UUID
    }

    var body: some View {
        GeometryReader { geometry in
            let original = animating && fromFullPhoto ? result.original : result.originalPreview
            let sourceFrame = fitted(original, in: geometry.size)
            let targetFrame = fitted(result.corrected, in: geometry.size)
            let start = sourceCorners(in: sourceFrame)
            let end = [CardPoint(x: targetFrame.minX, y: targetFrame.minY),
                       CardPoint(x: targetFrame.maxX, y: targetFrame.minY),
                       CardPoint(x: targetFrame.maxX, y: targetFrame.maxY),
                       CardPoint(x: targetFrame.minX, y: targetFrame.maxY)]
            ZStack(alignment: .topLeading) {
                Image(decorative: original, scale: 1)
                    .resizable().scaledToFit().frame(width: geometry.size.width, height: geometry.size.height)
                    .opacity(showingOriginal || (animating && backdropVisible) ? 1 : 0)
                // Keep this exact layer on screen after the warp. Crossfading two copies
                // of a transparent card briefly reduces its combined opacity and causes a blink.
                Image(decorative: result.corrected, scale: 1)
                    .resizable().frame(width: targetFrame.width, height: targetFrame.height)
                    .modifier(CardWarp(start: start, end: end, progress: reduceMotion ? 1 : progress))
                    .opacity(showingOriginal || (!animating && edited !== result.corrected) ? 0 : 1)
                Image(decorative: edited, scale: 1)
                    .resizable().scaledToFit().frame(width: geometry.size.width, height: geometry.size.height)
                    .opacity(!showingOriginal && !animating && edited !== result.corrected ? 1 : 0)
            }.frame(width: geometry.size.width, height: geometry.size.height).clipped()
        }
        .accessibilityHidden(true)
        .task(id: Playback(image: ObjectIdentifier(result.corrected), original: showingOriginal,
                           reducedMotion: reduceMotion, replay: replay)) {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            guard !showingOriginal, !reduceMotion else {
                withTransaction(transaction) { progress = 1; animating = false }
                return
            }
            withTransaction(transaction) {
                fromFullPhoto = !hasPlayed
                hasPlayed = true
                progress = 0; backdropVisible = true; animating = true
            }
            do {
                try await Task.sleep(for: .milliseconds(200))
                // Remove the stationary original before moving its cutout to avoid a doubled card.
                withAnimation(.easeOut(duration: 0.2)) { backdropVisible = false }
                try await Task.sleep(for: .milliseconds(200))
                withAnimation(.easeInOut(duration: 1.1)) { progress = 1 }
                try await Task.sleep(for: .milliseconds(1150))
                withTransaction(transaction) { animating = false }
            } catch { /* A newer image or comparison selection owns the next transition. */ }
        }
    }

    private func fitted(_ image: CGImage, in size: CGSize) -> CGRect {
        let scale = min(size.width / CGFloat(image.width), size.height / CGFloat(image.height))
        let width = CGFloat(image.width) * scale, height = CGFloat(image.height) * scale
        return CGRect(x: (size.width - width) / 2, y: (size.height - height) / 2, width: width, height: height)
    }

    private func sourceCorners(in frame: CGRect) -> [CardPoint] {
        let canvas = CGSize(width: result.original.width, height: result.original.height)
        let crop = (animating && fromFullPhoto) || result.framedOriginal == nil ? CGRect(origin: .zero, size: canvas) :
            CardGeometry.paddedItemCrop(bounds: result.detection.maskBounds ?? CardGeometry.bounds(of: result.detection.corners), canvas: canvas)
        // Render's quarter turns rotate pixels after detection; match their semantic corner order.
        return (0..<4).map { i in
            let p = result.detection.corners[(i - result.quarterTurns + 4) % 4]
            return CardPoint(x: frame.minX + (p.x - crop.minX) * frame.width / crop.width,
                             y: frame.minY + (p.y - crop.minY) * frame.height / crop.height)
        }
    }
}

private struct CardWarp: GeometryEffect {
    let start: [CardPoint]
    let end: [CardPoint]
    var progress: CGFloat
    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        let corners = DewarpGeometry.corners(from: start, to: end, progress: Double(progress))
        guard size.width > 0, size.height > 0, let m = DewarpGeometry.projection(to: corners) else {
            return ProjectionTransform(.identity)
        }
        var transform = CATransform3DIdentity
        transform.m11 = m[0] / size.width; transform.m21 = m[1] / size.height; transform.m41 = m[2]
        transform.m12 = m[3] / size.width; transform.m22 = m[4] / size.height; transform.m42 = m[5]
        transform.m14 = m[6] / size.width; transform.m24 = m[7] / size.height
        return ProjectionTransform(transform)
    }
}
