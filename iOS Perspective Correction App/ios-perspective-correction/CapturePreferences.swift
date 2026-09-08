import Foundation

enum CapturePreferences {
    static let relightKey = "relightEnabled"
    static let backgroundBlurKey = "backgroundBlurEnabled"
    static let automaticShutterKey = "automaticShutterEnabled"
    static var automaticShutter: Bool {
        get { UserDefaults.standard.object(forKey: automaticShutterKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: automaticShutterKey) }
    }
}
