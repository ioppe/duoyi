import AppKit
import CoreText

/// Native side of the pomodoro floating window.
///
/// This file deliberately does not import FlutterMacOS: it only knows about a
/// small value type and two delegate callbacks, so it can be compiled and
/// reviewed on its own. The Flutter method channel lives in
/// `MainFlutterWindow.swift` and forwards to `PomodoroFloatingPanelController`.
///
/// The panel never owns a timer. Dart remains the single source of truth for the
/// countdown; native code only renders the state it is given.

// MARK: - Appearance

/// Colors and metrics pushed from Dart's real `Theme` / `DesignTokens`.
///
/// Every value is optional on the channel. When Dart omits `appearance`
/// (older payloads, standalone native smoke runs) the panel falls back to
/// dynamic AppKit semantic colors so the card still follows the system look
/// instead of a hardcoded sample palette.
struct PomodoroFloatingPanelAppearance {
  let backgroundColor: NSColor
  let foregroundColor: NSColor
  let secondaryColor: NSColor
  let primaryColor: NSColor
  let onPrimaryColor: NSColor
  let borderColor: NSColor
  let borderWidth: CGFloat
  let cornerRadius: CGFloat
  let controlRadius: CGFloat
  let timeFontSize: CGFloat
  let captionFontSize: CGFloat
  let buttonFontSize: CGFloat
  /// Main-window title-bar colors. They fall back to the card palette for old snapshots.
  let windowBackgroundColor: NSColor
  let windowForegroundColor: NSColor

  static let semanticFallback = PomodoroFloatingPanelAppearance(
    backgroundColor: .windowBackgroundColor,
    foregroundColor: .labelColor,
    secondaryColor: .secondaryLabelColor,
    primaryColor: .controlAccentColor,
    onPrimaryColor: .alternateSelectedControlTextColor,
    borderColor: .separatorColor,
    borderWidth: 0,
    cornerRadius: 16,
    controlRadius: 12,
    timeFontSize: 26,
    captionFontSize: 12,
    buttonFontSize: 14
  )

  init(
    backgroundColor: NSColor,
    foregroundColor: NSColor,
    secondaryColor: NSColor,
    primaryColor: NSColor,
    onPrimaryColor: NSColor,
    borderColor: NSColor,
    borderWidth: CGFloat,
    cornerRadius: CGFloat,
    controlRadius: CGFloat,
    timeFontSize: CGFloat,
    captionFontSize: CGFloat,
    buttonFontSize: CGFloat,
    windowBackgroundColor: NSColor? = nil,
    windowForegroundColor: NSColor? = nil
  ) {
    self.backgroundColor = backgroundColor
    self.foregroundColor = foregroundColor
    self.secondaryColor = secondaryColor
    self.primaryColor = primaryColor
    self.onPrimaryColor = onPrimaryColor
    self.borderColor = borderColor
    self.borderWidth = borderWidth
    self.cornerRadius = cornerRadius
    self.controlRadius = controlRadius
    self.timeFontSize = timeFontSize
    self.captionFontSize = captionFontSize
    self.buttonFontSize = buttonFontSize
    self.windowBackgroundColor = windowBackgroundColor ?? backgroundColor
    self.windowForegroundColor = windowForegroundColor ?? foregroundColor
  }
  /// Parses the nested `appearance` map. Missing keys keep their semantic
  /// default, so a partial payload never produces an unstyled card.
  init?(dictionary: [String: Any]?) {
    guard let dictionary = dictionary else {
      return nil
    }
    let fallback = PomodoroFloatingPanelAppearance.semanticFallback
    self.backgroundColor =
      PomodoroFloatingPanelAppearance.colorValue(dictionary["backgroundColor"])
      ?? fallback.backgroundColor
    self.foregroundColor =
      PomodoroFloatingPanelAppearance.colorValue(dictionary["foregroundColor"])
      ?? fallback.foregroundColor
    self.secondaryColor =
      PomodoroFloatingPanelAppearance.colorValue(dictionary["secondaryColor"])
      ?? fallback.secondaryColor
    self.primaryColor =
      PomodoroFloatingPanelAppearance.colorValue(dictionary["primaryColor"])
      ?? fallback.primaryColor
    self.onPrimaryColor =
      PomodoroFloatingPanelAppearance.colorValue(dictionary["onPrimaryColor"])
      ?? fallback.onPrimaryColor
    self.borderColor =
      PomodoroFloatingPanelAppearance.colorValue(dictionary["borderColor"])
      ?? fallback.borderColor
    self.borderWidth = PomodoroFloatingPanelAppearance.metricValue(
      dictionary["borderWidth"], fallback: fallback.borderWidth)
    self.cornerRadius = PomodoroFloatingPanelAppearance.metricValue(
      dictionary["cornerRadius"], fallback: fallback.cornerRadius)
    self.controlRadius = PomodoroFloatingPanelAppearance.metricValue(
      dictionary["controlRadius"], fallback: fallback.controlRadius)
    self.timeFontSize = PomodoroFloatingPanelAppearance.metricValue(
      dictionary["timeFontSize"], fallback: fallback.timeFontSize)
    self.captionFontSize = PomodoroFloatingPanelAppearance.metricValue(
      dictionary["captionFontSize"], fallback: fallback.captionFontSize)
    self.buttonFontSize = PomodoroFloatingPanelAppearance.metricValue(
      dictionary["buttonFontSize"], fallback: fallback.buttonFontSize)
    self.windowBackgroundColor =
      PomodoroFloatingPanelAppearance.colorValue(dictionary["windowBackgroundColor"])
      ?? self.backgroundColor
    self.windowForegroundColor =
      PomodoroFloatingPanelAppearance.colorValue(dictionary["windowForegroundColor"])
      ?? self.foregroundColor
  }

