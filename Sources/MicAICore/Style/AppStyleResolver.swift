import Foundation

/// Picks a `StyleTone` for the app the text is about to land in.
///
/// Resolution order, first match wins:
/// 1. a user override for the bundle identifier,
/// 2. the built-in bundle identifier table,
/// 3. a case-insensitive match on the application name,
/// 4. `defaultTone`.
///
/// Step 3 exists because the table below is best-effort: bundle identifiers
/// change between releases and distribution channels (App Store vs. direct
/// download), so a name match keeps the feature working when an identifier
/// drifts. Anything still wrong is fixable by the user in Settings, which is
/// what `overrides` carries.
public struct AppStyleResolver: Sendable {
  /// Bundle identifier -> tone. Best-effort; `nameKeywords` backs it up.
  public static let builtInBundleTones: [String: StyleTone] = [
    // Chat and messaging
    "com.tinyspeck.slackmacgap": .casual,
    "com.apple.MobileSMS": .casual,
    "com.hnc.Discord": .casual,
    "net.whatsapp.WhatsApp": .casual,
    "ru.keepcoder.Telegram": .casual,
    "com.facebook.archon": .casual,

    // Email and documents
    "com.apple.mail": .professional,
    "com.microsoft.Outlook": .professional,
    "com.readdle.smartemail-Mac": .professional,
    "com.microsoft.teams2": .professional,
    "com.microsoft.Word": .professional,
    "com.apple.iWork.Pages": .professional,
    "com.linkedin.LinkedIn": .professional,

    // Code, terminals, AI prompts
    "com.apple.Terminal": .technical,
    "com.googlecode.iterm2": .technical,
    "dev.warp.Warp-Stable": .technical,
    "com.apple.dt.Xcode": .technical,
    "com.microsoft.VSCode": .technical,
    "com.todesktop.230313mzl4w4u92": .technical,  // Cursor
    "com.openai.chat": .technical,
    "com.anthropic.claudefordesktop": .technical,

    // Notes
    "com.apple.Notes": .neutral,
    "com.apple.TextEdit": .neutral,
    "notion.id": .neutral,
    "md.obsidian": .neutral,
  ]

  /// Lowercased substring of the application name -> tone, checked in order.
  /// Ordered most-specific first so "Microsoft Teams" does not fall into a
  /// broader match before it is tested.
  public static let nameKeywords: [(keyword: String, tone: StyleTone)] = [
    ("outlook", .professional),
    ("teams", .professional),
    ("mail", .professional),
    ("word", .professional),
    ("pages", .professional),
    ("linkedin", .professional),
    ("slack", .casual),
    ("messages", .casual),
    ("discord", .casual),
    ("whatsapp", .casual),
    ("telegram", .casual),
    ("messenger", .casual),
    ("signal", .casual),
    ("xcode", .technical),
    ("terminal", .technical),
    ("iterm", .technical),
    ("warp", .technical),
    ("code", .technical),
    ("cursor", .technical),
    ("zed", .technical),
    ("chatgpt", .technical),
    ("claude", .technical),
    ("notes", .neutral),
    ("textedit", .neutral),
    ("notion", .neutral),
    ("obsidian", .neutral),
  ]

  private let overrides: [String: StyleTone]
  private let defaultTone: StyleTone

  public init(
    overrides: [String: StyleTone] = [:],
    defaultTone: StyleTone = .neutral
  ) {
    self.overrides = overrides
    self.defaultTone = defaultTone
  }

  /// Resolves the tone for a target, falling back to `defaultTone`.
  public func tone(for target: TargetIdentity?) -> StyleTone {
    guard let target else {
      return defaultTone
    }

    if let bundleIdentifier = target.bundleIdentifier {
      if let override = overrides[bundleIdentifier] {
        return override
      }
      if let builtIn = Self.builtInBundleTones[bundleIdentifier] {
        return builtIn
      }
    }

    if let applicationName = target.applicationName?.lowercased() {
      for (keyword, tone) in Self.nameKeywords where applicationName.contains(keyword) {
        return tone
      }
    }

    return defaultTone
  }

  /// True when the tone came from a user override rather than a built-in guess.
  /// Settings uses this to show which rows the user has already corrected.
  public func hasOverride(forBundleIdentifier bundleIdentifier: String) -> Bool {
    overrides[bundleIdentifier] != nil
  }
}
