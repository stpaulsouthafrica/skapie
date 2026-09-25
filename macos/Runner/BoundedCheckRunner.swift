import Foundation
import FlutterMacOS
import Darwin

/// The first check is deliberately a fixed Git command. No shell or model text
/// reaches argv. The child starts in its own process group so Cancel and the
/// timeout can signal its ordinary descendants as one unit.
final class BoundedCheckRunner {
  private let lock = NSLock()
  private var busy = false
  private var cancelled = false
  private var activePid: pid_t = 0

  func run(root: String, onChunk: @escaping (String, String, String) -> Void,
           result: @escaping FlutterResult) {
    lock.lock()
    if busy {
      lock.unlock()
      result(FlutterError(code: "check_busy", message: "A check is already running", details: nil))
      return
    }
    busy = true
    cancelled = false
    lock.unlock()

    DispatchQueue.global(qos: .userInitiated).async {
      let report = self.perform(root: root, onChunk: onChunk)
      self.lock.lock()
      self.busy = false
      self.activePid = 0
      self.lock.unlock()
      DispatchQueue.main.async { result(report) }
    }
  }

  func cancel() -> Bool {
    lock.lock()
    let running = busy
    if running { cancelled = true }
    let pid = activePid
    lock.unlock()
    if pid > 0 { _ = kill(-pid, SIGTERM) }
    return running
  }

  private func isCancelled() -> Bool {
    lock.lock()
    defer { lock.unlock() }
    return cancelled
  }

  private func setActive(_ pid: pid_t) {
    lock.lock()
    activePid = pid
    let shouldStop = cancelled
    lock.unlock()
    if shouldStop && pid > 0 { _ = kill(-pid, SIGTERM) }
  }

  private func perform(root: String, onChunk: @escaping (String, String, String) -> Void) -> [String: Any] {
    let started = ISO8601DateFormatter().string(from: Date())
    let git = [
      "/Library/Developer/CommandLineTools/usr/bin/git",
      "/Applications/Xcode.app/Contents/Developer/usr/bin/git"
    ].first { FileManager.default.isExecutableFile(atPath: $0) }
    guard let git else {
      return failure("Install Xcode Command Line Tools to use this check.", root, started)
    }
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: root, isDirectory: &isDirectory),
          isDirectory.boolValue else {
      return failure("The selected write folder is missing.", root, started)
    }

    let statusArgs = ["-c", "core.quotePath=false", "status", "--porcelain=v1", "--untracked-files=normal"]
    let before = runCommand(git, statusArgs, root, seconds: 8, limit: 16_384,
                            phase: "before", onChunk: onChunk)
    if before.cancelled {
      return report("cancelled", git, root, started, before: before)
    }
    if before.timedOut {
      return report("timeout", git, root, started, before: before)
    }
    guard before.error == nil, before.exitCode == 0,
          !before.stopUncertain, !before.truncated else {
      return report("infrastructure_error", git, root, started, before: before)
    }

