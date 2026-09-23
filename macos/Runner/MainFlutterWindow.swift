import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private let bookmarkKey = "SkapieRepositoryBookmarks"
  private var activeRepositories: [String: URL] = [:]

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    let repositoryChannel = FlutterMethodChannel(
      name: "skapie/repository",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    repositoryChannel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(FlutterError(code: "window_closed", message: "Window closed", details: nil))
        return
      }
      switch call.method {
      case "chooseDirectory":
        self.chooseRepository(result)
      case "restoreDirectory":
        guard let path = call.arguments as? String else {
          result(false)
          return
        }
        result(self.restoreRepository(path))
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    super.awakeFromNib()
  }

  deinit {
    for url in activeRepositories.values {
      url.stopAccessingSecurityScopedResource()
    }
  }

  private func chooseRepository(_ result: @escaping FlutterResult) {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = false
    panel.canCreateDirectories = false
    panel.prompt = "Use Repository"
    guard panel.runModal() == .OK, let url = panel.url else {
      result(nil)
      return
    }
    do {
      let bookmark = try url.bookmarkData(
        options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
        includingResourceValuesForKeys: nil,
        relativeTo: nil
      )
      var saved = UserDefaults.standard.dictionary(forKey: bookmarkKey) ?? [:]
      saved[url.path] = bookmark
      UserDefaults.standard.set(saved, forKey: bookmarkKey)
      guard activateRepository(url) else {
        result(FlutterError(code: "repository_access", message: "Could not access selected repository", details: nil))
        return
      }
      result(url.path)
    } catch {
      result(FlutterError(code: "repository_bookmark", message: error.localizedDescription, details: nil))
    }
  }

  private func restoreRepository(_ path: String) -> Bool {
    if activeRepositories[path] != nil {
      return true
    }
    guard let saved = UserDefaults.standard.dictionary(forKey: bookmarkKey),
          let bookmark = saved[path] as? Data else {
      return false
    }
    do {
      var stale = false
      let url = try URL(
        resolvingBookmarkData: bookmark,
        options: .withSecurityScope,
        relativeTo: nil,
        bookmarkDataIsStale: &stale
      )
      guard url.path == path, activateRepository(url) else {
        return false
      }
      if stale {
        let updated = try url.bookmarkData(
          options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
          includingResourceValuesForKeys: nil,
          relativeTo: nil
        )
        var next = saved
        next[path] = updated
        UserDefaults.standard.set(next, forKey: bookmarkKey)
      }
      return true
    } catch {
      return false
    }
  }

  private func activateRepository(_ url: URL) -> Bool {
    if activeRepositories[url.path] != nil {
      return true
    }
    guard url.startAccessingSecurityScopedResource() else {
      return false
    }
    activeRepositories[url.path] = url
    return true
  }
}
