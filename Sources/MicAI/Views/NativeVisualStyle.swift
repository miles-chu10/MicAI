import SwiftUI

struct MicAIActionCluster<Content: View>: View {
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
  private let content: Content

  init(@ViewBuilder content: () -> Content) {
    self.content = content()
  }

  var body: some View {
    if #available(macOS 26.0, *), !reduceTransparency {
      GlassEffectContainer(spacing: 10) {
        content
      }
    } else {
      content
    }
  }
}

extension View {
  @ViewBuilder
  func micAIPrimaryButtonStyle() -> some View {
    if #available(macOS 26.0, *) {
      buttonStyle(.glassProminent)
    } else {
      buttonStyle(.borderedProminent)
    }
  }

  @ViewBuilder
  func micAISecondaryButtonStyle() -> some View {
    if #available(macOS 26.0, *) {
      buttonStyle(.glass)
    } else {
      buttonStyle(.bordered)
    }
  }

  func micAIStatusSurface() -> some View {
    modifier(MicAIStatusSurfaceModifier())
  }

  func micAIPanelSurface(cornerRadius: CGFloat = 12) -> some View {
    modifier(MicAIPanelSurfaceModifier(cornerRadius: cornerRadius))
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
}

private struct MicAIStatusSurfaceModifier: ViewModifier {
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
  @Environment(\.colorScheme) private var colorScheme

  func body(content: Content) -> some View {
    if #available(macOS 26.0, *), !reduceTransparency {
      content.glassEffect(.regular, in: .capsule)
    } else {
      content.background(fallbackFill, in: .capsule)
    }
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
    if #available(macOS 26.0, *), !reduceTransparency {
      content.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
    } else {
      content.background(
        fallbackFill,
        in: .rect(cornerRadius: cornerRadius)
      )
    }
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
