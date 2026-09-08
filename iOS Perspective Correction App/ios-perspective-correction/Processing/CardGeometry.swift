import Foundation
import CoreGraphics

// Swift port of presales_automation/src/lib/trading-card-perspective/perspective.ts.
// Coordinates are pixels, with the origin at the top left.
struct CardPoint: Equatable, Sendable {
    var x: Double
    var y: Double
    func distance(to other: Self) -> Double { hypot(x - other.x, y - other.y) }
}

struct CardDetection: Sendable {
    let corners: [CardPoint] // top left, top right, bottom right, bottom left
    let confidence: Double
    var maskBounds: CGRect? = nil
}

enum CardError: LocalizedError {
    case noCard, invalidImage, invalidMask, exportFailed
    var errorDescription: String? {
        switch self {
        case .noCard: "Couldn’t find all four card edges. Place one card on a plain, contrasting surface with every corner visible, then try again."
        case .invalidImage: "This image couldn’t be opened. Try another photo."
        case .invalidMask: "The card outline couldn’t be read. Try another photo."
        case .exportFailed: "The corrected image couldn’t be created. Please try again."
        }
    }
}

enum CardGeometry {
    static let standardAspectRatio = 3.5 / 2.5
    /// Demo full-canvas framing: measured area, two-pixel fit allowance, and mean corner position.
    /// The selected ratio replaces only the demo's fixed 3.5 / 2.5 proportions.
    static func sceneDestination(corners p: [CardPoint], width: Double, height: Double, aspectRatio: Double) throws -> [CardPoint] {
        guard p.count == 4, width > 2, height > 2, aspectRatio.isFinite, (0.2...5).contains(aspectRatio) else {
            throw CardError.exportFailed
        }
        let area = max(p[0].distance(to: p[1]), p[2].distance(to: p[3])) *
                   max(p[0].distance(to: p[3]), p[1].distance(to: p[2]))
        var w = sqrt(area * aspectRatio), h = sqrt(area / aspectRatio)
        let fit = min(1, (width - 2) / w, (height - 2) / h)
        w *= fit; h *= fit
        let cx = p.map(\.x).reduce(0, +) / 4, cy = p.map(\.y).reduce(0, +) / 4
        return [CardPoint(x: cx - w / 2, y: cy - h / 2), CardPoint(x: cx + w / 2, y: cy - h / 2),
                CardPoint(x: cx + w / 2, y: cy + h / 2), CardPoint(x: cx - w / 2, y: cy + h / 2)]
    }

    static func paddedItemCrop(bounds: CGRect, canvas: CGSize) -> CGRect {
        let padding = max(bounds.width, bounds.height) * 0.05
        return bounds.insetBy(dx: -padding, dy: -padding).integral
            .intersection(CGRect(origin: .zero, size: canvas))
    }

