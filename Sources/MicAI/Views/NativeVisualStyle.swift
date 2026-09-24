import MicAICore
import SwiftUI

// Liquid Glass APIs ship with the macOS 26 SDK (Swift 6.2 toolchains).
// `#available` is only a runtime check, so each glass branch is also gated at
// compile time; older SDKs (CI's default Xcode) build the fallback styling.

struct MicAIActionCluster<Content: View>: View {
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
  private let content: Content

  init(@ViewBuilder content: () -> Content) {
    self.content = content()
  }

  var body: some View {
    #if compiler(>=6.2)
      if #available(macOS 26.0, *), !reduceTransparency {
        GlassEffectContainer(spacing: 10) {
          content
        }
      } else {
        content
      }
    #else
      content
    #endif
  }
}

extension View {
  @ViewBuilder
  func micAIPrimaryButtonStyle() -> some View {
    #if compiler(>=6.2)
      if #available(macOS 26.0, *) {
        buttonStyle(.glassProminent)
      } else {
        buttonStyle(.borderedProminent)
      }
    #else
      buttonStyle(.borderedProminent)
    #endif
  }

  @ViewBuilder
  func micAISecondaryButtonStyle() -> some View {
    #if compiler(>=6.2)
      if #available(macOS 26.0, *) {
        buttonStyle(.glass)
      } else {
        buttonStyle(.bordered)
      }
    #else
      buttonStyle(.bordered)
    #endif
  }

  func micAIStatusSurface() -> some View {
    modifier(MicAIStatusSurfaceModifier())
  }

  func micAIPanelSurface(cornerRadius: CGFloat = 12) -> some View {
    modifier(MicAIPanelSurfaceModifier(cornerRadius: cornerRadius))
  }

  /// Opaque card for content. Glass stays on controls and floating chrome, per
  /// the Liquid Glass guidance, so reading surfaces keep full contrast.
  func micAICardSurface(cornerRadius: CGFloat = 12) -> some View {
    background(.background, in: .rect(cornerRadius: cornerRadius))
      .overlay {
        RoundedRectangle(cornerRadius: cornerRadius)
          .strokeBorder(.separator, lineWidth: 1)
      }
  }

  /// Tinted banner for a message the user should act on.
  func micAINoticeSurface(tint: Color, cornerRadius: CGFloat = 10) -> some View {
    padding(12)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(tint.opacity(0.1), in: .rect(cornerRadius: cornerRadius))
  }

  func micAIHUDSurface(cornerRadius: CGFloat = 16) -> some View {
    modifier(MicAIHUDSurfaceModifier(cornerRadius: cornerRadius))
  }
}

/// Semantic readiness colors that remain legible in light and dark appearances.
enum MicAIStatusColor {
  static var ready: Color { Color(nsColor: .systemGreen) }
  static var attention: Color { Color(nsColor: .systemOrange) }
  static var danger: Color { Color(nsColor: .systemRed) }
  static var accent: Color { Color.accentColor }

  /// One tint per mode so the HUD tells dictation, commands, translation and
  /// questions apart at a glance.
  static func modeTint(_ mode: MicAIMode?) -> Color {
    switch mode {
    case .dictation, nil:
      Color(nsColor: .systemRed)
    case .command:
      Color(nsColor: .systemTeal)
    case .translate:
      Color(nsColor: .systemIndigo)
    case .ask:
      Color(nsColor: .systemPurple)
    }
  }
}

private struct MicAIStatusSurfaceModifier: ViewModifier {
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
  @Environment(\.colorScheme) private var colorScheme

  func body(content: Content) -> some View {
    #if compiler(>=6.2)
      if #available(macOS 26.0, *), !reduceTransparency {
        content.glassEffect(.regular, in: .capsule)
      } else {
        content.background(fallbackFill, in: .capsule)
      }
    #else
      content.background(fallbackFill, in: .capsule)
    #endif
  }

  private var fallbackFill: Color {
    colorScheme == .dark
      ? Color.primary.opacity(0.14)
      : Color.primary.opacity(0.08)
  }
}

private struct MicAIPanelSurfaceModifier: ViewModifier {
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
  @Environment(\.colorScheme) private var colorScheme
  let cornerRadius: CGFloat

  func body(content: Content) -> some View {
    #if compiler(>=6.2)
      if #available(macOS 26.0, *), !reduceTransparency {
        content.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
      } else {
        content.background(
          fallbackFill,
          in: .rect(cornerRadius: cornerRadius)
        )
      }
    #else
      content.background(
        fallbackFill,
        in: .rect(cornerRadius: cornerRadius)
      )
    #endif
  }

  private var fallbackFill: Color {
    colorScheme == .dark
      ? Color.primary.opacity(0.12)
      : Color.primary.opacity(0.06)
  }
}

private struct MicAIHUDSurfaceModifier: ViewModifier {
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
  @Environment(\.colorScheme) private var colorScheme
  let cornerRadius: CGFloat

  func body(content: Content) -> some View {
    content
      .background(hudFill, in: .rect(cornerRadius: cornerRadius))
      .overlay {
        RoundedRectangle(cornerRadius: cornerRadius)
          .strokeBorder(separatorStroke, lineWidth: 1)
      }
  }

  private var hudFill: AnyShapeStyle {
    if reduceTransparency {
      AnyShapeStyle(
        colorScheme == .dark
          ? Color(nsColor: .windowBackgroundColor)
          : Color(nsColor: .controlBackgroundColor)
      )
    } else {
      AnyShapeStyle(.regularMaterial)
    }
  }

  private var separatorStroke: Color {
    Color.primary.opacity(colorScheme == .dark ? 0.28 : 0.16)
  }
}