    let check = runCommand(git, ["diff", "--check"], root, seconds: 30, limit: 32_768,
                           phase: "check", onChunk: onChunk)
    let after: CommandOutput? = check.cancelled || check.stopUncertain
      ? nil : runCommand(git, statusArgs, root, seconds: 8, limit: 16_384,
                         phase: "after", onChunk: onChunk)
    let outcome: String
    if check.cancelled || after?.cancelled == true { outcome = "cancelled" }
    else if check.timedOut || after?.timedOut == true { outcome = "timeout" }
    else if check.error != nil || check.stopUncertain || after?.error != nil ||
              after?.stopUncertain == true || after?.exitCode != 0 {
      outcome = "infrastructure_error"
    }
    else if check.exitCode == 0 { outcome = "exit_0" }
    else { outcome = "nonzero_exit" }
    return report(outcome, git, root, started, before: before, check: check, after: after)
  }

  private func failure(_ message: String, _ root: String, _ started: String) -> [String: Any] {
    return [
      "outcome": "infrastructure_error", "error": message, "cwd": root,
      "startedAt": started, "finishedAt": ISO8601DateFormatter().string(from: Date()),
      "environmentKeys": ["PATH", "LANG", "LC_ALL", "HOME", "GIT_CONFIG_NOSYSTEM", "GIT_CONFIG_GLOBAL", "GIT_OPTIONAL_LOCKS", "GIT_TERMINAL_PROMPT"],
      "truncated": false, "gitStateKnown": false, "stopUncertain": false,
      "network": "allowed_by_app_sandbox", "argv": ["git", "diff", "--check"]
    ]
  }

  private func report(
    _ outcome: String, _ git: String, _ root: String, _ started: String,
    before: CommandOutput, check: CommandOutput? = nil, after: CommandOutput? = nil
  ) -> [String: Any] {
    let actual = check ?? before
    return [
      "outcome": outcome,
      "argv": [git, "diff", "--check"],
      "cwd": root,
      "environmentKeys": ["PATH", "LANG", "LC_ALL", "HOME", "GIT_CONFIG_NOSYSTEM", "GIT_CONFIG_GLOBAL", "GIT_OPTIONAL_LOCKS", "GIT_TERMINAL_PROMPT"],
      "network": "allowed_by_app_sandbox",
      "startedAt": started,
      "finishedAt": ISO8601DateFormatter().string(from: Date()),
      "exitCode": actual.exitCode as Any,
      "stdout": actual.stdout,
      "stderr": actual.stderr,
      "truncated": before.truncated || actual.truncated || (after?.truncated ?? false),
      "beforeGit": before.stdout,
      "afterGit": after?.stdout ?? "",
      "gitStateKnown": !before.truncated && after?.exitCode == 0 &&
        after?.error == nil && after?.truncated == false &&
        after?.stopUncertain == false,
      "error": actual.error ?? after?.error ?? (check == nil ? before.stderr : ""),
      "stopUncertain": actual.stopUncertain || (after?.stopUncertain ?? false)
    ]
  }

  private struct CommandOutput {
    var exitCode: Int32 = -1
    var stdout = ""
    var stderr = ""
    var error: String? = nil
    var truncated = false
    var timedOut = false
    var cancelled = false
    var stopUncertain = false
  }

  private func runCommand(
    _ executable: String, _ arguments: [String], _ root: String,
    seconds: TimeInterval, limit: Int, phase: String,
    onChunk: @escaping (String, String, String) -> Void
  ) -> CommandOutput {
    var output = CommandOutput()
    if isCancelled() { output.cancelled = true; return output }
    var outPipe: [Int32] = [0, 0]
    var errPipe: [Int32] = [0, 0]
    guard pipe(&outPipe) == 0 else {
      output.error = "Could not open stdout pipe: \(errno)"
      return output
    }
    guard pipe(&errPipe) == 0 else {
      close(outPipe[0]); close(outPipe[1])
      output.error = "Could not open stderr pipe: \(errno)"
      return output
    }
    var actions: posix_spawn_file_actions_t? = nil
    var attributes: posix_spawnattr_t? = nil
    posix_spawn_file_actions_init(&actions)
    posix_spawnattr_init(&attributes)
    defer {
      posix_spawn_file_actions_destroy(&actions)
      posix_spawnattr_destroy(&attributes)
    }
    posix_spawn_file_actions_adddup2(&actions, outPipe[1], STDOUT_FILENO)
    posix_spawn_file_actions_adddup2(&actions, errPipe[1], STDERR_FILENO)
    posix_spawn_file_actions_addclose(&actions, outPipe[0])
    posix_spawn_file_actions_addclose(&actions, errPipe[0])
    let chdirStatus = root.withCString { posix_spawn_file_actions_addchdir_np(&actions, $0) }
    posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP))
    posix_spawnattr_setpgroup(&attributes, 0)
    if chdirStatus != 0 {
      close(outPipe[0]); close(outPipe[1]); close(errPipe[0]); close(errPipe[1])
      output.error = "Could not set working folder: \(chdirStatus)"
      return output
    }

    let environment = [
      "PATH=/usr/bin:/bin", "LANG=C", "LC_ALL=C", "HOME=/var/empty",
      "GIT_CONFIG_NOSYSTEM=1", "GIT_CONFIG_GLOBAL=/dev/null",
      "GIT_OPTIONAL_LOCKS=0", "GIT_TERMINAL_PROMPT=0"
    ]
    let argPointers: [UnsafeMutablePointer<CChar>?] = ([executable] + arguments).map { strdup($0) } + [nil]
    let envPointers: [UnsafeMutablePointer<CChar>?] = environment.map { strdup($0) } + [nil]
    defer {
      for pointer in argPointers where pointer != nil { free(pointer) }
      for pointer in envPointers where pointer != nil { free(pointer) }
    }
    var argv = argPointers
    var envp = envPointers
    var pid: pid_t = 0
    let spawnStatus = executable.withCString { command in
      argv.withUnsafeMutableBufferPointer { args in
        envp.withUnsafeMutableBufferPointer { env in
          posix_spawn(&pid, command, &actions, &attributes, args.baseAddress, env.baseAddress)
        }
      }
    }
    close(outPipe[1]); close(errPipe[1])
    if spawnStatus != 0 {
      close(outPipe[0]); close(errPipe[0])
      output.error = "Could not start installed Git: \(spawnStatus)"
      return output
    }
    setActive(pid)
    _ = fcntl(outPipe[0], F_SETFL, O_NONBLOCK)
    _ = fcntl(errPipe[0], F_SETFL, O_NONBLOCK)
    var stdout = Data()
    var stderr = Data()
    var stdoutClosed = false
    var stderrClosed = false
    var status: Int32 = 0
    var reaped = false
    var reapedAt: Date? = nil
    var signalAt: Date? = nil
    let deadline = Date().addingTimeInterval(seconds)
    while true {
      stdoutClosed = drain(outPipe[0], into: &stdout, limit: limit, truncated: &output.truncated,
                           phase: phase, stream: "stdout", onChunk: onChunk) || stdoutClosed
      stderrClosed = drain(errPipe[0], into: &stderr, limit: limit, truncated: &output.truncated,
                           phase: phase, stream: "stderr", onChunk: onChunk) || stderrClosed
      if !reaped {
        let waited = waitpid(pid, &status, WNOHANG)
        if waited == pid { reaped = true; reapedAt = Date() }
        else if waited == -1 { output.error = "Could not observe child exit: \(errno)"; reaped = true; reapedAt = Date() }
      }
      if signalAt == nil {
        if isCancelled() {
          output.cancelled = true
          signalAt = Date()
          _ = kill(-pid, SIGTERM)
        } else if Date() >= deadline {
          output.timedOut = true
          signalAt = Date()
          _ = kill(-pid, SIGTERM)
        }
      } else if !reaped && Date().timeIntervalSince(signalAt!) > 0.5 {
        _ = kill(-pid, SIGKILL)
      }
      if reaped && stdoutClosed && stderrClosed { break }
      if let reapedAt, Date().timeIntervalSince(reapedAt) > 1.0 {
        output.stopUncertain = !stdoutClosed || !stderrClosed
        _ = kill(-pid, SIGKILL)
        break
      }
      if signalAt != nil && !reaped && Date().timeIntervalSince(signalAt!) > 2.0 {
        output.stopUncertain = true
        break
      }
      usleep(20_000)
    }
    close(outPipe[0]); close(errPipe[0])
    setActive(0)
    if !reaped { output.stopUncertain = true }
    if reaped && output.error == nil {
      let terminationSignal = status & 0x7f
      output.exitCode = terminationSignal == 0 ? (status >> 8) & 0xff : 128 + terminationSignal
    }
    output.stdout = String(decoding: stdout, as: UTF8.self)
    output.stderr = String(decoding: stderr, as: UTF8.self)
    return output
  }

  private func drain(_ fd: Int32, into data: inout Data, limit: Int, truncated: inout Bool,
                     phase: String, stream: String,
                     onChunk: @escaping (String, String, String) -> Void) -> Bool {
    var bytes = [UInt8](repeating: 0, count: 4096)
    while true {
      let count = bytes.withUnsafeMutableBytes { read(fd, $0.baseAddress, $0.count) }
      if count > 0 {
        let remaining = max(0, limit - data.count)
        if remaining > 0 {
          let accepted = Data(bytes.prefix(min(count, remaining)))
          data.append(accepted)
          onChunk(phase, stream, String(decoding: accepted, as: UTF8.self))
        }
        if count > remaining { truncated = true }
        continue
      }
      if count == 0 { return true }
      if errno == EAGAIN || errno == EINTR { return false }
      return true
    }
  }
}
