import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private let bookmarkKey = "SkapieRepositoryBookmarks"
  private let writeBookmarkKey = "SkapieWriteScopeBookmarks"
  private var activeRepositories: [String: URL] = [:]
  private var activeWriteScopes: [String: URL] = [:]

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
      case "chooseWriteDirectory":
        self.chooseWriteDirectory(result)
      case "restoreWriteDirectory":
        guard let path = call.arguments as? String else {
          result(false)
          return
        }
        result(self.restoreWriteDirectory(path))
      case "exportPatchProposal":
        guard let args = call.arguments as? [String: String],
              let name = args["name"], let text = args["text"] else {
          result(FlutterError(code: "export_args", message: "Missing proposal", details: nil))
          return
        }
        self.exportPatchProposal(name: name, text: text, result: result)
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
    for url in activeWriteScopes.values {
      url.stopAccessingSecurityScopedResource()
    }
  }

  private func chooseWriteDirectory(_ result: @escaping FlutterResult) {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = false
    panel.canCreateDirectories = false
    panel.prompt = "Grant Write Access"
    guard panel.runModal() == .OK, let url = panel.url else {
      result(nil)
      return
    }
    do {
      let bookmark = try url.bookmarkData(
        options: .withSecurityScope,
        includingResourceValuesForKeys: nil,
        relativeTo: nil
      )
      guard activateWriteScope(url) else {
        result(FlutterError(code: "write_access", message: "Could not access selected folder for writing", details: nil))
        return
      }
      var saved = UserDefaults.standard.dictionary(forKey: writeBookmarkKey) ?? [:]
      saved[url.path] = bookmark
      UserDefaults.standard.set(saved, forKey: writeBookmarkKey)
      result(url.path)
    } catch {
      result(FlutterError(code: "write_bookmark", message: error.localizedDescription, details: nil))
    }
  }

  private func restoreWriteDirectory(_ path: String) -> Bool {
    if activeWriteScopes[path] != nil { return true }
    guard let saved = UserDefaults.standard.dictionary(forKey: writeBookmarkKey),
          let bookmark = saved[path] as? Data else { return false }
    do {
      var stale = false
      let url = try URL(
        resolvingBookmarkData: bookmark,
        options: .withSecurityScope,
        relativeTo: nil,
        bookmarkDataIsStale: &stale
      )
      guard url.path == path, activateWriteScope(url) else { return false }
      if stale {
        let updated = try url.bookmarkData(
          options: .withSecurityScope,
          includingResourceValuesForKeys: nil,
          relativeTo: nil
        )
        var next = saved
        next[path] = updated
        UserDefaults.standard.set(next, forKey: writeBookmarkKey)
      }
      return true
    } catch { return false }
  }

  private func activateWriteScope(_ url: URL) -> Bool {
    if activeWriteScopes[url.path] != nil { return true }
    guard url.startAccessingSecurityScopedResource() else { return false }
    activeWriteScopes[url.path] = url
    return true
  }

  private func exportPatchProposal(name: String, text: String, result: @escaping FlutterResult) {
    let panel = NSSavePanel()
    panel.nameFieldStringValue = URL(fileURLWithPath: name).lastPathComponent
    panel.prompt = "Export Proposal"
    guard panel.runModal() == .OK, let url = panel.url else {
      result(nil)
      return
    }
    do {
      try text.write(to: url, atomically: true, encoding: .utf8)
      result(url.path)
    } catch {
      result(FlutterError(code: "export_failed", message: error.localizedDescription, details: nil))
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
