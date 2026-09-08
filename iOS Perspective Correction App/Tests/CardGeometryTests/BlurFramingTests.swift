import Testing
@testable import CardGeometry

// Golden coordinates evaluated from the supplied demo’s actual correctPerspective implementation.
// Cover off-center portrait/landscape placement and both axes of the two-pixel fit rule.
@Test func blurFramingMatchesDemo() throws {
    do {
        let actual = try CardGeometry.sceneDestination(corners: [CardPoint(x: 30, y: 40), CardPoint(x: 110, y: 30), CardPoint(x: 135, y: 180), CardPoint(x: 20, y: 190)], width: 200, height: 240, aspectRatio: 0.7142857142857143)
        let expected = [CardPoint(x: 17.762222724035965, y: 31.617111813650354), CardPoint(x: 129.73777727596405, y: 31.617111813650354), CardPoint(x: 129.73777727596405, y: 188.38288818634965), CardPoint(x: 17.762222724035965, y: 188.38288818634965)]
        for (a, b) in zip(actual, expected) { #expect(a.distance(to: b) < 1e-8) }
    }
    do {
        let actual = try CardGeometry.sceneDestination(corners: [CardPoint(x: 80, y: 30), CardPoint(x: 290, y: 50), CardPoint(x: 280, y: 150), CardPoint(x: 70, y: 140)], width: 320, height: 200, aspectRatio: 1.4)
        let expected = [CardPoint(x: 89.6945455304594, y: 27.996103950328134), CardPoint(x: 270.3054544695406, y: 27.996103950328134), CardPoint(x: 270.3054544695406, y: 157.00389604967188), CardPoint(x: 89.6945455304594, y: 157.00389604967188)]
        for (a, b) in zip(actual, expected) { #expect(a.distance(to: b) < 1e-8) }
    }
    do {
        let actual = try CardGeometry.sceneDestination(corners: [CardPoint(x: 2, y: 2), CardPoint(x: 198, y: 2), CardPoint(x: 198, y: 198), CardPoint(x: 2, y: 198)], width: 200, height: 200, aspectRatio: 1.4)
        let expected = [CardPoint(x: 1, y: 29.285714285714278), CardPoint(x: 199, y: 29.285714285714278), CardPoint(x: 199, y: 170.71428571428572), CardPoint(x: 1, y: 170.71428571428572)]
        for (a, b) in zip(actual, expected) { #expect(a.distance(to: b) < 1e-8) }
    }
    do {
        let actual = try CardGeometry.sceneDestination(corners: [CardPoint(x: 20, y: 1), CardPoint(x: 180, y: 1), CardPoint(x: 180, y: 199), CardPoint(x: 20, y: 199)], width: 200, height: 200, aspectRatio: 0.7142857142857143)
        let expected = [CardPoint(x: 29.285714285714278, y: 1), CardPoint(x: 170.71428571428572, y: 1), CardPoint(x: 170.71428571428572, y: 199), CardPoint(x: 29.285714285714278, y: 199)]
        for (a, b) in zip(actual, expected) { #expect(a.distance(to: b) < 1e-8) }
    }
}
