import AppKit
import CoreText

/// Run with the production panel source; no Flutter engine or Xcode is needed:
/// swiftc -parse-as-library macos/Runner/PomodoroFloatingPanel.swift \
///   test/native/macos_pomodoro_panel_smoke.swift -o <scratch>/panel-smoke
/// <scratch>/panel-smoke <evidence-directory> [theme-snapshot.json]
///
/// The optional JSON file carries two complete Dart channel snapshots:
/// `{"default": {...}, "alternate": {...}}`. Only their `appearance` maps are
/// used, so the state values stay deterministic while the colors, radii and
/// font sizes are the real ones exported from the Flutter host test. Without
/// that file the panel falls back to dynamic AppKit semantic colors.
///
/// These checks do not replace a full app build or a real mouse drag.
@main
@MainActor
struct MacOSPomodoroPanelSmoke {
  final class Events: PomodoroFloatingPanelDelegate {
    var toggles = 0
    var closes = 0
    func pomodoroFloatingPanelDidRequestToggle() { toggles += 1 }
    func pomodoroFloatingPanelDidClose() { closes += 1 }
  }

  static let playLabel = "开始"
  static let pauseLabel = "暂停"
  static let resumeLabel = "继续"
  static let closeLabel = "隐藏悬浮窗"
  static let windowTitle = "番茄专注"

