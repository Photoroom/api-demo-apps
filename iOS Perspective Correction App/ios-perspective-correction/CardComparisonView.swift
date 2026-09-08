import SwiftUI
import UIKit

struct CardComparison: Identifiable {
    let id = UUID()
    let original: CGImage
    let edited: CGImage
    let showingOriginal: Bool
}

struct CardComparisonView: View {
    @Environment(\.dismiss) private var dismiss
    let comparison: CardComparison
    @State var showingOriginal: Bool

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Compare photos").font(.headline)
                Spacer()
                Button("Done") { dismiss() }.fontWeight(.semibold)
                    .frame(minWidth: 44, minHeight: 44)
            }.padding(.horizontal, 20)
            Picker("Full-screen comparison", selection: $showingOriginal) {
                Text("Edited").tag(false)
                Text("Original").tag(true)
            }.pickerStyle(.segmented).padding(.horizontal, 20)
            ZoomableCardImage(image: showingOriginal ? comparison.original : comparison.edited,
                              label: showingOriginal ? "Original photo, full screen" : "Edited photo, full screen")
                .id(showingOriginal)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Text("Pinch to zoom • Double-tap to zoom or reset")
                .font(.caption).foregroundStyle(.secondary).padding(.bottom, 12)
        }
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }
}

private struct ZoomableCardImage: UIViewRepresentable {
    let image: CGImage
    let label: String
    func makeUIView(context: Context) -> CardZoomScrollView {
        let view = CardZoomScrollView()
        view.imageView.image = UIImage(cgImage: image)
        view.imageView.accessibilityLabel = label
        return view
    }
    func updateUIView(_ uiView: CardZoomScrollView, context: Context) {}
}

private final class CardZoomScrollView: UIScrollView, UIScrollViewDelegate {
    let imageView = UIImageView()
    private var layoutSize = CGSize.zero

    init() {
        super.init(frame: .zero)
        delegate = self
        minimumZoomScale = 1
        maximumZoomScale = 5
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        contentInsetAdjustmentBehavior = .never
        backgroundColor = .black
        imageView.contentMode = .scaleAspectFit
        imageView.isAccessibilityElement = true
        imageView.accessibilityTraits = .image
        addSubview(imageView)
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(toggleZoom(_:)))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        if bounds.size != layoutSize, bounds.width > 0, bounds.height > 0, let image = imageView.image {
            layoutSize = bounds.size
            setZoomScale(1, animated: false)
            let scale = min(bounds.width / image.size.width, bounds.height / image.size.height)
            imageView.frame = CGRect(origin: .zero, size: CGSize(width: image.size.width * scale, height: image.size.height * scale))
            contentSize = imageView.frame.size
        }
        centerImage()
    }
    func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }
    func scrollViewDidZoom(_ scrollView: UIScrollView) { centerImage() }
    private func centerImage() {
        imageView.center = CGPoint(x: max(contentSize.width, bounds.width) / 2,
                                   y: max(contentSize.height, bounds.height) / 2)
    }
    @objc private func toggleZoom(_ gesture: UITapGestureRecognizer) {
        if zoomScale > 1.01 { setZoomScale(1, animated: true); return }
        let point = gesture.location(in: imageView)
        let size = CGSize(width: bounds.width / 2.5, height: bounds.height / 2.5)
        zoom(to: CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2,
                        width: size.width, height: size.height), animated: true)
    }
}