    static func bounds(of points: [CardPoint]) -> CGRect {
        guard let minX = points.map(\.x).min(), let maxX = points.map(\.x).max(),
              let minY = points.map(\.y).min(), let maxY = points.map(\.y).max() else { return .null }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private struct Line {
        let a: Double, b: Double, c: Double
        func distance(_ p: CardPoint) -> Double { abs(a * p.x + b * p.y + c) }
    }
    private static func cross(_ a: CardPoint, _ b: CardPoint, _ c: CardPoint) -> Double {
        (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
    }
    private static func area(_ points: [CardPoint]) -> Double {
        abs(points.indices.reduce(0) { sum, i in
            let next = points[(i + 1) % points.count]
            return sum + points[i].x * next.y - next.x * points[i].y
        }) / 2
    }
    static func ordered(_ points: [CardPoint]) -> [CardPoint] {
        guard points.count == 4 else { return points }
        let start = points.indices.min { points[$0].x + points[$0].y < points[$1].x + points[$1].y }!
        let previous = (start + 3) % 4, next = (start + 1) % 4
        let forward = points[next].y - points[next].x < points[previous].y - points[previous].x
        return (0..<4).map { points[(start + (forward ? $0 : 4 - $0)) % 4] }
    }
    static func valid(_ p: [CardPoint]) -> Bool {
        guard p.count == 4, p.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else { return false }
        let turns = (0..<4).map { cross(p[$0], p[($0 + 1) % 4], p[($0 + 2) % 4]) }
        guard turns.allSatisfy({ abs($0) >= 1e-6 && ($0 > 0) == (turns[0] > 0) }) else { return false }
        let w = (p[0].distance(to: p[1]) + p[2].distance(to: p[3])) / 2
        let h = (p[0].distance(to: p[3]) + p[1].distance(to: p[2])) / 2
        return min(w, h) >= 16 && (1.0...5.0).contains(max(w, h) / min(w, h))
    }
    private static func hull(_ points: [CardPoint]) -> [CardPoint] {
        let sorted = points.sorted { $0.x == $1.x ? $0.y < $1.y : $0.x < $1.x }
        var lower = [CardPoint](), upper = [CardPoint]()
        for p in sorted {
            while lower.count >= 2 && cross(lower[lower.count - 2], lower.last!, p) <= 0 { lower.removeLast() }
            lower.append(p)
        }
        for p in sorted.reversed() {
            while upper.count >= 2 && cross(upper[upper.count - 2], upper.last!, p) <= 0 { upper.removeLast() }
            upper.append(p)
        }
        return Array(lower.dropLast()) + Array(upper.dropLast())
    }
    private static func through(_ p: CardPoint, _ q: CardPoint) throws -> Line {
        let length = p.distance(to: q)
        guard length > 1e-6 else { throw CardError.noCard }
        let a = (p.y - q.y) / length, b = (q.x - p.x) / length
        return Line(a: a, b: b, c: -(a * p.x + b * p.y))
    }
    private static func leastSquares(_ points: [CardPoint]) throws -> Line {
        guard points.count >= 2 else { throw CardError.noCard }
        let n = Double(points.count)
        let center = CardPoint(x: points.reduce(0) { $0 + $1.x / n }, y: points.reduce(0) { $0 + $1.y / n })
        var xx = 0.0, xy = 0.0, yy = 0.0
        for p in points {
            let x = p.x - center.x, y = p.y - center.y
            xx += x * x; xy += x * y; yy += y * y
        }
        let direction = atan2(2 * xy, xx - yy) / 2
        let a = -sin(direction), b = cos(direction)
        return Line(a: a, b: b, c: -(a * center.x + b * center.y))
    }
    private static func robustFit(_ points: [CardPoint]) throws -> (Line, [CardPoint]) {
        var inliers = points
        var line = try leastSquares(inliers)
        for _ in 0..<3 {
            guard inliers.count >= 8 else { break }
            let ranked = inliers.sorted { line.distance($0) < line.distance($1) }
            let cutoff = max(1.25, line.distance(ranked[Int(Double(ranked.count - 1) * 0.78)]))
            let next = ranked.filter { line.distance($0) <= cutoff }
            if next.count < 4 || next.count == inliers.count { break }
            inliers = next
            line = try leastSquares(inliers)
        }
        return (line, inliers)
    }
    private static func intersection(_ p: Line, _ q: Line) throws -> CardPoint {
        let d = p.a * q.b - q.a * p.b
        guard abs(d) >= 1e-6 else { throw CardError.noCard }
        return CardPoint(x: (p.b * q.c - q.b * p.c) / d, y: (p.c * q.a - q.c * p.a) / d)
    }
    private static func fit(_ boundary: [CardPoint], width: Int, height: Int) throws -> (CardDetection, Double) {
        var corners = hull(boundary)
        guard corners.count >= 4 else { throw CardError.noCard }
        while corners.count > 4 {
            let i = corners.indices.min { a, b in
                abs(cross(corners[(a + corners.count - 1) % corners.count], corners[a], corners[(a + 1) % corners.count])) <
                abs(cross(corners[(b + corners.count - 1) % corners.count], corners[b], corners[(b + 1) % corners.count]))
            }!
            corners.remove(at: i)
        }
        let diagonal = hypot(Double(width), Double(height))
        let maximumDistance = max(4, diagonal * 0.06)
        var lines = [Line](), sideInliers = [[CardPoint]]()
        for _ in 0..<2 {
            let sides = try (0..<4).map { try through(corners[$0], corners[($0 + 1) % 4]) }
            var assigned = Array(repeating: [CardPoint](), count: 4)
            for point in boundary {
                var bestSide: Int?, bestDistance = Double.infinity
                for i in 0..<4 {
                    let start = corners[i], end = corners[(i + 1) % 4]
                    let dx = end.x - start.x, dy = end.y - start.y
                    let projection = ((point.x - start.x) * dx + (point.y - start.y) * dy) / (dx * dx + dy * dy)
                    let distance = sides[i].distance(point)
                    if (-0.18...1.18).contains(projection) && distance < bestDistance {
                        bestSide = i; bestDistance = distance
                    }
                }
                if let i = bestSide, bestDistance <= maximumDistance { assigned[i].append(point) }
            }
            guard assigned.allSatisfy({ $0.count >= 4 }) else { throw CardError.noCard }
            let fits = try assigned.map { try robustFit($0) }
            lines = fits.map(\.0); sideInliers = fits.map(\.1)
            corners = try (0..<4).map { try intersection(lines[($0 + 3) % 4], lines[$0]) }
        }
        let orderedCorners = ordered(corners)
        guard valid(orderedCorners) else { throw CardError.noCard }
        let residuals = boundary.map { p in lines.map { $0.distance(p) }.min()! }.sorted()
        let straightness = max(0, 1 - residuals[residuals.count / 2] / max(2, diagonal * 0.01))
        let support = min(1, Double(sideInliers.map(\.count).min()!) / max(8, Double(min(width, height)) * 0.15))
        return (CardDetection(corners: orderedCorners, confidence: straightness * 0.7 + support * 0.3), area(corners))
    }

    static func detect(mask: [UInt8], width: Int, height: Int, sourceWidth: Int? = nil, sourceHeight: Int? = nil) throws -> CardDetection {
        guard width > 1, height > 1, width <= 1600, height <= 1600, mask.count == width * height else { throw CardError.invalidMask }
        var exterior = [Bool](repeating: false, count: mask.count)
        var queue = [Int]()
        func enqueue(_ index: Int) {
            if mask[index] == 0 && !exterior[index] { exterior[index] = true; queue.append(index) }
        }
        for x in 0..<width { enqueue(x); enqueue((height - 1) * width + x) }
        for y in 1..<(height - 1) { enqueue(y * width); enqueue(y * width + width - 1) }
        var head = 0
        while head < queue.count {
            let i = queue[head]; head += 1
            let x = i % width, y = i / width
            if x > 0 { enqueue(i - 1) }; if x < width - 1 { enqueue(i + 1) }
            if y > 0 { enqueue(i - width) }; if y < height - 1 { enqueue(i + width) }
        }
        var visited = [Bool](repeating: false, count: mask.count)
        var bestArea = 0, bestBoundary = [CardPoint]()
        for start in mask.indices where mask[start] != 0 && !visited[start] {
            queue.removeAll(keepingCapacity: true); queue.append(start); visited[start] = true; head = 0
            var boundary = [CardPoint]()
            while head < queue.count {
                let i = queue[head]; head += 1
                let x = i % width, y = i / width
                var isBoundary = x == 0 || x == width - 1 || y == 0 || y == height - 1
                let neighbors = [x > 0 ? i - 1 : nil, x < width - 1 ? i + 1 : nil,
                                 y > 0 ? i - width : nil, y < height - 1 ? i + width : nil].compactMap { $0 }
                for n in neighbors {
                    if mask[n] != 0 && !visited[n] { visited[n] = true; queue.append(n) }
                    if exterior[n] { isBoundary = true }
                }
                if isBoundary { boundary.append(CardPoint(x: Double(x), y: Double(y))) }
            }
            if queue.count > bestArea { bestArea = queue.count; bestBoundary = boundary }
        }
        guard Double(bestArea) >= Double(mask.count) * 0.01, !bestBoundary.isEmpty else { throw CardError.noCard }
        let (fitted, quadArea) = try fit(bestBoundary, width: width, height: height)
        let fill = Double(bestArea) / max(1, quadArea)
        guard fitted.confidence >= 0.5, (0.7...1.2).contains(fill) else { throw CardError.noCard }
        let sx = Double(sourceWidth ?? width) / Double(width), sy = Double(sourceHeight ?? height) / Double(height)
        let corners = fitted.corners.map { CardPoint(x: $0.x * sx, y: $0.y * sy) }
        guard valid(corners) else { throw CardError.noCard }
        let fillScore = max(0, 1 - abs(1 - fill) / 0.3)
        let minX = bestBoundary.map(\.x).min()!, maxX = bestBoundary.map(\.x).max()!
        let minY = bestBoundary.map(\.y).min()!, maxY = bestBoundary.map(\.y).max()!
        let bounds = CGRect(x: minX * sx, y: minY * sy, width: (maxX - minX + 1) * sx, height: (maxY - minY + 1) * sy)
        return CardDetection(corners: corners, confidence: max(0, min(1, fitted.confidence * 0.75 + fillScore * 0.25)), maskBounds: bounds)
    }
}