  static func main() throws {
    guard CommandLine.arguments.count > 1 else {
      throw NSError(
        domain: "MacOSPomodoroPanelSmoke", code: 5,
        userInfo: [
          NSLocalizedDescriptionKey:
            "usage: panel-smoke <evidence-directory> [theme-snapshot.json]"
        ])
    }
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
    NSApp.appearance = NSAppearance(named: .aqua)
    let fontAsset = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
      .appendingPathComponent("assets/fonts/NotoSansSC-Variable.ttf")
    let hasBundledFont = FileManager.default.fileExists(atPath: fontAsset.path)
    if hasBundledFont {
      CTFontManagerRegisterFontsForURL(fontAsset as CFURL, .process, nil)
    }

    let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

    let fixtures = try loadFixtures()
    let defaultAppearancePayload = fixtures["default"]?["appearance"] as? [String: Any]
    let defaultAppearance =
      PomodoroFloatingPanelAppearance(dictionary: defaultAppearancePayload)
      ?? PomodoroFloatingPanelAppearance.semanticFallback
    let alternateAppearancePayload = fixtures["alternate"]?["appearance"] as? [String: Any]
    let alternateTheme = alternateAppearance(from: alternateAppearancePayload)

    let controller = PomodoroFloatingPanelController.shared
    let events = Events()
    controller.delegate = events
    defer { controller.dispose() }
    var checked: [String] = []

    func check(_ condition: Bool, _ name: String) throws {
      if !condition {
        throw NSError(
          domain: "MacOSPomodoroPanelSmoke", code: 1,
          userInfo: [NSLocalizedDescriptionKey: name])
      }
      checked.append(name)
    }

    func snapshot(
      _ text: String,
      running: Bool = false,
      paused: Bool = false,
      allowed: Bool = true,
      isBreak: Bool = false,
      stateLabel: String? = nil,
      appearance: [String: Any]?
    ) -> PomodoroFloatingPanelState {
      var arguments: [String: Any] = [
        "timeText": text,
        "isRunning": running,
        "isPaused": paused,
        "canToggle": allowed,
        "isBreak": isBreak,
        "stateLabel": stateLabel ?? (paused ? "已暂停" : (running ? (isBreak ? "休息" : "专注中") : "待开始")),
        "playLabel": playLabel,
        "pauseLabel": pauseLabel,
        "resumeLabel": resumeLabel,
        "closeLabel": closeLabel,
        "windowTitle": windowTitle,
      ]
      if let appearance = appearance {
        arguments["appearance"] = appearance
      }
      return PomodoroFloatingPanelState(arguments: arguments)!
    }

    controller.update(snapshot("25:00", appearance: defaultAppearancePayload))
    try check(!controller.isPanelVisible, "update does not open the panel")

    controller.show(snapshot("25:00", appearance: defaultAppearancePayload))
    guard let panel = NSApp.windows.first(where: { $0 is PomodoroFloatingPanel }),
          let content = panel.contentView,
          let time = view(PomodoroFloatingPanelContentView.timeIdentifier, in: content)
            as? NSTextField,
          let status = view(PomodoroFloatingPanelContentView.statusIdentifier, in: content)
            as? NSTextField,
          let toggle = view(PomodoroFloatingPanelContentView.toggleIdentifier, in: content)
            as? NSButton,
          let close = view(PomodoroFloatingPanelContentView.closeIdentifier, in: content)
            as? NSButton else {
      throw NSError(
        domain: "MacOSPomodoroPanelSmoke", code: 2,
        userInfo: [NSLocalizedDescriptionKey: "panel content is missing identifier lookups"])
    }
    content.layoutSubtreeIfNeeded()

    try check(
      panel.isVisible && panel.frame.size == NSSize(width: 320, height: 88),
      "one compact themed card is shown")
    try check(
      panel.styleMask.contains(.nonactivatingPanel)
        && panel.level == .floating && !panel.hidesOnDeactivate,
      "panel floats without activating the application")
    try check(
      panel.collectionBehavior.contains(.canJoinAllSpaces)
        && panel.collectionBehavior.contains(.fullScreenAuxiliary),
      "panel joins desktop and full-screen workspaces")
    try check(
      time.stringValue == "25:00" && status.stringValue == "待开始"
        && time.identifier == PomodoroFloatingPanelContentView.timeIdentifier
        && toggle.identifier == PomodoroFloatingPanelContentView.toggleIdentifier
        && close.identifier == PomodoroFloatingPanelContentView.closeIdentifier,
      "initial snapshot and control identifiers are applied")
    try check(
      sameColor(content.layer?.backgroundColor, defaultAppearance.backgroundColor.cgColor)
        && content.layer?.cornerRadius == defaultAppearance.cornerRadius
        && content.layer?.borderWidth == defaultAppearance.borderWidth,
      "card paints the theme background, corner radius and border")
    try check(
      sameColor(time.textColor, defaultAppearance.foregroundColor)
        && sameColor(status.textColor, defaultAppearance.secondaryColor)
        && time.font?.pointSize == defaultAppearance.timeFontSize
        && status.font?.pointSize == defaultAppearance.captionFontSize,
      "time and status labels use the theme colors and font sizes")
    try check(
      sameColor(toggle.layer?.backgroundColor, defaultAppearance.primaryColor.cgColor)
        && toggle.layer?.cornerRadius == defaultAppearance.controlRadius
        && buttonTitleFont(toggle)?.pointSize == defaultAppearance.buttonFontSize
        && sameColor(buttonTitleColor(toggle), defaultAppearance.onPrimaryColor),
      "primary button is a themed solid control with its own label")
    let timeFrame = time.convert(time.bounds, to: content)
    let statusFrame = status.convert(status.bounds, to: content)
    let separation = abs(timeFrame.midY - statusFrame.midY)
      - (timeFrame.height + statusFrame.height) / 2
    try check(!timeFrame.intersects(statusFrame) && separation >= 4,
              "status and timer have a clear non-overlapping line gap")
    guard let toggleCell = toggle.cell, let closeCell = close.cell else {
      throw NSError(domain: "MacOSPomodoroPanelSmoke", code: 6)
    }
    let toggleImage = toggleCell.imageRect(forBounds: toggle.bounds)
    let closeImage = closeCell.imageRect(forBounds: close.bounds)
    try check(toggleImage.minX > 0
              && abs(closeImage.midX - close.bounds.midX) <= 2,
              "button icons are padded and centered with their labels")
    try check(
      content.acceptsFirstMouse(for: nil) && toggle.acceptsFirstMouse(for: nil)
        && close.acceptsFirstMouse(for: nil),
      "drag area and controls accept the first click while inactive")
    let originalTint = toggle.contentTintColor
    let hoverEvent = NSEvent.enterExitEvent(
      with: .mouseEntered, location: .zero, modifierFlags: [], timestamp: 0,
      windowNumber: panel.windowNumber, context: nil, eventNumber: 0,
      trackingNumber: 0, userData: nil)!
    toggle.mouseEntered(with: hoverEvent)
    toggle.mouseExited(with: hoverEvent)
    try check(
      toggle.contentTintColor == originalTint,
      "hover exit restores the original control tint")
    try check(
      content.hitTest(time.convert(NSPoint(x: time.bounds.midX, y: time.bounds.midY), to: content)) === content,
      "timer digits belong to the draggable background")
    try check(
      content.hitTest(NSPoint(x: toggle.frame.midX, y: toggle.frame.midY)) === toggle,
      "play button has its own mouse hit region")
    try check(
      content.hitTest(NSPoint(x: close.frame.midX, y: close.frame.midY)) === close,
      "close button has its own mouse hit region")
    let readyOffset = try capture(content, to: output.appendingPathComponent("panel-ready.png"))
    try check(abs(readyOffset) <= 1.5, "ready visible text is vertically centered (offset: \(readyOffset))")

    toggle.performClick(nil)
    try check(
      events.toggles == 1 && time.stringValue == "25:00",
      "play sends one callback without changing timer state locally")

    controller.update(snapshot("24:59", running: true, appearance: defaultAppearancePayload))
    content.layoutSubtreeIfNeeded()
    try check(
      time.stringValue == "24:59" && toggle.toolTip == pauseLabel
        && toggle.title == pauseLabel && status.stringValue == "专注中",
      "running snapshot shows the brand phase and the pause action")
    let runningOffset = try capture(content, to: output.appendingPathComponent("panel-running.png"))
    try check(abs(runningOffset) <= 1.5, "running visible text is vertically centered (offset: \(runningOffset))")

    controller.update(snapshot("24:59", paused: true, appearance: defaultAppearancePayload))
    content.layoutSubtreeIfNeeded()
    try check(
      time.stringValue == "24:59" && toggle.title == resumeLabel
        && toggle.toolTip == resumeLabel && status.stringValue == "已暂停",
      "paused snapshot keeps the time and offers continue")
    let pausedOffset = try capture(content, to: output.appendingPathComponent("panel-paused.png"))
    try check(abs(pausedOffset) <= 1.5, "paused visible text is vertically centered (offset: \(pausedOffset))")

    controller.update(snapshot("1440:00", appearance: defaultAppearancePayload))
    content.layoutSubtreeIfNeeded()
    let textWidth = (time.stringValue as NSString)
      .size(withAttributes: [.font: time.font!]).width
    try check(
      textWidth <= time.frame.width && time.stringValue == "1440:00",
      "maximum configured duration fits without truncating digits")
    let longOffset = try capture(content, to: output.appendingPathComponent("panel-long-duration.png"))
    try check(abs(longOffset) <= 1.5, "long duration visible text is vertically centered (offset: \(longOffset))")

    controller.update(
      snapshot(
        "05:00", allowed: false, isBreak: true, appearance: defaultAppearancePayload))
    content.layoutSubtreeIfNeeded()
    try check(
      !toggle.isEnabled && time.stringValue == "05:00",
      "disabled break snapshot is rendered")
    toggle.performClick(nil)
    try check(events.toggles == 1, "disabled button does not invoke timer control")

    controller.hide()
    controller.update(
      snapshot(
        "04:59", running: true, isBreak: true, appearance: defaultAppearancePayload))
    try check(
      !controller.isPanelVisible && time.stringValue == "04:59",
      "hidden panel receives updates without reopening")

    controller.show(
      snapshot(
        "04:59", running: true, isBreak: true, appearance: defaultAppearancePayload))
    let visibleFrame = (panel.screen ?? NSScreen.main)!.visibleFrame
    panel.setFrameOrigin(NSPoint(x: visibleFrame.midX - 160, y: visibleFrame.midY - 44))
    let movedFrame = panel.frame
    controller.hide()
    controller.show(
      snapshot(
        "04:58", running: true, isBreak: true, appearance: defaultAppearancePayload))
    try check(panel.frame == movedFrame, "hide and show retain the moved position")

    panel.setFrameOrigin(NSPoint(x: -1_000_000, y: -1_000_000))
    controller.show(
      snapshot(
        "04:57", running: true, isBreak: true, appearance: defaultAppearancePayload))
    try check(
      NSScreen.screens.contains(where: { $0.visibleFrame.contains(panel.frame) }),
      "an off-screen panel returns to a visible screen")

    // Theme switch must not move the card, rebuild the panel or add a second one.
    let themedFrame = panel.frame
    let windowCount = NSApp.windows.filter { $0 is PomodoroFloatingPanel }.count
    controller.update(
      snapshot(
        "04:57", running: true, isBreak: true, appearance: alternateAppearancePayload))
    content.layoutSubtreeIfNeeded()
    try check(
      panel.frame == themedFrame
        && NSApp.windows.filter { $0 is PomodoroFloatingPanel }.count == windowCount
        && windowCount == 1
        && panel.contentView === content,
      "theme change keeps one panel in place")
    try check(
      sameColor(content.layer?.backgroundColor, alternateTheme.backgroundColor.cgColor)
        && content.layer?.cornerRadius == alternateTheme.cornerRadius
        && content.layer?.borderWidth == alternateTheme.borderWidth
        && sameColor(time.textColor, alternateTheme.foregroundColor)
        && time.font?.pointSize == alternateTheme.timeFontSize
        && toggle.layer?.cornerRadius == alternateTheme.controlRadius
        && sameColor(toggle.layer?.backgroundColor, alternateTheme.primaryColor.cgColor),
      "second theme repaints colors, radii and font sizes in place")
    let alternateOffset = try capture(content, to: output.appendingPathComponent("panel-alternate-theme.png"))
    try check(abs(alternateOffset) <= 1.5, "alternate theme visible text is vertically centered (offset: \(alternateOffset))")

    close.performClick(nil)
    try check(
      events.closes == 1 && !controller.isPanelVisible
        && time.stringValue == "04:57",
      "close hides once without resetting the timer")
    controller.dispose()
    try check(!controller.isPanelVisible, "dispose releases the visible panel")
    if hasBundledFont {
      try check(time.font?.familyName?.contains("Noto") == true,
                "renders with the same bundled Noto family as the app")
    }
    try check(checked.count >= 24, "all expected checks were executed")

    let result: [String: Any] = [
      "checksPassed": checked.count, "checks": checked,
      "scope": "production AppKit panel without Flutter engine",
      "themeFixture": fixtures.isEmpty ? "semantic-fallback" : "flutter-snapshot",
      "realMouseDragVerified": false, "fullApplicationBuildVerified": false,
      "renderedFontFamily": time.font?.familyName ?? "",
      "textCenterOffsets": ["ready": readyOffset, "running": runningOffset,
                            "paused": pausedOffset, "longDuration": longOffset,
                            "alternate": alternateOffset],
    ]
    let data = try JSONSerialization.data(
      withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
    try data.write(to: output.appendingPathComponent("native-smoke.json"))
    print(String(data: data, encoding: .utf8)!)
  }

  // MARK: Helpers

  static func loadFixtures() throws -> [String: [String: Any]] {
    guard CommandLine.arguments.count > 2 else {
      return [:]
    }
    let url = URL(fileURLWithPath: CommandLine.arguments[2])
    let data = try Data(contentsOf: url)
    guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      return [:]
    }
    var fixtures: [String: [String: Any]] = [:]
    if let fallback = root["default"] as? [String: Any] {
      fixtures["default"] = fallback
    }
    if let alternate = root["alternate"] as? [String: Any] {
      fixtures["alternate"] = alternate
    }
    return fixtures
  }

