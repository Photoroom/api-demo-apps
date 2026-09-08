import AVFoundation
import PhotosUI
import SwiftUI

private let cardAccent = Color.accentColor

struct ContentView: View {
    @State private var apiKey = ""
    @State private var settingsPresented = false
    @State private var pendingPhoto: CapturedPhoto?
    @State private var input: PhotoInput?
    @State private var result: CardResult?
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var cameraPresented = false
    @State private var samplesPresented = false
    @State private var errorMessage: String?
    @State private var cameraDenied = false
    private let processor = CardProcessor()

    var body: some View {
        NavigationStack {
            ZStack {
                Color(uiColor: .systemGroupedBackground).ignoresSafeArea()
                if let result {
                    CardResultView(result: result, apiKey: apiKey) { self.result = nil; input = nil }
                } else if input != nil {
                    ProcessingView { input = nil }
                } else {
                    CaptureHome(onCamera: openCamera, onSamples: { if apiKey.isEmpty { settingsPresented = true } else { samplesPresented = true } }, selectedPhoto: $selectedPhoto)
                }
            }
            .navigationTitle("Card Straight")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { settingsPresented = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("Settings")
                }
            }
            .sheet(isPresented: $settingsPresented, onDismiss: { pendingPhoto = nil }) {
                APIKeySettings(currentKey: $apiKey) { key in
                    apiKey = key
                    if let pendingPhoto, !key.isEmpty {
                        self.pendingPhoto = nil
                        receiveCapture(pendingPhoto)
                    }
                }
            }
            .task {
#if DEBUG
                if ProcessInfo.processInfo.arguments.contains("--verify-camera-ui") { cameraPresented = true; return }
                if ProcessInfo.processInfo.arguments.contains("--verify-proportions") {
                    do { result = try await ProportionPreviewFixture.make(calibrated: !ProcessInfo.processInfo.arguments.contains("--without-calibration")) }
                    catch { errorMessage = error.localizedDescription }
                    return
                }
#endif
                do { apiKey = try APIKeyStore.read() ?? "" }
                catch { errorMessage = error.localizedDescription }
            }
            .fullScreenCover(isPresented: $cameraPresented) {
                CameraCapture(onCapture: receiveCapture)
                    .ignoresSafeArea()
            }
            .sheet(isPresented: $samplesPresented) { SamplePicker(onSelect: receive) }
            .alert("Couldn’t complete correction", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: { Text(errorMessage ?? "Please try again.") }
            .alert("Allow camera access", isPresented: $cameraDenied) {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
                Button("Cancel", role: .cancel) {}
            } message: { Text("Enable Camera in Settings to photograph cards inside the app. You can also choose a photo from your library.") }
            .task(id: input?.id) {
                guard let input else { return }
                do {
                    let output = try await processor.process(input.data, apiKey: apiKey, calibration: input.calibration)
                    try Task.checkCancellation()
                    result = output
                } catch is CancellationError {
                    // A cancelled scan must not replace the next photo's result.
                } catch {
                    guard !Task.isCancelled else { return }
                    self.input = nil
                    errorMessage = error.localizedDescription
                }
            }
            .task(id: selectedPhoto) {
                guard let selectedPhoto else { return }
                do {
                    guard let data = try await selectedPhoto.loadTransferable(type: Data.self) else { throw CardError.invalidImage }
                    try Task.checkCancellation()
                    receive(data)
                } catch {
                    if !Task.isCancelled { errorMessage = error.localizedDescription }
                }
                self.selectedPhoto = nil
            }
        }
        .tint(cardAccent)
    }

    private func receive(_ data: Data) { receiveCapture(CapturedPhoto(data: data, calibration: nil)) }
    private func receiveCapture(_ photo: CapturedPhoto) {
        guard !apiKey.isEmpty else { pendingPhoto = photo; settingsPresented = true; return }
        result = nil
        input = PhotoInput(data: photo.data, calibration: photo.calibration)
    }
    private func openCamera() {
        guard !apiKey.isEmpty else { settingsPresented = true; return }
        guard AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) != nil else {
            errorMessage = "A camera isn’t available on this device. Choose a library photo or try a sample card."
            return
        }
        Task { @MainActor in
            let status = AVCaptureDevice.authorizationStatus(for: .video)
            var allowed = status == .authorized
            if status == .notDetermined { allowed = await AVCaptureDevice.requestAccess(for: .video) }
            if allowed { cameraPresented = true } else { cameraDenied = true }
        }
    }
}

private struct PhotoInput: Identifiable {
    let id = UUID()
    let data: Data
    let calibration: CameraCalibration?
}

