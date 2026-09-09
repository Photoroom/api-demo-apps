import Foundation

enum DewarpGeometry {
    // Separate in-plane rotation from the corner morph so a half-turn never collapses the card.
    static func corners(from start: [CardPoint], to end: [CardPoint], progress: Double) -> [CardPoint] {
        guard start.count == 4, end.count == 4 else { return end }
        let t = min(1, max(0, progress))
        let a = CardPoint(x: start.map(\.x).reduce(0, +) / 4, y: start.map(\.y).reduce(0, +) / 4)
        let b = CardPoint(x: end.map(\.x).reduce(0, +) / 4, y: end.map(\.y).reduce(0, +) / 4)
        let angle = atan2(start[1].y - start[0].y, start[1].x - start[0].x)
        let rotation = angle * (1 - t)
        return zip(start, end).map { p, q in
            let dx = p.x - a.x, dy = p.y - a.y
            let x = (dx * cos(angle) + dy * sin(angle)) * (1 - t) + (q.x - b.x) * t
            let y = (-dx * sin(angle) + dy * cos(angle)) * (1 - t) + (q.y - b.y) * t
            return CardPoint(x: a.x * (1 - t) + b.x * t + x * cos(rotation) - y * sin(rotation),
                             y: a.y * (1 - t) + b.y * t + x * sin(rotation) + y * cos(rotation))
        }
    }

    // Unit-square → quadrilateral homography, row-major with the final coefficient fixed at one.
    static func projection(to p: [CardPoint]) -> [Double]? {
        guard p.count == 4 else { return nil }
        let dx1 = p[1].x - p[2].x, dx2 = p[3].x - p[2].x
        let dy1 = p[1].y - p[2].y, dy2 = p[3].y - p[2].y
        let sx = p[0].x - p[1].x + p[2].x - p[3].x
        let sy = p[0].y - p[1].y + p[2].y - p[3].y
        let determinant = dx1 * dy2 - dx2 * dy1
        guard abs(determinant) > 1e-8 else { return nil }
        let g = (sx * dy2 - dx2 * sy) / determinant
        let h = (dx1 * sy - sx * dy1) / determinant
        let matrix = [p[1].x - p[0].x + g * p[1].x, p[3].x - p[0].x + h * p[3].x, p[0].x,
                      p[1].y - p[0].y + g * p[1].y, p[3].y - p[0].y + h * p[3].y, p[0].y, g, h]
        return matrix.allSatisfy(\.isFinite) ? matrix : nil
    }
}