  /// Alternative theme: the exported Flutter snapshot when present, otherwise
  /// another dynamic system palette (never the retired sample colors).
  static func alternateAppearance(
    from payload: [String: Any]?
  ) -> PomodoroFloatingPanelAppearance {
    if let appearance = PomodoroFloatingPanelAppearance(dictionary: payload) {
      return appearance
    }
    let fallback = PomodoroFloatingPanelAppearance.semanticFallback
    return PomodoroFloatingPanelAppearance(
      backgroundColor: .underPageBackgroundColor,
      foregroundColor: .labelColor,
      secondaryColor: .secondaryLabelColor,
      primaryColor: .systemOrange,
      onPrimaryColor: .alternateSelectedControlTextColor,
      borderColor: fallback.borderColor,
      borderWidth: 1,
      cornerRadius: fallback.cornerRadius - 6,
      controlRadius: fallback.controlRadius - 4,
      timeFontSize: fallback.timeFontSize - 2,
      captionFontSize: fallback.captionFontSize - 1,
      buttonFontSize: fallback.buttonFontSize - 1
    )
  }

  /// Recursive identifier lookup so nested stacks/tracks stay verifiable.
  static func view(_ identifier: NSUserInterfaceItemIdentifier, in root: NSView) -> NSView? {
    if root.identifier == identifier {
      return root
    }
    for subview in root.subviews {
      if let match = view(identifier, in: subview) {
        return match
      }
    }
    return nil
  }