  /// Flutter sends colors as `uint32` ARGB values; alpha is honoured.
  private static func colorValue(_ value: Any?) -> NSColor? {
    guard let number = value as? NSNumber else {
      return nil
    }
    let argb = number.uint32Value
    let alpha = CGFloat((argb >> 24) & 0xFF) / 255.0
    let red = CGFloat((argb >> 16) & 0xFF) / 255.0
    let green = CGFloat((argb >> 8) & 0xFF) / 255.0
    let blue = CGFloat(argb & 0xFF) / 255.0
    return NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
  }

  private static func metricValue(_ value: Any?, fallback: CGFloat) -> CGFloat {
    guard let number = value as? NSNumber, number.doubleValue.isFinite else {
      return fallback
    }
    return CGFloat(number.doubleValue)
  }
}


// MARK: - Size

/// Card density pushed from Dart's device-local preference (`windowSize`).
///
/// Missing or unknown values fall back to `.large`, so an older Dart payload or
/// a standalone native run keeps the original 320 x 88 card.
enum PomodoroFloatingPanelSize: String {
  case large
  case compact

  static let fallback = PomodoroFloatingPanelSize.large

  init?(string: String?) {
    guard let raw = string?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
          !raw.isEmpty else {
      return nil
    }
    self.init(rawValue: raw)
  }

  /// Borderless panel content size. The compact card must stay visibly smaller.
  var panelSize: NSSize {
    switch self {
    case .large: return NSSize(width: 320, height: 88)
    case .compact: return NSSize(width: 236, height: 64)
    }
  }

  var horizontalPadding: CGFloat {
    switch self {
    case .large: return 16
    case .compact: return 12
    }
  }

  var verticalPadding: CGFloat {
    switch self {
    case .large: return 12
    case .compact: return 8
    }
  }

  var statusToTimeSpacing: CGFloat {
    switch self {
    case .large: return 6
    case .compact: return 2
    }
  }

  var timeToToggleSpacing: CGFloat {
    switch self {
    case .large: return 8
    case .compact: return 8
    }
  }

  var toggleToCloseSpacing: CGFloat {
    switch self {
    case .large: return 12
    case .compact: return 8
    }
  }

  var toggleButtonSize: NSSize {
    switch self {
    case .large: return NSSize(width: 96, height: 44)
    case .compact: return NSSize(width: 34, height: 30)
    }
  }

  var closeButtonSize: NSSize {
    switch self {
    case .large: return NSSize(width: 32, height: 32)
    case .compact: return NSSize(width: 24, height: 24)
    }
  }

  /// Only the large card pairs the symbol with the localized title; the compact
  /// card keeps the accessibility label and tooltip instead.
  var showsToggleTitle: Bool {
    switch self {
    case .large: return true
    case .compact: return false
    }
  }

  var closeSymbolPointSize: CGFloat {
    switch self {
    case .large: return 14
    case .compact: return 11
    }
  }

  func toggleSymbolPointSize(buttonFontSize: CGFloat) -> CGFloat {
    switch self {
    case .large: return max(12, buttonFontSize + 2)
    case .compact: return max(11, buttonFontSize - 1)
    }
  }

  /// Keeps the compact digits legible while leaving room for "1440:00" between
  /// the paddings and the two controls.
  func timeFontSize(_ appearanceSize: CGFloat) -> CGFloat {
    switch self {
    case .large: return appearanceSize
    case .compact: return min(appearanceSize, 26)
    }
  }

  func captionFontSize(_ appearanceSize: CGFloat) -> CGFloat {
    switch self {
    case .large: return appearanceSize
    case .compact: return min(appearanceSize, 11)
    }
  }
}
// MARK: - State

/// Snapshot pushed from Dart. Field names match the channel contract:
/// `timeText`, `isRunning`, `isPaused`, `canToggle`, `isBreak`, `stateLabel`,
/// `playLabel`, `pauseLabel`, `resumeLabel`, `closeLabel`, `windowTitle`,
/// `appearance`, and `windowSize` (missing or unknown means `.large`).
struct PomodoroFloatingPanelState {
  static let defaultPlayLabel = "Play"
  static let defaultPauseLabel = "Pause"
  static let defaultCloseLabel = "Close"

  let timeText: String
  let isRunning: Bool
  let isPaused: Bool
  let canToggle: Bool
  let isBreak: Bool
  let stateLabel: String
  let playLabel: String
  let pauseLabel: String
  let resumeLabel: String
  let closeLabel: String
  let windowTitle: String
  let appearance: PomodoroFloatingPanelAppearance
  let windowSize: PomodoroFloatingPanelSize