private struct CaptureHome: View {
    let onCamera: () -> Void
    let onSamples: () -> Void
    @Binding var selectedPhoto: PhotosPickerItem?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 10) {
                    Label("A better angle. Automatically.", systemImage: "viewfinder")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(cardAccent)
                    Text("Your cards.\nPerfectly straight.")
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    Text("Take a photo. We’ll remove the background, correct the perspective, and crop your card.")
                        .font(.body).foregroundStyle(.secondary)
                }
                CardIllustration()
                VStack(spacing: 12) {
                    Button(action: onCamera) {
                        Label("Take a photo", systemImage: "camera.fill").frame(maxWidth: .infinity).padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                    .accessibilityIdentifier("takePhoto")
                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        Label("Choose from library", systemImage: "photo.on.rectangle").frame(maxWidth: .infinity).padding(.vertical, 5)
                    }
                    .buttonStyle(.bordered).controlSize(.large)
                }
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "lightbulb").foregroundStyle(cardAccent)
                    Text("For the best result, use a plain background, avoid glare, and keep all four corners in the picture.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Button(action: onSamples) {
                    HStack {
                        Label("Try a sample card", systemImage: "sparkles.rectangle.stack")
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption.weight(.bold))
                    }
                    .font(.subheadline.weight(.semibold)).padding(18)
                    .background(.background, in: RoundedRectangle(cornerRadius: 18))
                }
                .accessibilityIdentifier("trySamples")
                Label("Background removal by Photoroom", systemImage: "cloud")
                    .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity)
            }
            .padding(24)
        }
    }
}

private struct CardIllustration: View {
    var body: some View {
        HStack(spacing: 22) {
            MiniCard().rotationEffect(.degrees(-12)).rotation3DEffect(.degrees(20), axis: (x: 0, y: 1, z: 0))
            Image(systemName: "arrow.right").font(.title3.weight(.semibold)).foregroundStyle(cardAccent)
            MiniCard().overlay(alignment: .bottomTrailing) {
                Image(systemName: "checkmark.circle.fill").font(.title2).symbolRenderingMode(.palette)
                    .foregroundStyle(.white, cardAccent).offset(x: 8, y: 8)
            }
        }
        .padding(32).frame(maxWidth: .infinity)
        .background(cardAccent.opacity(0.07), in: RoundedRectangle(cornerRadius: 28))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("A tilted trading card becomes straight")
    }
}

private struct MiniCard: View {
    var body: some View {
        VStack(spacing: 8) {
            HStack { Capsule().frame(width: 30, height: 4); Spacer(); Circle().frame(width: 5, height: 5) }
            Image(systemName: "sparkles").font(.system(size: 30)).frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(cardAccent.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))
            Capsule().frame(height: 3)
            Capsule().frame(width: 40, height: 3).frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(cardAccent).padding(10).frame(width: 88, height: 124)
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(cardAccent.opacity(0.2)))
        .shadow(color: cardAccent.opacity(0.12), radius: 12, y: 6)
    }
}

private struct ProcessingView: View {
    let cancel: () -> Void
    var body: some View {
        VStack(spacing: 20) {
            ProgressView().controlSize(.large)
            Text("Preparing your card").font(.title2.bold())
            Text("Getting the Photoroom mask, removing the background, and straightening the image.")
                .foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button("Cancel", role: .cancel, action: cancel).buttonStyle(.bordered)
        }.padding(32)
    }
}

private struct SampleCard: Identifiable {
    let id: Int
    var name: String { String(format: "trading-card-sample-%02d", id) }
    static let all = (1...9).map { SampleCard(id: $0) }
}

private struct SamplePicker: View {
    @Environment(\.dismiss) private var dismiss
    let onSelect: (Data) -> Void
    @State private var errorMessage: String?
    var body: some View {
        NavigationStack {
            ScrollView {
                Text("Photos from the original trading-card demo. Tap one to straighten it.")
                    .foregroundStyle(.secondary).padding()
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140))], spacing: 16) {
                    ForEach(SampleCard.all) { sample in
                        Button {
                            if let url = Bundle.main.url(forResource: sample.name, withExtension: "jpg"), let data = try? Data(contentsOf: url) {
                                dismiss(); onSelect(data)
                            } else { errorMessage = "This sample couldn’t be opened." }
                        } label: {
                            VStack {
                                Image(uiImage: UIImage(named: sample.name + ".jpg") ?? UIImage())
                                    .resizable().scaledToFit().frame(height: 175)
                                Text("Sample \(sample.id)").font(.subheadline.weight(.medium))
                            }.padding(12).frame(maxWidth: .infinity)
                                .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
                        }.accessibilityLabel("Correct sample \(sample.id)")
                    }
                }.padding(.horizontal)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Sample cards").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
            .alert("Sample unavailable", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK") { errorMessage = nil }
            } message: { Text(errorMessage ?? "") }
        }
    }
}

#Preview { ContentView() }