  static func buttonTitleFont(_ button: NSButton) -> NSFont? {
    guard button.attributedTitle.length > 0 else {
      return nil
    }
    return button.attributedTitle.attribute(
      .font, at: 0, effectiveRange: nil) as? NSFont
  }

  static func buttonTitleColor(_ button: NSButton) -> NSColor? {
    guard button.attributedTitle.length > 0 else {
      return nil
    }
    return button.attributedTitle.attribute(
      .foregroundColor, at: 0, effectiveRange: nil) as? NSColor
  }

  static func sameColor(_ lhs: NSColor?, _ rhs: NSColor?) -> Bool {
    guard let lhs = lhs?.usingColorSpace(.sRGB),
          let rhs = rhs?.usingColorSpace(.sRGB) else {
      return false
    }
    let tolerance: CGFloat = 0.01
    return abs(lhs.redComponent - rhs.redComponent) <= tolerance
      && abs(lhs.greenComponent - rhs.greenComponent) <= tolerance
      && abs(lhs.blueComponent - rhs.blueComponent) <= tolerance
      && abs(lhs.alphaComponent - rhs.alphaComponent) <= tolerance
  }

  static func sameColor(_ lhs: CGColor?, _ rhs: CGColor?) -> Bool {
    guard let lhs = lhs, let rhs = rhs else {
      return false
    }
    return sameColor(NSColor(cgColor: lhs), NSColor(cgColor: rhs))
  }