  /// Returns nil when `timeText` is missing, which the channel reports back to
  /// Dart as `invalid_arguments`.
  init?(arguments: [String: Any]?) {
    guard let arguments = arguments,
          let timeText = arguments["timeText"] as? String else {
      return nil
    }

    self.timeText = timeText
    self.isRunning = PomodoroFloatingPanelState.boolValue(arguments["isRunning"]) ?? false
    self.isPaused = PomodoroFloatingPanelState.boolValue(arguments["isPaused"]) ?? false
    self.canToggle = PomodoroFloatingPanelState.boolValue(arguments["canToggle"]) ?? true
    self.isBreak = PomodoroFloatingPanelState.boolValue(arguments["isBreak"]) ?? false
    self.stateLabel = PomodoroFloatingPanelState.stringValue(arguments["stateLabel"]) ?? ""
    self.playLabel = PomodoroFloatingPanelState.stringValue(arguments["playLabel"])
      ?? PomodoroFloatingPanelState.defaultPlayLabel
    self.pauseLabel = PomodoroFloatingPanelState.stringValue(arguments["pauseLabel"])
      ?? PomodoroFloatingPanelState.defaultPauseLabel
    self.resumeLabel = PomodoroFloatingPanelState.stringValue(arguments["resumeLabel"])
      ?? self.playLabel
    self.closeLabel = PomodoroFloatingPanelState.stringValue(arguments["closeLabel"])
      ?? PomodoroFloatingPanelState.defaultCloseLabel
    self.windowTitle = PomodoroFloatingPanelState.stringValue(arguments["windowTitle"]) ?? ""
    self.appearance = PomodoroFloatingPanelAppearance(
      dictionary: arguments["appearance"] as? [String: Any]
    ) ?? PomodoroFloatingPanelAppearance.semanticFallback
    self.windowSize =
      PomodoroFloatingPanelSize(string: arguments["windowSize"] as? String)
      ?? PomodoroFloatingPanelSize.fallback
  }

  /// Label and symbol for the single shared play/pause control: paused wins
  /// over running so a paused timer offers "continue" rather than "pause".
  var toggleLabel: String {
    if isPaused {
      return resumeLabel
    }
    return isRunning ? pauseLabel : playLabel
  }

  var toggleSymbolName: String {
    return (isRunning && !isPaused) ? "pause.fill" : "play.fill"
  }

  private static func boolValue(_ value: Any?) -> Bool? {
    if let value = value as? Bool {
      return value
    }
    if let value = value as? NSNumber {
      return value.boolValue
    }
    return nil
  }

  private static func stringValue(_ value: Any?) -> String? {
    guard let value = value as? String, !value.isEmpty else {
      return nil
    }
    return value
  }
}

/// Fonts derived from the appearance metrics, all from the bundled
/// `Noto Sans SC` family.
struct PomodoroFloatingPanelFonts {
  let time: NSFont
  let caption: NSFont
  let button: NSFont
}

// MARK: - Delegate

/// Callbacks into the Flutter bridge. Implemented in `MainFlutterWindow.swift`.
protocol PomodoroFloatingPanelDelegate: AnyObject {
  /// User pressed play/pause. Dart owns the toggle, there is no optimistic UI.
  func pomodoroFloatingPanelDidRequestToggle()
  /// User pressed the native close button; the panel is already hidden.
  func pomodoroFloatingPanelDidClose()
}

// MARK: - Panel

/// Borderless, non-activating floating panel that hosts the compact card.
final class PomodoroFloatingPanel: NSPanel {
  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { false }

  override func cancelOperation(_ sender: Any?) {
    // Escape must not close the panel; closing is a user action on the close
    // button only.
  }
}

/// Static text that ignores mouse events so dragging the digits moves the
/// panel, while VoiceOver still reads it as static text.
final class PomodoroTimeLabel: NSTextField {
  private func glyphLine() -> CTLine? {
    guard let font = font, !stringValue.isEmpty else { return nil }
    let attributes: [NSAttributedString.Key: Any] = [
      .font: font,
      NSAttributedString.Key(kCTForegroundColorAttributeName as String):
        (textColor ?? .labelColor).cgColor,
    ]
    return CTLineCreateWithAttributedString(
      NSAttributedString(string: stringValue, attributes: attributes) as CFAttributedString)
  }

  override var intrinsicContentSize: NSSize {
    var size = super.intrinsicContentSize
    if let line = glyphLine() {
      size.height = ceil(CTLineGetBoundsWithOptions(line, [.useGlyphPathBounds]).height)
    }
    return size
  }

  override func draw(_ dirtyRect: NSRect) {
    guard let line = glyphLine(), let context = NSGraphicsContext.current?.cgContext else { return }
    let glyphs = CTLineGetBoundsWithOptions(line, [.useGlyphPathBounds])
    context.saveGState()
    context.clip(to: bounds)
    if isFlipped {
      context.translateBy(x: 0, y: bounds.minY + bounds.maxY)
      context.scaleBy(x: 1, y: -1)
    }
    context.textMatrix = .identity
    context.textPosition = NSPoint(x: bounds.minX + 2, y: bounds.midY - glyphs.midY)
    CTLineDraw(line, context)
    context.restoreGState()
  }

