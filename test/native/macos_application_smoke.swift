import AppKit
import CoreGraphics
import Foundation
import Security

/// Native guard used by `scripts/macos_adhoc_package.py check-packages`.
///
/// Compile with the Command Line Tools only (no Xcode project, no CocoaPods):
///
///     xcrun swiftc -O test/native/macos_application_smoke.swift -o <scratch>/macos-smoke
///
/// Modes:
///
///     macos-smoke inspect <app-path>
///     macos-smoke keychain write|read|delete <service>
///
/// `inspect` is read-only: it reports every running application whose bundle
/// URL matches `<app-path>` with its pid, `isFinishedLaunching` and the number
/// of layer-0 windows owned by that pid. Launching, polling and terminating by
/// exact pid stay in the Python wrapper, so the original /Applications copy is
/// never opened by name.
///
/// `keychain` exercises the classic login keychain (`kSecUseDataProtectionKeychain`
/// is false) with a throw-away service name and a fixed dummy account/value.
/// Callers generate a fresh UUID service per run and invoke the three phases in
/// three separate processes, which proves the item survives a process restart.
/// Only a status code and `roundTripMatched` are printed: no real AI
/// configuration, account token or user keychain item is read, overwritten or
/// reset. This is a packaging guard, not a functional regression suite.

enum SmokeError: Error {
  case usage
}

func emit(_ value: [String: Any]) {
  let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
  print(data.flatMap { String(data: $0, encoding: .utf8) } ?? "{}")
}

let keychainAccount = "duoyi-macos-packaging-probe"
let keychainValue = Data("duoyi-macos-packaging-probe-value".utf8)

func keychainQuery(service: String) -> [String: Any] {
  return [
    kSecClass as String: kSecClassGenericPassword,
    kSecAttrService as String: service,
    kSecAttrAccount as String: keychainAccount,
    kSecUseDataProtectionKeychain as String: false,
  ]
}

func runInspect(_ path: String) -> Int32 {
  let target = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
  guard FileManager.default.fileExists(atPath: target) else {
    emit(["error": "application path does not exist", "applications": []])
    return 2
  }
  let windows = CGWindowListCopyWindowInfo([.excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
  let apps = NSWorkspace.shared.runningApplications.filter {
    $0.bundleURL?.resolvingSymlinksInPath().path == target
  }
  let records: [[String: Any]] = apps.map { app in
    let count = windows.filter {
      ($0[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == app.processIdentifier &&
        ($0[kCGWindowLayer as String] as? NSNumber)?.intValue == 0
    }.count
    return [
      "pid": Int(app.processIdentifier),
      "bundleIdentifier": app.bundleIdentifier ?? "",
      "bundlePath": app.bundleURL?.path ?? "",
      "finishedLaunching": app.isFinishedLaunching,
      "terminated": app.isTerminated,
      "windowCount": count,
    ]
  }
  emit(["applications": records])
  return 0
}

func runKeychain(phase: String, service: String) -> Int32 {
  // Never show an authorization sheet during an unattended CI check.
  _ = SecKeychainSetUserInteractionAllowed(false)
  guard !service.isEmpty else {
    emit(["error": "service is required"])
    return 2
  }
  let query = keychainQuery(service: service)
  switch phase {
  case "write":
    var add = query
    add[kSecValueData as String] = keychainValue
    let status = SecItemAdd(add as CFDictionary, nil)
    emit(["phase": phase, "status": Int(status)])
    return 0
  case "read":
    var read = query
    read[kSecReturnData as String] = true
    read[kSecMatchLimit as String] = kSecMatchLimitOne
    var result: CFTypeRef?
    let status = SecItemCopyMatching(read as CFDictionary, &result)
    let matched = (result as? Data) == keychainValue
    emit(["phase": phase, "status": Int(status), "roundTripMatched": matched])
    return 0
  case "delete":
    let status = SecItemDelete(query as CFDictionary)
    emit(["phase": phase, "status": Int(status)])
    return 0
  default:
    emit(["error": "unknown keychain phase"])
    return 2
  }
}

let arguments = CommandLine.arguments
guard arguments.count >= 3 else {
  FileHandle.standardError.write(Data("usage: macos-smoke inspect <app> | keychain write|read|delete <service>\n".utf8))
  exit(2)
}

switch arguments[1] {
case "inspect":
  if arguments.count != 3 {
    exit(2)
  }
  exit(runInspect(arguments[2]))
case "keychain":
  if arguments.count != 4 {
    exit(2)
  }
  exit(runKeychain(phase: arguments[2], service: arguments[3]))
default:
  FileHandle.standardError.write(Data("unknown mode\n".utf8))
  exit(2)
}
