import Foundation

public struct ChatGPTCredential: Sendable, Equatable {
  public let accessToken: String
  public let accountID: String

  public init(accessToken: String, accountID: String) {
    self.accessToken = accessToken
    self.accountID = accountID
  }
}

public protocol CredentialLoading: Sendable {
  func load() throws -> ChatGPTCredential
}
