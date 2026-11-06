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

  /// Borderless panel content size. The compact card starts at the narrowest
  /// width that still keeps a visible gap between the digits and the controls;
  /// the controller then widens it only when the current duration needs it.
  var panelSize: NSSize {
    switch self {
    case .large: return NSSize(width: 320, height: 88)
    case .compact: return NSSize(width: 176, height: 64)
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

  /// Keeps the compact digits legible; the card width is measured from the
  /// rendered value instead of reserving a fixed four-digit minute budget.
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
  let controlSessionId: String
  let controlRevision: Int
  let controlState: String

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
    self.controlSessionId = arguments["controlSessionId"] as? String ?? ""
    self.controlRevision = max(0, (arguments["controlRevision"] as? NSNumber)?.intValue ?? 0)
    self.controlState = arguments["controlState"] as? String ?? ""
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

// MARK: - Placement geometry

/// Pure geometry for keeping the floating card reachable across displays.
///
/// AppKit window frames and `NSEvent.mouseLocation` are both global *logical*
/// points, so nothing here scales, rounds or converts between points and
/// backing pixels, and negative origins (a display left of or below the main
/// one) stay valid.
///
/// The panel's own `constrainFrameRect` is open, so a native
/// `performDrag(with:)` may carry the card over a display seam; the controller
/// restores visibility only at safe moments (show, real size change, display
/// topology change, drag end).
struct PomodoroFloatingPanelGeometry {
  /// Area of `frame` covered by the union of `screens`, so overlapping,
  /// mirrored or duplicated display rectangles are never counted twice.
  static func coveredArea(_ frame: NSRect, by screens: [NSRect]) -> CGFloat {
    guard frame.width > 0, frame.height > 0 else {
      return 0
    }
    let pieces = screens.compactMap { screen -> NSRect? in
      let clipped = screen.intersection(frame)
      guard !clipped.isNull, clipped.width > 0, clipped.height > 0 else {
        return nil
      }
      return clipped
    }
    guard !pieces.isEmpty else {
      return 0
    }

    var stops = Set<CGFloat>()
    for piece in pieces {
      stops.insert(piece.minX)
      stops.insert(piece.maxX)
    }
    let columns = stops.sorted()
    var area: CGFloat = 0
    for index in 0..<(columns.count - 1) {
      let left = columns[index]
      let right = columns[index + 1]
      guard right > left else {
        continue
      }
      // Merge the vertical spans of every display covering this column; the
      // union can be several disjoint strips (stacked displays with a seam).
      let spans = pieces
        .filter { $0.minX <= left && $0.maxX >= right }
        .map { (min: $0.minY, max: $0.maxY) }
        .sorted { $0.min < $1.min }
      var covered: CGFloat = 0
      var stripStart: CGFloat?
      var stripEnd: CGFloat = 0
      for span in spans {
        if let start = stripStart {
          if span.min > stripEnd {
            covered += stripEnd - start
            stripStart = span.min
            stripEnd = span.max
          } else {
            stripEnd = max(stripEnd, span.max)
          }
        } else {
          stripStart = span.min
          stripEnd = span.max
        }
      }
      if let start = stripStart {
        covered += stripEnd - start
      }
      area += (right - left) * covered
    }
    return area
  }

  /// Display that should own the card: the one under the pointer right after a
  /// drop, otherwise the largest overlap, otherwise the nearest one.
  static func targetVisibleFrame(
    frame: NSRect,
    screens: [NSRect],
    pointer: NSPoint?
  ) -> NSRect? {
    guard !screens.isEmpty else {
      return nil
    }
    if let pointer = pointer, let hovered = screens.first(where: { $0.contains(pointer) }) {
      return hovered
    }
    var best: NSRect?
    var bestArea: CGFloat = 0
    for screen in screens {
      let overlap = screen.intersection(frame)
      guard !overlap.isNull else {
        continue
      }
      let area = overlap.width * overlap.height
      if area > bestArea {
        bestArea = area
        best = screen
      }
    }
    if let best = best {
      return best
    }
    let centre = NSPoint(x: frame.midX, y: frame.midY)
    return screens.min {
      squaredDistance(from: centre, to: $0) < squaredDistance(from: centre, to: $1)
    }
  }

  /// Placement for show, a real size change or a display topology change: a
  /// card that already sits on a display keeps its exact origin, and a card
  /// that hangs over an edge is pulled back inside the margin.
  static func fittedOrigin(
    frame: NSRect,
    screens: [NSRect],
    margin: CGFloat,
    pointer: NSPoint? = nil
  ) -> NSPoint? {
    guard let target = targetVisibleFrame(frame: frame, screens: screens, pointer: pointer)
    else {
      return nil
    }
    guard !target.contains(frame) else {
      return nil
    }
    return clampedOrigin(frame: frame, into: target, margin: margin)
  }

  /// A card fully covered by the display union stays where it was dropped,
  /// including across a flush seam. Restore any uncovered edge so the controls
  /// remain reachable after a size change or a drop past the desktop boundary.
  static func droppedOrigin(
    frame: NSRect,
    screens: [NSRect],
    margin: CGFloat,
    pointer: NSPoint? = nil
  ) -> NSPoint? {
    let area = frame.width * frame.height
    if area > 0, coveredArea(frame, by: screens) >= area {
      return nil
    }
    return fittedOrigin(frame: frame, screens: screens, margin: margin, pointer: pointer)
  }

  private static func clampedOrigin(
    frame: NSRect,
    into visibleFrame: NSRect,
    margin: CGFloat
  ) -> NSPoint {
    let minX = visibleFrame.minX + margin
    let maxX = max(minX, visibleFrame.maxX - frame.width - margin)
    let minY = visibleFrame.minY + margin
    let maxY = max(minY, visibleFrame.maxY - frame.height - margin)
    return NSPoint(
      x: min(max(frame.origin.x, minX), maxX),
      y: min(max(frame.origin.y, minY), maxY)
    )
  }

  private static func squaredDistance(from point: NSPoint, to rect: NSRect) -> CGFloat {
    let dx = max(max(rect.minX - point.x, 0), point.x - rect.maxX)
    let dy = max(max(rect.minY - point.y, 0), point.y - rect.maxY)
    return dx * dx + dy * dy
  }
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

  /// Called once after a native drag loop returned and the card was released.
  var onDragFinished: (() -> Void)?

  /// True from the mouse-down until the native drag loop returns. The owner
  /// must not reposition the card while this is set.
  private(set) var isDraggingAcrossScreens = false

  override func cancelOperation(_ sender: Any?) {
    // Escape must not close the panel; closing is a user action on the close
    // button only.
  }

  /// AppKit's default implementation pulls a dragged window back towards the
  /// display the drag started on, which makes a borderless card stick at seams
  /// between displays with different heights, offsets or a gap. The card is a
  /// floating HUD that restores its own visibility at safe moments, so movement
  /// stays free here. Frames are global logical points: nothing is scaled.
  override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
    frameRect
  }

  /// Native AppKit window drag (no synthetic mouse loop, no pixel math),
  /// wrapped so the owner knows the position must not be clamped mid-drag.
  func performAcrossScreenDrag(with event: NSEvent) {
    beginAcrossScreenDrag()
    performDrag(with: event)
    endAcrossScreenDrag()
  }

  /// Drag lifecycle primitives. `performDrag` blocks in its own tracking loop,
  /// so the owner only learns about the end through `onDragFinished`.
  func beginAcrossScreenDrag() {
    isDraggingAcrossScreens = true
  }

  func endAcrossScreenDrag() {
    guard isDraggingAcrossScreens else {
      return
    }
    isDraggingAcrossScreens = false
    onDragFinished?()
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

  /// Fitting size for the card currently applied. The large card keeps its
  /// fixed metrics; the compact card starts at `panelSize` and only grows
  /// enough to keep the live digits and caption unclipped, so ordinary MM:SS
  /// stays narrow while "1440:00" still gets its full width.
  func preferredPanelSize(for size: PomodoroFloatingPanelSize) -> NSSize {
    switch size {
    case .large:
      return size.panelSize
    case .compact:
      let textWidth = max(stableTimeWidth(), stableCaptionWidth())
      let controlsWidth =
        size.horizontalPadding * 2
        + size.timeToToggleSpacing
        + size.toggleButtonSize.width
        + size.toggleToCloseSpacing
        + size.closeButtonSize.width
      return NSSize(
        width: max(size.panelSize.width, ceil(textWidth + controlsWidth)),
        height: size.panelSize.height
      )
    }
  }

  /// Measures a canonical string with the same glyph count as the live value.
  /// Tabular figures give every digit one width, so ticking 24:58 -> 24:57
  /// cannot change the card size; the label's own intrinsic inset is added back
  /// so its drawing offset never clips the digits.
  private func stableTimeWidth() -> CGFloat {
    guard let font = timeLabel.font, !timeLabel.stringValue.isEmpty else {
      return 0
    }
    let value = timeLabel.stringValue
    let canonical = String(value.map { $0.isNumber ? Character("8") : $0 })
    let canonicalWidth = (canonical as NSString)
      .size(withAttributes: [.font: font]).width
    let liveWidth = (value as NSString)
      .size(withAttributes: [.font: font]).width
    let labelInset = max(0, timeLabel.intrinsicContentSize.width - liveWidth)
    return ceil(canonicalWidth + labelInset)
  }

  /// The caption is localized, so its own width can exceed the digits.
  private func stableCaptionWidth() -> CGFloat {
    guard !statusLabel.isHidden, !statusLabel.stringValue.isEmpty else {
      return 0
    }
    return ceil(statusLabel.intrinsicContentSize.width)
  }

  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

  // Dragging the card (including the blank area around the digits) moves the
  // panel; buttons are subviews and keep receiving their own clicks. The drag
  // itself stays native AppKit tracking, wrapped only to learn when it ends.
  override func mouseDown(with event: NSEvent) {
    guard let panel = window as? PomodoroFloatingPanel else {
      window?.performDrag(with: event)
      return
    }
    panel.performAcrossScreenDrag(with: event)
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
  /// snapshot's `windowSize` and its measured labels, keeping the remembered
  /// origin.
  static let panelSize = PomodoroFloatingPanelSize.large.panelSize
  static let frameAutosaveName = "DuoyiPomodoroFloatingPanel"

  weak var delegate: PomodoroFloatingPanelDelegate?

  private var panel: PomodoroFloatingPanel?
  private var state: PomodoroFloatingPanelState?
  private var activityToken: NSObjectProtocol?
  private var screenParametersObserver: NSObjectProtocol?
  private var didRegisterBundledFont = false
  private var cachedFonts: [FontKey: NSFont] = [:]

  /// Global pointer position used when a drag ends. AppKit reports the same
  /// logical points as window frames, so nothing is scaled here. Overridable so
  /// the native smoke test can drop the card at a deterministic point.
  var pointerLocationProvider: () -> NSPoint? = { NSEvent.mouseLocation }

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

  /// Bind a click to the state actually displayed by this native panel.
  var toggleBinding: [String: Any]? {
    guard let state = state, state.canToggle else { return nil }
    return [
      "sessionId": state.controlSessionId,
      "revision": state.controlRevision,
      "state": state.controlState,
    ]
  }

  /// Applies the state first, then shows the panel. Creates the panel on demand
  /// and reuses it after `hide()`.
  @discardableResult
  func show(_ state: PomodoroFloatingPanelState) -> Bool {
    let panel = ensurePanel()
    self.state = state
    updateActivity(isRunning: state.isRunning)
    applyStateToPanel()
    restorePlacement(panel, pointer: nil)
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

    panel.onDragFinished = { [weak self, weak panel] in
      guard let self = self, let panel = panel else {
        return
      }
      self.handleDragFinished(panel)
    }

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
    // Apply the content first: the compact card measures its own labels after
    // the strings and fonts are in place, then the window takes that size.
    contentView.apply(state: state, fonts: fonts(for: state))
    let targetSize = contentView.preferredPanelSize(for: state.windowSize)
    let sizeChanged = panel.frame.size != targetSize
    resize(panel, to: targetSize)
    // A compact card can be flush with the right edge. Growing it (a longer
    // duration or a density switch) must keep the close control reachable,
    // while ordinary updates and theme changes preserve the exact position.
    // During a native drag the user owns the position, so this check waits for
    // the drop instead of pulling the card back.
    if sizeChanged {
      restorePlacement(panel, pointer: nil)
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

  /// Keeps the card reachable on a display that still exists. Called on show,
  /// after a real size change, when the display topology changes and once after
  /// a native drag; ordinary ticks never reach this path.
  ///
  /// `panel.screen` is deliberately not used: it lags the real frame while the
  /// card crosses a seam. The largest frame overlap decides, the display under
  /// the pointer wins at drop time and the nearest display is the last resort
  /// after a display was unplugged.
  private func restorePlacement(
    _ panel: PomodoroFloatingPanel,
    pointer: NSPoint?,
    afterDrop: Bool = false
  ) {
    // AppKit owns the position while the user drags; clamping here would pull
    // the card back towards the display the drag started on. The same check
    // runs once when the drag ends.
    guard !panel.isDraggingAcrossScreens else {
      return
    }
    let screens = NSScreen.screens.map { $0.visibleFrame }
    let origin: NSPoint?
    if afterDrop {
      origin = PomodoroFloatingPanelGeometry.droppedOrigin(
        frame: panel.frame,
        screens: screens,
        margin: Self.screenMargin,
        pointer: pointer
      )
    } else {
      origin = PomodoroFloatingPanelGeometry.fittedOrigin(
        frame: panel.frame,
        screens: screens,
        margin: Self.screenMargin,
        pointer: pointer
      )
    }
    if let origin = origin, origin != panel.frame.origin {
      panel.setFrameOrigin(origin)
    }
  }

  /// The native drag loop returned and the user let the card go.
  private func handleDragFinished(_ panel: PomodoroFloatingPanel) {
    restorePlacement(panel, pointer: pointerLocationProvider(), afterDrop: true)
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
      self.restorePlacement(panel, pointer: nil)
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
