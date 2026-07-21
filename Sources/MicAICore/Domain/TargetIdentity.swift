import Foundation

public struct TargetIdentity: Codable, Equatable, Sendable {
  public let processIdentifier: Int32
  public let bundleIdentifier: String?
  public let applicationName: String?

  public init(
    processIdentifier: Int32,
    bundleIdentifier: String? = nil,
    applicationName: String? = nil
  ) {
    self.processIdentifier = processIdentifier
    self.bundleIdentifier = bundleIdentifier
    self.applicationName = applicationName
  }
}