  override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// Leaves the whole text column available as a window drag surface.
final class PomodoroTextColumn: NSStackView {
  override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// Panel background. Dragging anywhere that is not a control moves the panel.
final class PomodoroFloatingPanelContentView: NSView {
  static let cardIdentifier = NSUserInterfaceItemIdentifier("pomodoro.card")
  static let timeIdentifier = NSUserInterfaceItemIdentifier("pomodoro.time")
  static let statusIdentifier = NSUserInterfaceItemIdentifier("pomodoro.status")
  static let toggleIdentifier = NSUserInterfaceItemIdentifier("pomodoro.toggle")
  static let closeIdentifier = NSUserInterfaceItemIdentifier("pomodoro.close")

  var onToggle: (() -> Void)?
  var onClose: (() -> Void)?

  private let statusLabel = PomodoroTimeLabel(labelWithString: "")
  private let timeLabel = PomodoroTimeLabel(labelWithString: "")
  private let playPauseButton = PomodoroIconButton()
  private let closeButton = PomodoroIconButton()
  private let textColumn = PomodoroTextColumn(views: [])

  // Size-dependent constraints. Both densities share one view tree, so a
  // preference change only moves constraints and never rebuilds the panel.
  private var textColumnLeading: NSLayoutConstraint?
  private var textColumnHeight: NSLayoutConstraint?
  private var textColumnTrailing: NSLayoutConstraint?
  private var timeTrailing: NSLayoutConstraint?
  private var toggleTrailing: NSLayoutConstraint?
  private var toggleWidth: NSLayoutConstraint?
  private var toggleHeight: NSLayoutConstraint?
  private var closeTrailing: NSLayoutConstraint?
  private var closeWidth: NSLayoutConstraint?
  private var closeHeight: NSLayoutConstraint?

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    configure()
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
    configure()
  }

  private func configure() {
    wantsLayer = true
    layer?.cornerRadius = PomodoroFloatingPanelAppearance.semanticFallback.cornerRadius
    layer?.cornerCurve = .continuous
    layer?.masksToBounds = true
    identifier = Self.cardIdentifier
    setAccessibilityIdentifier(Self.cardIdentifier.rawValue)

    statusLabel.translatesAutoresizingMaskIntoConstraints = false
    statusLabel.alignment = .left
    statusLabel.lineBreakMode = .byTruncatingTail
    statusLabel.usesSingleLineMode = true
    statusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    statusLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)
    statusLabel.identifier = Self.statusIdentifier
    statusLabel.setAccessibilityIdentifier(Self.statusIdentifier.rawValue)

    timeLabel.translatesAutoresizingMaskIntoConstraints = false
    timeLabel.alignment = .left
    timeLabel.lineBreakMode = .byTruncatingTail
    timeLabel.usesSingleLineMode = true
    // Four-digit minutes ("1440:00") must never be clipped.
    timeLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
    timeLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)
    timeLabel.identifier = Self.timeIdentifier
    timeLabel.setAccessibilityIdentifier(Self.timeIdentifier.rawValue)

    playPauseButton.translatesAutoresizingMaskIntoConstraints = false
    playPauseButton.target = self
    playPauseButton.action = #selector(handleToggle)
    playPauseButton.identifier = Self.toggleIdentifier
    playPauseButton.setAccessibilityIdentifier(Self.toggleIdentifier.rawValue)
    addSubview(playPauseButton)

    closeButton.translatesAutoresizingMaskIntoConstraints = false
    closeButton.target = self
    closeButton.action = #selector(handleClose)
    closeButton.identifier = Self.closeIdentifier
    closeButton.setAccessibilityIdentifier(Self.closeIdentifier.rawValue)
    addSubview(closeButton)

    textColumn.orientation = .vertical
    textColumn.alignment = .leading
    textColumn.translatesAutoresizingMaskIntoConstraints = false
    textColumn.addArrangedSubview(statusLabel)
    textColumn.addArrangedSubview(timeLabel)
    addSubview(textColumn)

    let textColumnLeading = textColumn.leadingAnchor.constraint(equalTo: leadingAnchor)
    let textColumnTrailing = textColumn.trailingAnchor.constraint(
      lessThanOrEqualTo: playPauseButton.leadingAnchor)
    let textColumnHeight = textColumn.heightAnchor.constraint(lessThanOrEqualTo: heightAnchor)
    // The digits keep their intrinsic width; this is the slack allowed to break.
    let timeTrailing = timeLabel.trailingAnchor.constraint(
      lessThanOrEqualTo: playPauseButton.leadingAnchor)
    timeTrailing.priority = .defaultHigh
    let toggleTrailing = playPauseButton.trailingAnchor.constraint(
      equalTo: closeButton.leadingAnchor)
    let toggleWidth = playPauseButton.widthAnchor.constraint(equalToConstant: 0)
    let toggleHeight = playPauseButton.heightAnchor.constraint(equalToConstant: 0)
    let closeTrailing = closeButton.trailingAnchor.constraint(equalTo: trailingAnchor)
    let closeWidth = closeButton.widthAnchor.constraint(equalToConstant: 0)
    let closeHeight = closeButton.heightAnchor.constraint(equalToConstant: 0)

    self.textColumnLeading = textColumnLeading
    self.textColumnTrailing = textColumnTrailing
    self.textColumnHeight = textColumnHeight
    self.timeTrailing = timeTrailing
    self.toggleTrailing = toggleTrailing
    self.toggleWidth = toggleWidth
    self.toggleHeight = toggleHeight
    self.closeTrailing = closeTrailing
    self.closeWidth = closeWidth
    self.closeHeight = closeHeight

