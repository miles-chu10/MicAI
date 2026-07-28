import Foundation

public struct TargetIdentity: Codable, Equatable, Sendable {
  public let processIdentifier: Int32
  public let bundleIdentifier: String?
  public let applicationName: String?
  public let focusToken: UUID?

  public init(
    processIdentifier: Int32,
    bundleIdentifier: String? = nil,
    applicationName: String? = nil,
    focusToken: UUID? = nil
  ) {
    self.processIdentifier = processIdentifier
    self.bundleIdentifier = bundleIdentifier
    self.applicationName = applicationName
    self.focusToken = focusToken
  }
}
