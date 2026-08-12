import Combine
import Foundation
import MicAICore

@MainActor
final class SettingsStore: ObservableObject {
  @Published var settings: AppSettings
  @Published private(set) var validationMessage: String?
  @Published private(set) var hasSeenOnboarding: Bool

  private let defaults: UserDefaults
  private let storageKey = "appSettings"
  private let onboardingKey = "hasSeenOnboarding"

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    if let data = defaults.data(forKey: storageKey),
      let decoded = try? JSONDecoder().decode(AppSettings.self, from: data),
      let validated = try? decoded.validated()
    {
      settings = validated
    } else {
      settings = .defaults
    }
    hasSeenOnboarding = defaults.bool(forKey: onboardingKey)
  }

  @discardableResult
  func save(_ candidate: AppSettings? = nil) -> Bool {
    do {
      let validatedSettings = try (candidate ?? settings).validated()
      let data = try JSONEncoder().encode(validatedSettings)
      defaults.set(data, forKey: storageKey)
      settings = validatedSettings
      validationMessage = nil
      return true
    } catch {
      validationMessage = error.localizedDescription
      return false
    }
  }

  func markOnboardingSeen() {
    defaults.set(true, forKey: onboardingKey)
    hasSeenOnboarding = true
  }

  func discardValidation() {
    validationMessage = nil
  }
}