    NSLayoutConstraint.activate([
      textColumnLeading,
      textColumnTrailing,
      textColumnHeight,
      textColumn.centerYAnchor.constraint(equalTo: centerYAnchor),
      timeTrailing,
      toggleTrailing,
      toggleWidth,
      toggleHeight,
      playPauseButton.centerYAnchor.constraint(equalTo: centerYAnchor),
      closeTrailing,
      closeWidth,
      closeHeight,
      closeButton.centerYAnchor.constraint(equalTo: centerYAnchor),
    ])

    applyLayout(for: .large)
  }

  /// Applies the metrics of `size`. Called from `apply(state:fonts:)`, so a
  /// density change lands as an `update` and never as a new `show`.
  private func applyLayout(for size: PomodoroFloatingPanelSize) {
    textColumn.spacing = size.statusToTimeSpacing
    textColumnLeading?.constant = size.horizontalPadding
    textColumnTrailing?.constant = -size.timeToToggleSpacing
    textColumnHeight?.constant = -2 * size.verticalPadding
    timeTrailing?.constant = -size.timeToToggleSpacing
    toggleTrailing?.constant = -size.toggleToCloseSpacing
    toggleWidth?.constant = size.toggleButtonSize.width
    toggleHeight?.constant = size.toggleButtonSize.height
    closeTrailing?.constant = -size.horizontalPadding
    closeWidth?.constant = size.closeButtonSize.width
    closeHeight?.constant = size.closeButtonSize.height
  }

  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

  // Dragging the card (including the blank area around the digits) moves the
  // panel; buttons are subviews and keep receiving their own clicks.
  override func mouseDown(with event: NSEvent) {
    window?.performDrag(with: event)
  }

  func apply(state: PomodoroFloatingPanelState, fonts: PomodoroFloatingPanelFonts) {
    let appearance = state.appearance
    let size = state.windowSize
    applyLayout(for: size)

    layer?.backgroundColor = appearance.backgroundColor.cgColor
    layer?.cornerRadius = appearance.cornerRadius
    layer?.borderWidth = appearance.borderWidth
    layer?.borderColor = appearance.borderColor.cgColor

    statusLabel.stringValue = state.stateLabel
    statusLabel.isHidden = state.stateLabel.isEmpty
    statusLabel.font = fonts.caption
    statusLabel.textColor = appearance.secondaryColor
    statusLabel.setAccessibilityLabel(state.stateLabel.isEmpty ? nil : state.stateLabel)

    timeLabel.stringValue = state.timeText
    timeLabel.font = fonts.time
    timeLabel.textColor = appearance.foregroundColor
    timeLabel.setAccessibilityLabel(state.timeText)
    if state.isBreak {
      // The break phase is exposed to assistive technologies through the panel
      // content; there is no second timer or extra decoration.
      timeLabel.setAccessibilityValue(state.windowTitle.isEmpty ? nil : state.windowTitle)
    } else {
      timeLabel.setAccessibilityValue(nil)
    }

    let label = state.toggleLabel
    playPauseButton.setSymbol(
      state.toggleSymbolName,
      pointSize: size.toggleSymbolPointSize(buttonFontSize: appearance.buttonFontSize),
      accessibilityLabel: label,
      toolTip: label
    )
    playPauseButton.setFill(appearance.primaryColor, cornerRadius: appearance.controlRadius)
    // The compact card draws the SF Symbol only; the accessibility label and
    // tooltip above still carry the full localized action.
    playPauseButton.setTitle(
      size.showsToggleTitle ? label : "",
      font: fonts.button,
      color: appearance.onPrimaryColor
    )
    playPauseButton.isEnabled = state.canToggle
    playPauseButton.alphaValue = state.canToggle ? 1 : 0.35

    closeButton.setSymbol(
      "xmark",
      pointSize: size.closeSymbolPointSize,
      accessibilityLabel: state.closeLabel,
      toolTip: state.closeLabel
    )
    closeButton.setFill(nil, cornerRadius: appearance.controlRadius)
    closeButton.setTitle("", font: fonts.caption, color: appearance.secondaryColor)
    closeButton.setTint(appearance.secondaryColor)
    statusLabel.invalidateIntrinsicContentSize()
    timeLabel.invalidateIntrinsicContentSize()

    window?.title = state.windowTitle
    if !state.windowTitle.isEmpty {
      window?.setAccessibilityLabel(state.windowTitle)
    }
  }

  @objc private func handleToggle() {
    onToggle?()
  }

  @objc private func handleClose() {
    onClose?()
  }
}

/// Symbol + text button. Without a fill it behaves like a plain icon button
/// (the close control); with a fill it becomes the themed primary action.
final class PomodoroCenteredButtonCell: NSButtonCell {
  private func contentRects(in bounds: NSRect) -> (image: NSRect, title: NSRect) {
    let imageSize = image?.size ?? .zero
    let titleSize = attributedTitle.size()
    let hasTitle = !attributedTitle.string.isEmpty
    let gap: CGFloat = hasTitle && image != nil ? 6 : 0
    let titleWidth = min(titleSize.width, max(0, bounds.width - 16 - imageSize.width - gap))
    let width = imageSize.width + gap + titleWidth
    let leading = bounds.midX - width / 2
    return (
      NSRect(x: leading, y: bounds.midY - imageSize.height / 2,
             width: imageSize.width, height: imageSize.height),
      NSRect(x: leading + imageSize.width + gap, y: bounds.midY - titleSize.height / 2,
             width: titleWidth, height: titleSize.height)
    )
  }

