import Cocoa
import FlutterMacOS

/// Bridges Dart to the native pomodoro floating panel and the main window theme.
///
/// Channel: `com.duoyi/pomodoro_floating_window`
/// Dart -> native: `update`, `show`, `hide`, `dispose`
/// Native -> Dart: `toggle`, `closed`
final class PomodoroFloatingWindowChannel: NSObject, PomodoroFloatingPanelDelegate {
  static let channelName = "com.duoyi/pomodoro_floating_window"

  private let channel: FlutterMethodChannel
  private let controller: PomodoroFloatingPanelController
  private weak var mainWindow: MainFlutterWindow?

  init(
    messenger: FlutterBinaryMessenger,
    controller: PomodoroFloatingPanelController = .shared,
    mainWindow: MainFlutterWindow? = nil
  ) {
    self.channel = FlutterMethodChannel(name: Self.channelName, binaryMessenger: messenger)
    self.controller = controller
    self.mainWindow = mainWindow
    super.init()
    controller.delegate = self
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(FlutterMethodNotImplemented)
        return
      }
      self.handle(call, result: result)
    }
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "show", "update":
      guard let state = PomodoroFloatingPanelState(arguments: call.arguments as? [String: Any]) else {
        result(
          FlutterError(
            code: "invalid_arguments",
            message: "\(call.method) expects a map containing timeText.",
            details: call.arguments
          )
        )
        return
      }
      // The same snapshot drives both the floating panel and the native titlebar.
      mainWindow?.applyThemeAppearance(state.appearance)
      if call.method == "show" {
        controller.show(state)
      } else {
        controller.update(state)
      }
      result(nil)
    case "hide":
      controller.hide()
      result(nil)
    case "dispose":
      controller.dispose()
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: PomodoroFloatingPanelDelegate

  func pomodoroFloatingPanelDidRequestToggle() {
    channel.invokeMethod("toggle", arguments: nil)
  }

  func pomodoroFloatingPanelDidClose() {
    channel.invokeMethod("closed", arguments: nil)
  }
}

class MainFlutterWindow: NSWindow, NSWindowDelegate {
  private var flutterViewController: FlutterViewController?
  private var pomodoroChannel: PomodoroFloatingWindowChannel?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    self.delegate = self
    self.flutterViewController = flutterViewController
    self.pomodoroChannel = PomodoroFloatingWindowChannel(
      messenger: flutterViewController.engine.binaryMessenger,
      mainWindow: self
    )

    super.awakeFromNib()
    applyThemeAppearance(.semanticFallback)
  }

  /// Applies the Flutter page background and foreground colors to AppKit's
  /// native titlebar while keeping traffic lights and window behavior native.
  func applyThemeAppearance(_ appearance: PomodoroFloatingPanelAppearance) {
    let background = appearance.windowBackgroundColor
    let foreground = appearance.windowForegroundColor
    backgroundColor = background
    titlebarAppearsTransparent = true
    titleVisibility = .visible
    titlebarSeparatorStyle = .none

    let rgb = background.usingColorSpace(.sRGB)
    let luminance = rgb.map {
      0.2126 * $0.redComponent + 0.7152 * $0.greenComponent + 0.0722 * $0.blueComponent
    } ?? 1
    self.appearance = NSAppearance(named: luminance < 0.45 ? .darkAqua : .aqua)

    guard let closeButton = standardWindowButton(.closeButton) else { return }
    var titlebarView: NSView = closeButton
    for _ in 0..<3 {
      guard let parent = titlebarView.superview else { break }
      titlebarView = parent
    }
    titlebarView.wantsLayer = true
    titlebarView.layer?.backgroundColor = background.cgColor
    titlebarView.layer?.borderWidth = 0
    updateTitlebarTextColor(titlebarView, color: foreground)
  }

  private func updateTitlebarTextColor(_ view: NSView, color: NSColor) {
    if let field = view as? NSTextField, field.stringValue == title {
      field.textColor = color
    }
    for child in view.subviews {
      updateTitlebarTextColor(child, color: color)
    }
  }

  /// The red close button hides the window instead of closing it, so the Flutter
  /// engine, the pomodoro timers and the floating panel keep running. Quitting
  /// still happens through Cmd+Q / the app menu.
  func windowShouldClose(_ sender: NSWindow) -> Bool {
    sender.orderOut(nil)
    return false
  }
}
