#if os(iOS) && targetEnvironment(simulator)
  import Foundation
  import UIKit

  enum IOSUIEvidenceReporter {
    @MainActor
    static func dumpIfRequested() async {
      guard ProcessInfo.processInfo.environment["MICAI_IOS_DUMP_HIERARCHY"] == "1" else {
        return
      }

      try? await Task.sleep(for: .milliseconds(750))
      guard
        let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
        let window = scene.windows.first(where: \.isKeyWindow) ?? scene.windows.first
      else {
        write("MicAI iOS runtime hierarchy\n<no window>\n")
        return
      }

      var lines = [
        "MicAI iOS runtime hierarchy",
        "fixture=\(fixtureName())",
        "window=\(String(describing: type(of: window))) frame=\(window.frame.integral)",
      ]
      describe(view: window, depth: 0, lines: &lines)
      write(lines.joined(separator: "\n") + "\n")
    }

    private static func fixtureName() -> String {
      let arguments = ProcessInfo.processInfo.arguments
      guard let index = arguments.firstIndex(of: "--fixture"),
        arguments.indices.contains(index + 1)
      else {
        return "primary"
      }
      return arguments[index + 1]
    }

    private static func describe(view: UIView, depth: Int, lines: inout [String]) {
      guard !view.isHidden, view.alpha > 0.01 else { return }
      let indent = String(repeating: "  ", count: depth)
      var attributes = [
        "frame=\(view.frame.integral)",
        "accessible=\(view.isAccessibilityElement)",
      ]
      if let identifier = view.accessibilityIdentifier, !identifier.isEmpty {
        attributes.append("id=\(quoted(identifier))")
      }
      if let label = view.accessibilityLabel, !label.isEmpty {
        attributes.append("label=\(quoted(label))")
      }
      if let value = view.accessibilityValue, !value.isEmpty {
        attributes.append("value=\(quoted(value))")
      }
      lines.append(
        "\(indent)\(String(describing: type(of: view))) \(attributes.joined(separator: " "))"
      )

      if let elements = view.accessibilityElements {
        for element in elements where !(element is UIView) {
          describe(accessibilityElement: element, depth: depth + 1, lines: &lines)
        }
      }
      for subview in view.subviews {
        describe(view: subview, depth: depth + 1, lines: &lines)
      }
    }

    private static func describe(
      accessibilityElement element: Any,
      depth: Int,
      lines: inout [String]
    ) {
      guard let object = element as? NSObject else { return }
      let indent = String(repeating: "  ", count: depth)
      var attributes = ["accessible=\(object.isAccessibilityElement)"]
      if let identified = object as? UIAccessibilityIdentification,
        let identifier = identified.accessibilityIdentifier,
        !identifier.isEmpty
      {
        attributes.append("id=\(quoted(identifier))")
      }
      if let label = object.accessibilityLabel, !label.isEmpty {
        attributes.append("label=\(quoted(label))")
      }
      if let value = object.accessibilityValue, !value.isEmpty {
        attributes.append("value=\(quoted(value))")
      }
      lines.append(
        "\(indent)\(String(describing: type(of: object))) \(attributes.joined(separator: " "))"
      )
    }

    private static func quoted(_ value: String) -> String {
      "\"\(value.replacingOccurrences(of: "\n", with: "\\n"))\""
    }

    private static func write(_ value: String) {
      FileHandle.standardOutput.write(Data(value.utf8))
    }
  }
#endif