  override func imageRect(forBounds bounds: NSRect) -> NSRect {
    contentRects(in: bounds).image
  }

  override func titleRect(forBounds bounds: NSRect) -> NSRect {
    contentRects(in: bounds).title
  }

  override func drawInterior(withFrame cellFrame: NSRect, in controlView: NSView) {
    let rects = contentRects(in: cellFrame)
    if let symbol = image {
      let color = (controlView as? NSButton)?.contentTintColor ?? .labelColor
      let tinted = NSImage(size: symbol.size, flipped: false) { rect in
        symbol.draw(in: rect)
        color.setFill()
        rect.fill(using: .sourceAtop)
        return true
      }
      tinted.draw(in: rects.image, from: .zero, operation: .sourceOver,
                  fraction: 1, respectFlipped: controlView.isFlipped, hints: nil)
    }
    if !attributedTitle.string.isEmpty {
      attributedTitle.draw(in: rects.title)
    }
  }
}

final class PomodoroIconButton: NSButton {
  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    cell = PomodoroCenteredButtonCell(textCell: "")
    setButtonType(.momentaryPushIn)
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
    cell = PomodoroCenteredButtonCell(textCell: "")
    setButtonType(.momentaryPushIn)
  }

  private var hoverTrackingArea: NSTrackingArea?
  private var restingTintColor: NSColor = .black
  private var restingFillColor: NSColor?
  private var hoverFillColor: NSColor?

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let hoverTrackingArea = hoverTrackingArea {
      removeTrackingArea(hoverTrackingArea)
    }
    let area = NSTrackingArea(
      rect: bounds,
      options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
      owner: self,
      userInfo: nil
    )
    addTrackingArea(area)
    hoverTrackingArea = area
  }

  override func mouseEntered(with event: NSEvent) {
    guard isEnabled else {
      super.mouseEntered(with: event)
      return
    }
    if let hoverFillColor = hoverFillColor {
      layer?.backgroundColor = hoverFillColor.cgColor
      return
    }
    guard let highlighted = restingTintColor.highlightedVariant else {
      super.mouseEntered(with: event)
      return
    }
    contentTintColor = highlighted
  }

  override func mouseExited(with event: NSEvent) {
    layer?.backgroundColor = restingFillColor?.cgColor
    contentTintColor = restingTintColor
    super.mouseExited(with: event)
  }

  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

  func setTint(_ color: NSColor) {
    restingTintColor = color
    contentTintColor = color
  }

  /// Solid themed background for the primary action; `nil` keeps the button
  /// transparent (close control).
  func setFill(_ color: NSColor?, cornerRadius: CGFloat) {
    wantsLayer = true
    layer?.cornerRadius = cornerRadius
    layer?.cornerCurve = .continuous
    layer?.masksToBounds = true
    restingFillColor = color
    hoverFillColor = color?.highlightedVariant
    layer?.backgroundColor = color?.cgColor
  }

  func setTitle(_ text: String, font: NSFont, color: NSColor) {
    imagePosition = text.isEmpty ? .imageOnly : .imageLeft
    attributedTitle = NSAttributedString(
      string: text,
      attributes: [
        .font: font,
        .foregroundColor: color,
      ]
    )
    lineBreakMode = .byTruncatingTail
    restingTintColor = color
    contentTintColor = color
  }

  func setSymbol(_ name: String, pointSize: CGFloat, accessibilityLabel: String, toolTip: String) {
    let configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)
    image = NSImage(systemSymbolName: name, accessibilityDescription: accessibilityLabel)?
      .withSymbolConfiguration(configuration)
    image?.isTemplate = true
    imagePosition = .imageLeft
    imageScaling = .scaleProportionallyDown
    isBordered = false
    bezelStyle = .regularSquare
    focusRingType = .none
    self.toolTip = toolTip
    setAccessibilityLabel(accessibilityLabel)
    setAccessibilityRole(.button)
  }
}

private extension NSColor {
  /// Slightly stronger version of a tint, used for hover feedback.
  var highlightedVariant: NSColor? {
    usingColorSpace(.sRGB)?.blended(withFraction: 0.35, of: .black)
  }
}

// MARK: - Controller

/// Owns the single floating panel instance, its App Nap suppression activity and
/// its on-screen placement. Main thread only.
final class PomodoroFloatingPanelController {
  static let shared = PomodoroFloatingPanelController()

  /// Initial content size. Every show/update then sizes the card from the
  /// snapshot's `windowSize`, keeping the remembered origin.
  static let panelSize = PomodoroFloatingPanelSize.large.panelSize
  static let frameAutosaveName = "DuoyiPomodoroFloatingPanel"

  weak var delegate: PomodoroFloatingPanelDelegate?

  private var panel: PomodoroFloatingPanel?
  private var state: PomodoroFloatingPanelState?
  private var activityToken: NSObjectProtocol?
  private var screenParametersObserver: NSObjectProtocol?
  private var didRegisterBundledFont = false
  private var cachedFonts: [FontKey: NSFont] = [:]

  private struct FontKey: Hashable {
    let size: CGFloat
    let weight: CGFloat
  }

