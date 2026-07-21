import Combine
import Foundation
import MicAICore

@MainActor
final class SettingsStore: ObservableObject {
  @Published var settings: AppSettings
  @Published private(set) var validationMessage: String?

  private let defaults: UserDefaults
  private let storageKey = "appSettings"

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    if let data = defaults.data(forKey: storageKey),
      let decoded = try? JSONDecoder().decode(AppSettings.self, from: data)
    {
      settings = decoded
    } else {
      settings = .defaults
    }
  }

  @discardableResult
  func save() -> Bool {
    do {
      let validatedSettings = try settings.validated()
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
}
