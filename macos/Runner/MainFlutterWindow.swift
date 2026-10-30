import Cocoa
import FlutterMacOS

/// Bridges Dart to the native pomodoro floating panel.
///
/// Channel: `com.duoyi/pomodoro_floating_window`
/// Dart -> native: `update`, `show`, `hide`, `dispose`
/// Native -> Dart: `toggle` (user pressed play/pause), `closed` (user dismissed
/// the panel with its own close button)
///
/// Every method answers with success unless the arguments are malformed;
/// unknown methods answer `FlutterMethodNotImplemented`.
final class PomodoroFloatingWindowChannel: NSObject, PomodoroFloatingPanelDelegate {
  static let channelName = "com.duoyi/pomodoro_floating_window"

  private let channel: FlutterMethodChannel
  private let controller: PomodoroFloatingPanelController

  init(messenger: FlutterBinaryMessenger, controller: PomodoroFloatingPanelController = .shared) {
    self.channel = FlutterMethodChannel(name: Self.channelName, binaryMessenger: messenger)
    self.controller = controller
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
      messenger: flutterViewController.engine.binaryMessenger
    )

    super.awakeFromNib()
  }

  /// The red close button hides the window instead of closing it, so the Flutter
  /// engine, the pomodoro timers and the floating panel keep running. Quitting
  /// still happens through Cmd+Q / the app menu.
  func windowShouldClose(_ sender: NSWindow) -> Bool {
    sender.orderOut(nil)
    return false
  }
}
