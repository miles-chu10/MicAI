import Foundation
import MicAICore
import Testing

@Suite
struct CodexAuthFileLoaderTests {
  @Test
  func loadsAccessTokenAndAccountIDFromValidFile() throws {
    let url = try writeTempAuth(
      """
      {
        "auth_mode": "chatgpt",
        "last_refresh": "2026-07-21T00:00:00Z",
        "tokens": {
          "access_token": "fake-access-token",
          "account_id": "fake-account-id",
          "id_token": "fake-id-token",
          "refresh_token": "fake-refresh-token"
        }
      }
      """
    )
    defer { try? FileManager.default.removeItem(at: url) }

    let credential = try CodexAuthFileLoader(fileURL: url).load()

    #expect(credential.accessToken == "fake-access-token")
    #expect(credential.accountID == "fake-account-id")
  }

  @Test
  func loadsWithoutRequiringRefreshToken() throws {
    let url = try writeTempAuth(
      """
      {
        "tokens": {
          "access_token": "fake-access-token",
          "account_id": "fake-account-id"
        }
      }
      """
    )
    defer { try? FileManager.default.removeItem(at: url) }

    let credential = try CodexAuthFileLoader(fileURL: url).load()

    #expect(credential.accessToken == "fake-access-token")
    #expect(credential.accountID == "fake-account-id")
  }

  @Test
  func missingFileReportsCredentialMissing() {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("micai-auth-absent-\(UUID().uuidString).json")

    expect(loading: url, throws: .credentialMissing)
  }

  @Test
  func missingTokensReportsCredentialMissing() throws {
    let url = try writeTempAuth(#"{"auth_mode":"chatgpt"}"#)
    defer { try? FileManager.default.removeItem(at: url) }

    expect(loading: url, throws: .credentialMissing)
  }

  @Test
  func missingAccountIDReportsCredentialMissing() throws {
    let url = try writeTempAuth(
      #"{"tokens":{"access_token":"fake-access-token"}}"#
    )
    defer { try? FileManager.default.removeItem(at: url) }

    expect(loading: url, throws: .credentialMissing)
  }

  @Test
  func blankTokenValueReportsCredentialMissing() throws {
    let url = try writeTempAuth(
      #"{"tokens":{"access_token":"   ","account_id":"fake-account-id"}}"#
    )
    defer { try? FileManager.default.removeItem(at: url) }

    expect(loading: url, throws: .credentialMissing)
  }

  @Test
  func malformedJSONReportsCredentialMalformed() throws {
    let url = try writeTempAuth("this is not json {{{")
    defer { try? FileManager.default.removeItem(at: url) }

    expect(loading: url, throws: .credentialMalformed)
  }

  private func expect(loading url: URL, throws expected: MicAIError) {
    do {
      _ = try CodexAuthFileLoader(fileURL: url).load()
      Issue.record("Expected loading to throw \(expected)")
    } catch {
      #expect(error as? MicAIError == expected)
    }
  }

  private func writeTempAuth(_ contents: String) throws -> URL {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("micai-auth-\(UUID().uuidString).json")
    try contents.write(to: url, atomically: true, encoding: .utf8)
    return url
  }
}