  private static let screenMargin: CGFloat = 20
  private static let fontAssetRelativePath =
    "flutter_assets/assets/fonts/NotoSansSC-Variable.ttf"
  private static let fontFamilyCandidates = ["Noto Sans SC", "NotoSansSC", "Noto Sans SC Regular"]

  private init() {}

  var isPanelVisible: Bool {
    panel?.isVisible ?? false
  }

  /// Applies the state first, then shows the panel. Creates the panel on demand
  /// and reuses it after `hide()`.
  @discardableResult
  func show(_ state: PomodoroFloatingPanelState) -> Bool {
    let panel = ensurePanel()
    self.state = state
    updateActivity(isRunning: state.isRunning)
    applyStateToPanel()
    clampIntoVisibleFrame(panel)
    panel.orderFrontRegardless()
    return true
  }

  /// Updates content only. Never shows the panel and never moves it, so a theme
  /// or state change cannot shift the card.
  @discardableResult
  func update(_ state: PomodoroFloatingPanelState) -> Bool {
    self.state = state
    updateActivity(isRunning: state.isRunning)
    guard panel != nil else {
      return true
    }
    applyStateToPanel()
    return true
  }

  /// Hides the panel without touching the countdown or the App Nap activity.
  @discardableResult
  func hide() -> Bool {
    panel?.orderOut(nil)
    return true
  }

  /// Tears the panel down and ends the App Nap activity. The main app normally
  /// does not call this; it exists for disable/logout flows and app termination.
  @discardableResult
  func dispose() -> Bool {
    if let panel = panel {
      panel.orderOut(nil)
      panel.contentView = nil
      panel.close()
    }
    panel = nil
    state = nil
    endActivity()
    removeScreenParametersObserver()
    return true
  }

  // MARK: Panel lifecycle

  private func ensurePanel() -> PomodoroFloatingPanel {
    if let panel = panel {
      return panel
    }

    let panel = PomodoroFloatingPanel(
      contentRect: NSRect(origin: .zero, size: Self.panelSize),
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )
    panel.isFloatingPanel = true
    panel.level = .floating
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    panel.hidesOnDeactivate = false
    panel.allowsToolTipsWhenApplicationIsInactive = true
    panel.becomesKeyOnlyIfNeeded = true
    panel.isReleasedWhenClosed = false
    panel.isMovableByWindowBackground = true
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = true
    panel.animationBehavior = .none
    panel.isRestorable = false
    panel.title = ""

    let contentView = PomodoroFloatingPanelContentView(
      frame: NSRect(origin: .zero, size: Self.panelSize)
    )
    contentView.onToggle = { [weak self] in
      self?.delegate?.pomodoroFloatingPanelDidRequestToggle()
    }
    contentView.onClose = { [weak self] in
      self?.hide()
      self?.delegate?.pomodoroFloatingPanelDidClose()
    }
    panel.contentView = contentView

    let restoredFrame = panel.setFrameUsingName(Self.frameAutosaveName)
    panel.setFrameAutosaveName(Self.frameAutosaveName)
    if restoredFrame {
      // Only the position is reused: a size autosaved by an older, smaller
      // build must not shrink the themed card.
      panel.setContentSize(Self.panelSize)
    } else {
      panel.setFrameOrigin(self.defaultOrigin(for: panel))
    }

    self.panel = panel
    registerBundledFontIfNeeded()
    observeScreenParametersIfNeeded()
    return panel
  }

  private func applyStateToPanel() {
    guard let panel = panel, let state = state else {
      return
    }
    guard let contentView = panel.contentView as? PomodoroFloatingPanelContentView else {
      return
    }
    // Apply the target layout before resizing: AppKit keeps the window at least
    // as wide as the currently active required constraints, so resizing first
    // would leave the compact card wider than its own metrics.
    let targetSize = state.windowSize.panelSize
    let sizeChanged = panel.frame.size != targetSize
    contentView.apply(state: state, fonts: fonts(for: state))
    resize(panel, to: targetSize)
    // A compact card can be flush with the right edge. Growing it to large
    // must keep the close control reachable, while ordinary updates and theme
    // changes must continue to preserve the user's exact position.
    if sizeChanged {
      clampIntoVisibleFrame(panel)
    }
  }

  /// Resizes the card from its current origin, so switching density never looks
  /// like a drag and the per-second `update` cannot move the panel.
  private func resize(_ panel: NSPanel, to size: NSSize) {
    guard panel.frame.size != size else {
      return
    }
    panel.setFrame(NSRect(origin: panel.frame.origin, size: size), display: true)
  }

  // MARK: Placement

  private func defaultOrigin(for panel: NSPanel) -> NSPoint {
    let screen = NSScreen.main ?? NSScreen.screens.first
    guard let visibleFrame = screen?.visibleFrame else {
      return NSPoint(x: 0, y: 0)
    }
    return NSPoint(
      x: visibleFrame.maxX - panel.frame.width - Self.screenMargin,
      y: visibleFrame.maxY - panel.frame.height - Self.screenMargin
    )
  }

