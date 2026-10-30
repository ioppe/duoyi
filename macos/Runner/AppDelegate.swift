import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  /// The app keeps running without any visible window: the pomodoro countdown
  /// and its floating panel live on after the main window is hidden.
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return false
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  /// Dock icon click (or re-open from Finder) brings the main window back when it
  /// was hidden with the red close button.
  override func applicationShouldHandleReopen(
    _ sender: NSApplication,
    hasVisibleWindows flag: Bool
  ) -> Bool {
    let window = mainFlutterWindow
      ?? sender.windows.first(where: { $0 is MainFlutterWindow })
    if let window = window {
      window.makeKeyAndOrderFront(nil)
      NSApp.activate(ignoringOtherApps: true)
    }
    return true
  }

  /// Cmd+Q terminates normally; release the floating panel and the App Nap
  /// activity before the engine goes away.
  override func applicationWillTerminate(_ notification: Notification) {
    PomodoroFloatingPanelController.shared.dispose()
    super.applicationWillTerminate(notification)
  }
}
