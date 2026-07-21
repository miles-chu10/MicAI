import Foundation

public struct CodexAuthFileLoader: CredentialLoading, Sendable {
  public let fileURL: URL

  public init(
    fileURL: URL = FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent(".codex/auth.json")
  ) {
    self.fileURL = fileURL
  }

  public func load() throws -> ChatGPTCredential {
    let data: Data
    do {
      data = try Data(contentsOf: fileURL, options: [.mappedIfSafe])
    } catch {
      throw MicAIError.credentialMissing
    }

    let document: AuthDocument
    do {
      document = try JSONDecoder().decode(AuthDocument.self, from: data)
    } catch {
      throw MicAIError.credentialMalformed
    }

    guard
      let accessToken = nonempty(document.tokens?.accessToken),
      let accountID = nonempty(document.tokens?.accountID)
    else {
      throw MicAIError.credentialMissing
    }

    return ChatGPTCredential(
      accessToken: accessToken,
      accountID: accountID
    )
  }

  private func nonempty(_ value: String?) -> String? {
    guard let value else {
      return nil
    }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }
}

private struct AuthDocument: Decodable {
  let tokens: Tokens?

  struct Tokens: Decodable {
    let accessToken: String?
    let accountID: String?

    enum CodingKeys: String, CodingKey {
      case accessToken = "access_token"
      case accountID = "account_id"
    }
  }
}