  static func capture(_ view: NSView, to url: URL) throws -> Double {
    view.layoutSubtreeIfNeeded()
    view.displayIfNeeded()
    guard let image = view.bitmapImageRepForCachingDisplay(in: view.bounds),
          let time = self.view(PomodoroFloatingPanelContentView.timeIdentifier, in: view) as? NSTextField,
          let status = self.view(PomodoroFloatingPanelContentView.statusIdentifier, in: view) as? NSTextField else {
      throw NSError(domain: "MacOSPomodoroPanelSmoke", code: 3)
    }
    view.cacheDisplay(in: view.bounds, to: image)
    guard let png = image.representation(using: .png, properties: [:]) else {
      throw NSError(domain: "MacOSPomodoroPanelSmoke", code: 4)
    }
    try png.write(to: url)

    let region = time.convert(time.bounds, to: view)
      .union(status.convert(status.bounds, to: view))
    let scaleX = Double(image.pixelsWide) / Double(view.bounds.width)
    let scaleY = Double(image.pixelsHigh) / Double(view.bounds.height)
    let minX = max(0, Int((Double(region.minX) - 2) * scaleX))
    let maxX = min(image.pixelsWide, Int((Double(region.maxX) + 2) * scaleX))
    let colors = [time.textColor, status.textColor].compactMap { $0?.usingColorSpace(.sRGB) }
    var firstY = image.pixelsHigh
    var lastY = -1
    let inset = Int(4 * scaleY)
    for y in inset..<(image.pixelsHigh - inset) {
      for x in minX..<maxX {
        guard let pixel = image.colorAt(x: x, y: y)?.usingColorSpace(.sRGB),
              pixel.alphaComponent > 0.95 else { continue }
        if colors.contains(where: {
          abs(pixel.redComponent - $0.redComponent) < 0.18
            && abs(pixel.greenComponent - $0.greenComponent) < 0.18
            && abs(pixel.blueComponent - $0.blueComponent) < 0.18
        }) {
          firstY = min(firstY, y)
          lastY = max(lastY, y)
          break
        }
      }
    }
    guard lastY >= firstY else {
      throw NSError(domain: "MacOSPomodoroPanelSmoke", code: 7,
                    userInfo: [NSLocalizedDescriptionKey: "No rendered text pixels in \(url.lastPathComponent)"])
    }
    return Double(firstY + lastY + 1) / (2 * scaleY) - Double(view.bounds.height) / 2
  }
}