  /// Keeps the card inside the usable area of a screen. Called on every show
  /// and whenever the display configuration changes; `update` never moves it.
  private func clampIntoVisibleFrame(_ panel: NSPanel) {
    let frame = panel.frame
    let isOnKnownScreen = NSScreen.screens.contains { $0.visibleFrame.intersects(frame) }
    guard isOnKnownScreen,
          let visibleFrame = (panel.screen ?? NSScreen.main)?.visibleFrame else {
      panel.setFrameOrigin(defaultOrigin(for: panel))
      return
    }

    let minX = visibleFrame.minX + Self.screenMargin
    let maxX = max(minX, visibleFrame.maxX - frame.width - Self.screenMargin)
    let minY = visibleFrame.minY + Self.screenMargin
    let maxY = max(minY, visibleFrame.maxY - frame.height - Self.screenMargin)
    let clampedOrigin = NSPoint(
      x: min(max(frame.origin.x, minX), maxX),
      y: min(max(frame.origin.y, minY), maxY)
    )
    if clampedOrigin != frame.origin {
      panel.setFrameOrigin(clampedOrigin)
    }
  }

  private func observeScreenParametersIfNeeded() {
    guard screenParametersObserver == nil else {
      return
    }
    screenParametersObserver = NotificationCenter.default.addObserver(
      forName: NSApplication.didChangeScreenParametersNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      guard let self = self, let panel = self.panel else {
        return
      }
      self.clampIntoVisibleFrame(panel)
    }
  }

  private func removeScreenParametersObserver() {
    if let observer = screenParametersObserver {
      NotificationCenter.default.removeObserver(observer)
      screenParametersObserver = nil
    }
  }

  // MARK: App Nap

  /// Suppresses App Nap while the countdown runs. Uses
  /// `.userInitiatedAllowingIdleSystemSleep`, so the Mac may still sleep.
  private func updateActivity(isRunning: Bool) {
    if isRunning {
      beginActivityIfNeeded()
    } else {
      endActivity()
    }
  }

  private func beginActivityIfNeeded() {
    guard activityToken == nil else {
      return
    }
    activityToken = ProcessInfo.processInfo.beginActivity(
      options: .userInitiatedAllowingIdleSystemSleep,
      reason: "Duoyi pomodoro countdown is running; keep the floating panel responsive."
    )
  }

  private func endActivity() {
    guard let token = activityToken else {
      return
    }
    ProcessInfo.processInfo.endActivity(token)
    activityToken = nil
  }

  // MARK: Fonts

  /// Every visible string uses the bundled `Noto Sans SC` variable font that
  /// Flutter already ships inside `App.framework`, at the size the current
  /// appearance asks for (clamped for the compact card). Weights: time 600,
  /// caption 400, button 500.
  private func fonts(for state: PomodoroFloatingPanelState) -> PomodoroFloatingPanelFonts {
    let appearance = state.appearance
    let size = state.windowSize
    return PomodoroFloatingPanelFonts(
      time: font(size: size.timeFontSize(appearance.timeFontSize), weight: .semibold),
      caption: font(size: size.captionFontSize(appearance.captionFontSize), weight: .regular),
      button: font(size: appearance.buttonFontSize, weight: .medium)
    )
  }

  private func font(size: CGFloat, weight: NSFont.Weight) -> NSFont {
    let key = FontKey(size: size, weight: weight.rawValue)
    if let cached = cachedFonts[key] {
      return cached
    }
    registerBundledFontIfNeeded()
    let font = makeNotoFont(size: size, weight: weight)
      ?? NSFont.systemFont(ofSize: size, weight: weight)
    cachedFonts[key] = font
    return font
  }

  private func registerBundledFontIfNeeded() {
    guard !didRegisterBundledFont else {
      return
    }
    didRegisterBundledFont = true
    guard let fontURL = bundledFontURL() else {
      return
    }
    CTFontManagerRegisterFontsForURL(fontURL as CFURL, .process, nil)
  }

  private func bundledFontURL() -> URL? {
    guard let frameworksURL = Bundle.main.privateFrameworksURL else {
      return nil
    }
    let fontURL = frameworksURL
      .appendingPathComponent("App.framework", isDirectory: true)
      .appendingPathComponent("Resources", isDirectory: true)
      .appendingPathComponent(Self.fontAssetRelativePath)
    return FileManager.default.fileExists(atPath: fontURL.path) ? fontURL : nil
  }

  private func makeNotoFont(size: CGFloat, weight: NSFont.Weight) -> NSFont? {
    let availableFamilies = Set(NSFontManager.shared.availableFontFamilies)
    for family in Self.fontFamilyCandidates where availableFamilies.contains(family) {
      let descriptor = NSFontDescriptor(fontAttributes: [.family: family])
      let weighted = descriptor.addingAttributes([
        .traits: [NSFontDescriptor.TraitKey.weight: weight],
        .featureSettings: Self.tabularFigureFeatureSettings,
      ])
      if let font = NSFont(descriptor: weighted, size: size) {
        return font
      }
      if let fallback = NSFont(descriptor: descriptor, size: size) {
        return fallback
      }
    }
    return nil
  }

  /// `kNumberSpacingType` / `kMonospacedNumbersSelector` from CoreText's
  /// SFNTLayoutTypes.h, requested so the digits keep a stable width.
  private static let tabularFigureFeatureSettings: [[NSFontDescriptor.FeatureKey: Int]] = [
    [
      .typeIdentifier: 6,
      .selectorIdentifier: 0,
    ],
  ]
}
