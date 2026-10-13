import Cocoa
import AVFoundation
import FlutterMacOS
import WebKit

// P2-r10: 攔截 OpenWhisper 的合成 Cmd+V 事件
// OpenWhisper 用 postEvent:atStart: 模擬 Cmd+V
// Flutter 的 FlutterViewController 攔截了事件但沒觸發 paste:
// 自訂 FlutterViewController 子類，覆寫 keyDown 來手動處理
class BridgeFlutterViewController: FlutterViewController {
  // P2-r10: OpenWhisper 語音輸入修正
  // OpenWhisper 用 postEvent 模擬 Cmd+V，FlutterTextInputPlugin.paste: 雖然回應
  // responds(to:) 但沒有正確讀取 pasteboard 插入文字。
  // 解法：攔截 Cmd+V，直接讀 NSPasteboard + NSTextInputClient.insertText:
  override func keyDown(with event: NSEvent) {
    let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    if mods.contains(.command) && event.keyCode == 9 {
      if let text = NSPasteboard.general.string(forType: .string), !text.isEmpty,
         let client = self.view.window?.firstResponder as? NSTextInputClient {
        client.insertText(text, replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
        return
      }
    }
    super.keyDown(with: event)
  }

  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    if mods.contains(.command) && event.keyCode == 9 {
      if let text = NSPasteboard.general.string(forType: .string), !text.isEmpty,
         let client = self.view.window?.firstResponder as? NSTextInputClient {
        client.insertText(text, replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
        return true
      }
    }
    return super.performKeyEquivalent(with: event)
  }
}

class MainFlutterWindow: NSWindow {

  override func awakeFromNib() {
    // [v219b 小葵 2026-09-02 Blue 抓包] 禁用 App Nap——
    // Agent 是背景工作引擎：使用者切頁/螢保啟動時 App 失去前台，
    // macOS App Nap 會節流 timer 與網路 → agent 任務跑到一半被凍。
    _ = ProcessInfo.processInfo.beginActivity(
      options: [.userInitiated, .idleSystemSleepDisabled],
      reason: "bridge_agent_loop_background_work")
    let flutterViewController = BridgeFlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)
    // [小葵 2026-08-14] 最小寬度 1280
    // 頂部：Logo + 6 tab + 深色/懸浮窗/API 按鈕，1080 仍不夠
    self.minSize = NSSize(width: 1280, height: 720)

    RegisterGeneratedPlugins(registry: flutterViewController)
    registerDesktopShellChannel(flutterViewController: flutterViewController)

    // [小葵 2026-07-21] App 啟動時自動清理舊暫存
    cleanupOldTemporaryFiles()

    // B4: screen capture MethodChannel
    let screenChannel = FlutterMethodChannel(
      name: "bridge.screen_capture.macos.v1",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    screenChannel.setMethodCallHandler { call, result in
      switch call.method {
      case "captureWindow":
        ScreenCaptureNative.captureWindow(call: call, result: result)
      case "captureScreen": // [開光 v0.4.x] OS 全螢幕視網膜
        ScreenCaptureNative.captureScreen(result: result)
      case "listWindows":
        ScreenCaptureNative.listWindows(result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    // [小葵 2026-09-05 橋樑 Computer Use Phase 0] 安全機制 + AX 樹 + CGEvent 注入
    // spec: docs/specs/2026-09-05-bridge-computer-use.md
    ComputerUseNative.register(with: flutterViewController)
    // [刀 5 延伸 SR.1] 全電腦示範錄製——事件串流 + start/stop
    SystemRoutineNative.register(with: flutterViewController)

    super.awakeFromNib()
  }

  private var lastDesktopShellCommandResults: [[String: Any]] = []
  private let desktopCompanionPanel = DesktopCompanionPanelController()
  private var localRuntimeProcess: Process?
  private var localRuntimeDownloadProcess: Process?
  private var localModelDownloadProcess: Process?
  // [小葵 2026-07-21] URLSession 下載取代 curl（沙盒內 curl 會寫入 orphan inode）
  private var localModelDownloadTask: URLSessionDownloadTask?
  private var localModelDownloadSession: URLSession?
  private var localModelDownloadDelegate: LocalModelDownloadDelegate?
  private var localModelDownloadTaskPath: String?
  private var localModelDownloadPartialPath: String?
  private var localModelDownloadExpectedPath: String?
  // [小葵 2026-07-21] 記憶體監控 + 自動降級
  private var memoryMonitorTimer: Timer?
  private var memoryGuardLevel: String = "green" // green / yellow / red / critical
  private var desktopShellState: [String: Any] = [
    "visible": true,
    "paused": false,
    "transparent": true,
    "frameless": true,
    "alwaysOnTop": false,
    "draggable": true,
    "trayEnabled": false,
    "launchAtLogin": false,
    "width": 228.0,
    "height": 286.0,
    "commandCount": 0,
    "lastAction": "none",
    "runtimeSynced": false,
    "companionName": "Bridge Companion",
    "companionRole": "橋樑代理人",
    "statusText": "自由待機",
  ]
  private var localRuntimeState: [String: Any] = [
    "phase": "notInstalled",
    "title": "Bridge Local Runtime",
    "detail": "Bridge Desktop 尚未安裝內建推論引擎。",
    "primaryCommand": "prepareRuntime",
    "primaryActionLabel": "準備下載本地引擎",
    "primaryActionEnabled": true,
  ]

  private func registerDesktopShellChannel(flutterViewController: FlutterViewController) {
    let channel = FlutterMethodChannel(
      name: "bridge.desktop_shell.macos.v1",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )

    channel.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      // [小葵 2026-09-01 v183 星系螢保] 閒置 N 分鐘 → 全螢幕即時星系（?saver=1
      // 純淨模式+30 秒重抓 galaxy_data——大腦長新東西螢幕就長新星）；活動即退。
      case "setGalaxySaver":
        DispatchQueue.main.async {
          let args = call.arguments as? [String: Any]
          let enabled = args?["enabled"] as? Bool ?? false
          let idleMinutes = args?["idleMinutes"] as? Int ?? 5
          let url = args?["url"] as? String
          GalaxySaverController.shared.configure(enabled: enabled,
                                                 idleMinutes: idleMinutes,
                                                 urlString: url)
          result(["ok": true])
        }
      // [小葵 2026-08-31 v180 星系獨立視窗] WebKit 對「非視窗主人」webview
      // 深度節流（鐵證：同頁面 Safari 獨立視窗 3.5 分鐘 0 凍結 vs App 內 7/11 凍結）。
      // 解法 A：獨立 NSWindow + 獨立 WKWebView（頁面=視窗主人=絲滑保證）。
      case "openGalaxyWindow":
        DispatchQueue.main.async {
          let url = (call.arguments as? [String: Any])?["url"] as? String
          GalaxyWindowController.shared.open(urlString: url)
          result(["ok": true])
        }
      case "resetGalaxyWindow":
        DispatchQueue.main.async {
          let lvl = (call.arguments as? [String: Any])?["level"] as? Int ?? 1
          GalaxyWindowController.shared.resetWebview(level: lvl)
          result(["ok": true])
        }
      case "closeGalaxyWindow":
        DispatchQueue.main.async {
          GalaxyWindowController.shared.close()
          result(["ok": true])
        }
      case "inspect":
        result([
          "connected": true,
          "platform": "macos",
          "message": "macOS AppKit shell channel ready; native panel available",
          "lastCommandCount": self?.lastDesktopShellCommandResults.count ?? 0,
          "nativePanelAvailable": true,
        ])
      case "applyCommands":
        let payload = call.arguments as? [String: Any]
        let commands = payload?["commands"] as? [[String: Any]] ?? []
        let commandResults = commands.map { self?.previewResult(for: $0) ?? [:] }
        self?.lastDesktopShellCommandResults = commandResults
        result(commandResults)
      case "lastResults":
        result(self?.lastDesktopShellCommandResults ?? [])
      case "snapshot":
        result(self?.snapshotState() ?? [:])
      case "syncRuntime":
        let payload = call.arguments as? [String: Any] ?? [:]
        self?.syncRuntime(payload: payload)
        result(self?.snapshotState() ?? [:])
      case "lifecycle":
        let payload = call.arguments as? [String: Any]
        let action = payload?["action"] as? String ?? "unknown"
        self?.applyLifecycle(action: action)
        result(self?.snapshotState() ?? [:])
      case "hardwareProfile":
        result(self?.hardwareProfile() ?? [:])
      case "memoryGuardStatus":
        result(self?.memoryGuardStatus() ?? [:])
      case "startMemoryMonitor":
        self?.startMemoryMonitor()
        result(self?.memoryGuardStatus() ?? [:])
      case "stopMemoryMonitor":
        self?.stopMemoryMonitor()
        result(true)
      case "listTopMemoryProcesses":
        result(self?.listTopMemoryProcesses() ?? [:])
      case "killProcess":
        let pid = call.arguments as? Int
        if let pid = pid {
          self?.killProcessByPid(Int32(pid))
          result(true)
        } else {
          result(false)
        }
      case "killLocalModel":
        self?.killLocalModelServer()
        result(true)
      case "localRuntime":
        let payload = call.arguments as? [String: Any] ?? [:]
        result(self?.applyLocalRuntime(actionPayload: payload) ?? [:])
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func previewResult(for command: [String: Any]) -> [String: Any] {
    let id = command["id"] as? String ?? "unknown"
    let action = nativeActionName(for: id)
    applyState(command: command, action: action)
    return [
      "id": id,
      "action": action,
      "status": "accepted",
      "channel": "bridge.desktop_shell.macos.v1",
      "message": "Command mapped to \(action)",
    ]
  }

  private func applyState(command: [String: Any], action: String) {
    let payload = command["payload"] as? [String: Any] ?? [:]
    switch action {
    case "configureTransparentWindow":
      if let transparent = payload["transparent"] as? Bool {
        desktopShellState["transparent"] = transparent
      }
      if let frameless = payload["frameless"] as? Bool {
        desktopShellState["frameless"] = frameless
      }
      if let width = payload["width"] as? Double {
        desktopShellState["width"] = width
      } else if let width = payload["width"] as? Int {
        desktopShellState["width"] = Double(width)
      }
      if let height = payload["height"] as? Double {
        desktopShellState["height"] = height
      } else if let height = payload["height"] as? Int {
        desktopShellState["height"] = Double(height)
      }
    case "configureDragAnchor":
      if let draggable = payload["draggable"] as? Bool {
        desktopShellState["draggable"] = draggable
      }
    case "configureAlwaysOnTop":
      if let alwaysOnTop = payload["alwaysOnTop"] as? Bool {
        desktopShellState["alwaysOnTop"] = alwaysOnTop
      }
    case "installStatusItem":
      if let trayEnabled = payload["enabled"] as? Bool {
        desktopShellState["trayEnabled"] = trayEnabled
      }
    case "configureLoginItem":
      if let launchAtLogin = payload["launchAtLogin"] as? Bool {
        desktopShellState["launchAtLogin"] = launchAtLogin
      }
    default:
      break
    }
    desktopShellState["commandCount"] = lastDesktopShellCommandResults.count + 1
    desktopShellState["lastAction"] = action
    desktopCompanionPanel.apply(state: desktopShellState)
  }

  private func applyLifecycle(action: String) {
    switch action {
    case "show":
      desktopShellState["visible"] = true
      desktopShellState["lastAction"] = "showWindow"
      desktopCompanionPanel.show(state: desktopShellState)
    case "hide":
      desktopShellState["visible"] = false
      desktopShellState["lastAction"] = "hideWindow"
      desktopCompanionPanel.hide()
    case "pause":
      desktopShellState["paused"] = true
      desktopShellState["lastAction"] = "pauseCompanion"
      desktopCompanionPanel.pause(state: desktopShellState)
    case "resume":
      desktopShellState["paused"] = false
      desktopShellState["visible"] = true
      desktopShellState["lastAction"] = "resumeCompanion"
      desktopCompanionPanel.resume(state: desktopShellState)
    default:
      desktopShellState["lastAction"] = "unknownLifecycle"
    }
    let currentCount = desktopShellState["commandCount"] as? Int ?? 0
    desktopShellState["commandCount"] = currentCount + 1
  }

  private func snapshotState() -> [String: Any] {
    return desktopCompanionPanel.snapshot(base: desktopShellState)
  }

  private func hardwareProfile() -> [String: Any] {
    let ramGb = Int((Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824.0).rounded())
    let processorCount = ProcessInfo.processInfo.processorCount
    let activeProcessorCount = ProcessInfo.processInfo.activeProcessorCount
    return [
      "source": "macos-method-channel",
      "ramGb": ramGb,
      "chipLabel": "macOS · \(processorCount)c / \(ramGb)GB RAM",
      "desktopConnected": true,
      "processorCount": processorCount,
      "activeProcessorCount": activeProcessorCount,
    ]
  }

  // ═══════════════════════════════════════════════════════════════
  // [小葵 2026-07-21] 記憶體監控 + 自動降級
  // ═══════════════════════════════════════════════════════════════

  /// 啟動記憶體監控（每 5 秒檢查一次）
  func startMemoryMonitor() {
    memoryMonitorTimer?.invalidate()
    memoryMonitorTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
      self?.checkMemoryPressure()
    }
    // 立即檢查一次
    checkMemoryPressure()
  }

  /// 停止記憶體監控
  func stopMemoryMonitor() {
    memoryMonitorTimer?.invalidate()
    memoryMonitorTimer = nil
  }

  /// 取得當前記憶體使用率（0.0 ~ 1.0）
  private func memoryUsageRatio() -> Double {
    // 用 vm_statistics64 取得全系統記憶體統計
    var hostInfo = vm_statistics64_data_t()
    var hostCount = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
    let herr = withUnsafeMutablePointer(to: &hostInfo) {
      $0.withMemoryRebound(to: integer_t.self, capacity: Int(hostCount)) {
        host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &hostCount)
      }
    }
    if herr != KERN_SUCCESS {
      // fallback: 用 App 進程的 resident_size
      var taskInfo = mach_task_basic_info()
      var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<integer_t>.size)
      let kerr = withUnsafeMutablePointer(to: &taskInfo) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
          task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
        }
      }
      if kerr != KERN_SUCCESS { return 0 }
      let totalBytes = Double(ProcessInfo.processInfo.physicalMemory)
      return min(Double(taskInfo.resident_size) / max(totalBytes, 1.0), 1.0)
    }

    let activePages = Double(hostInfo.active_count)
    let inactivePages = Double(hostInfo.inactive_count)
    let wiredPages = Double(hostInfo.wire_count)
    let compressedPages = Double(hostInfo.compressor_page_count)
    let freePages = Double(hostInfo.free_count)

    let usedPages = activePages + wiredPages + compressedPages
    let totalVmPages = usedPages + inactivePages + freePages

    return min(usedPages / max(totalVmPages, 1.0), 1.0)
  }

  /// 記憶體壓力檢查 + 自動降級
  private func checkMemoryPressure() {
    let ratio = memoryUsageRatio()
    let pct = Int(ratio * 100)

    var newLevel: String
    if ratio >= 0.95 {
      newLevel = "critical"
    } else if ratio >= 0.85 {
      newLevel = "red"
    } else if ratio >= 0.70 {
      newLevel = "yellow"
    } else {
      newLevel = "green"
    }

    if newLevel == memoryGuardLevel { return } // 沒變化不做事

    let oldLevel = memoryGuardLevel
    memoryGuardLevel = newLevel
    print("[MemoryGuard] \(oldLevel) → \(newLevel) (\(pct)% RAM)")

    switch newLevel {
    case "yellow":
      // 黃燈：記錄到 state，讓 Dart 端知道
      localRuntimeState["memoryGuard"] = "yellow"
      persistLocalRuntimeState()
    case "red":
      // [小葵 2026-07-22] #4: 紅燈不再自動殺 llama-server
      // 改由 Dart 端偵測紅燈 → 彈 L2 對話框讓使用者選要關什麼
      // 本地模型關閉選項放在彈窗裡（Blue 指示：大部分關掉本地模型就夠了）
      localRuntimeState["memoryGuard"] = "red"
      persistLocalRuntimeState()
    case "critical":
      // 危險：強制釋放
      print("[MemoryGuard] 危險等級！強制釋放所有非核心進程")
      if localRuntimeProcess?.isRunning == true {
        localRuntimeProcess?.terminate()
        localRuntimeProcess = nil
      }
      localRuntimeState["phase"] = "installed"
      localRuntimeState["detail"] = "記憶體嚴重不足，本地模型已緊急停止。"
      localRuntimeState["primaryCommand"] = "startServer"
      localRuntimeState["primaryActionLabel"] = "啟動本地 server"
      localRuntimeState["primaryActionEnabled"] = true
      localRuntimeState["memoryGuard"] = "critical"
      persistLocalRuntimeState()
    case "green":
      // 恢復正常
      localRuntimeState["memoryGuard"] = "green"
      persistLocalRuntimeState()
    default:
      break
    }
  }

  /// 取得記憶體監控狀態（給 Dart 端查詢用）
  func memoryGuardStatus() -> [String: Any] {
    let ratio = memoryUsageRatio()
    return [
      "level": memoryGuardLevel,
      "usagePercent": Int(ratio * 100),
      "localServerRunning": localRuntimeProcess?.isRunning == true,
    ]
  }

  // ═══════════════════════════════════════════════════════════════
  // [小葵 2026-07-22] #4 L2: 系統程序記憶體列表 + 殺程序
  // ═══════════════════════════════════════════════════════════════

  /// 列出記憶體佔用最高的前 15 個使用者程序（排除系統核心程序）
  /// 回傳 { processes: [{pid, name, ramMB, ramPercent}], totalRAMMB }
  /// 用 `ps` 指令實作（避免 libproc.h header 在 Swift explicit module 模式下不可用）
  func listTopMemoryProcesses() -> [String: Any] {
    let totalRAM = ProcessInfo.processInfo.physicalMemory
    let totalRAMMB = Int(totalRAM / (1024 * 1024))

    // 用 ps 取得所有程序的 PID + RSS + 名稱
    // -ax: 所有程序, -o pid,rss,comm: 自訂輸出格式
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/ps")
    process.arguments = ["-ax", "-o", "pid=,rss=,comm="]

    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe

    do {
      try process.run()
      process.waitUntilExit()
    } catch {
      return ["processes": [], "totalRAMMB": totalRAMMB]
    }

    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    let output = String(data: data, encoding: .utf8) ?? ""

    var processData: [(pid: Int32, name: String, rss: Int64)] = []

    let systemNames: Set<String> = [
      "kernel_task", "launchd", "WindowServer",
      "coreaudiod", "logd", "UserEventAgent", "syslogd",
      "configd", "distnoted", "bluetoothd", "thermalmonitord",
      "trustd", "cfprefsd", "cfprefsd", "lsd",
    ]

    for line in output.split(separator: "\n") {
      let parts = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
      guard parts.count >= 3 else { continue }
      guard let pid = Int32(parts[0]) else { continue }
      guard let rssKB = Int64(parts[1]) else { continue }
      let comm = String(parts[2])
      let name = (comm as NSString).lastPathComponent

      // 跳過自己 + 系統核心程序
      if pid == getpid() { continue }
      if systemNames.contains(name) { continue }
      // RSS < 1MB 的不值得列出
      if rssKB < 1024 { continue }

      processData.append((pid: pid, name: name, rss: rssKB * 1024))
    }

    // 按 RSS 排序，取前 15
    processData.sort { $0.rss > $1.rss }

    var results: [[String: Any]] = []
    for item in processData.prefix(15) {
      let rssMB = Double(item.rss) / (1024.0 * 1024.0)
      let pct = Double(item.rss) / Double(totalRAM) * 100.0
      results.append([
        "pid": Int(item.pid),
        "name": item.name,
        "ramMB": Int(rssMB),
        "ramPercent": (pct * 10).rounded() / 10.0,
      ])
    }

    return [
      "processes": results,
      "totalRAMMB": totalRAMMB,
    ]
  }

  /// 殺掉指定 PID 的程序
  func killProcessByPid(_ pid: Int32) {
    print("[MemoryGuard] L2: 殺掉程序 PID=\(pid)")
    kill(pid, SIGTERM)
  }

  /// 殺掉本地模型 server（llama-server）
  func killLocalModelServer() {
    print("[MemoryGuard] L2: 使用者選擇關閉本地模型")
    if localRuntimeProcess?.isRunning == true {
      localRuntimeProcess?.terminate()
      localRuntimeProcess = nil
      localRuntimeState["phase"] = "installed"
      localRuntimeState["detail"] = "使用者已關閉本地模型以釋放記憶體。"
      localRuntimeState["primaryCommand"] = "startServer"
      localRuntimeState["primaryActionLabel"] = "啟動本地 server"
      localRuntimeState["primaryActionEnabled"] = true
      localRuntimeState["memoryGuard"] = "green"
      persistLocalRuntimeState()
    }
  }

  private func applyLocalRuntime(actionPayload: [String: Any]) -> [String: Any] {
    let action = actionPayload["action"] as? String ?? "status"
    if action == "status" {
      restoreLocalRuntimeState()
      advanceLocalRuntimeDownloadIfNeeded()
      // [小葵 2026-10-01] 真相自癒：status 輪詢時把 title 拉回 activeModelName——
      // 下載/舊版殘留的 title（如已退位模型名）活不過一個 poll 週期。
      // Blue 抓包：12B 已登基但卡上大字殘留 E4B，就是 title 無人更正。
      if (localRuntimeState["phase"] as? String) == "running",
         let activeName = localRuntimeState["activeModelName"] as? String,
         !activeName.isEmpty,
         (localRuntimeState["title"] as? String) != activeName {
        localRuntimeState["title"] = activeName
        persistLocalRuntimeState()
      }
    }
    switch action {
    case "prepareRuntime":
      let runtimePath = prepareLocalRuntimeStorage()
      localRuntimeState["runtimePath"] = runtimePath
      localRuntimeState["expectedRuntimeExecutablePath"] = expectedRuntimeExecutablePath()
      // [小葵 2026-07-20] 移除 quarantine，確保 isExecutableFile() 正確回傳
      if let root = localRuntimeRootDirectory() {
        removeQuarantineFromBin(binRoot: root.appendingPathComponent("runtime/bin"))
      }
      if FileManager.default.isExecutableFile(atPath: expectedRuntimeExecutablePath()) {
        // [小葵 2026-07-20] 引擎已安裝，檢查是否有更新版
        let installedVersion = readInstalledRuntimeVersion()
        let latestRelease = fetchLatestLlamaCppRelease()
        if let latest = latestRelease,
           let installed = installedVersion,
           latest.tag != installed {
          // 有新版本，自動更新
          localRuntimeState["phase"] = "downloading"
          localRuntimeState["detail"] = "發現新版本 \(latest.tag)（目前 \(installed)），正在更新推論引擎..."
          localRuntimeState["primaryCommand"] = "status"
          localRuntimeState["primaryActionLabel"] = "更新引擎中"
          localRuntimeState["primaryActionEnabled"] = false
          localRuntimeState["downloadKind"] = "runtime"
          startLocalRuntimeDownload()
        } else {
          // 已是最新版
          localRuntimeState["phase"] = "installed"
          localRuntimeState["detail"] = "Bridge Local Runtime 已準備好（\(installedVersion ?? "未知版本")）；可以下載建議模型。"
          localRuntimeState["primaryCommand"] = "downloadModel"
          localRuntimeState["primaryActionLabel"] = "下載推薦模型"
          localRuntimeState["primaryActionEnabled"] = true
          localRuntimeState["runtimeExecutablePath"] = expectedRuntimeExecutablePath()
          localRuntimeState["runtimeVersion"] = installedVersion ?? "unknown"
          localRuntimeState.removeValue(forKey: "downloadKind")
          localRuntimeState.removeValue(forKey: "progress")
        }
      } else {
        startLocalRuntimeDownload()
      }
      desktopShellState["lastAction"] = "prepareLocalRuntime"
    case "downloadModel":
      let model = actionPayload["model"] as? [String: Any] ?? [:]
      let modelName = model["name"] as? String ?? "推薦模型"
      let downloadSize = model["downloadSize"] as? String ?? "未知大小"
      let sourceManifest = model["sourceManifest"] as? [String: Any] ?? [:]
      let sourceLabel = sourceManifest["sourceLabel"] as? String ?? "模型來源"
      let task = createLocalModelDownloadTask(model: model, fit: actionPayload["fit"] as? String, reason: actionPayload["reason"] as? String)
      localRuntimeState["phase"] = "downloading"
      localRuntimeState["detail"] = "\(modelName) 下載任務已建立（\(downloadSize)，\(sourceLabel)）；Bridge Desktop 正在準備模型檔案。"
      localRuntimeState["primaryCommand"] = "status"
      localRuntimeState["primaryActionLabel"] = "下載中"
      localRuntimeState["primaryActionEnabled"] = false
      localRuntimeState["progress"] = task["progress"] ?? 0.12
      localRuntimeState["taskId"] = task["id"]
      localRuntimeState["taskPath"] = task["taskPath"]
      localRuntimeState["modelId"] = task["modelId"]
      localRuntimeState["runtimePath"] = task["runtimePath"]
      localRuntimeState["expectedRuntimeExecutablePath"] = expectedRuntimeExecutablePath()
      localRuntimeState["expectedModelFilePath"] = task["expectedModelFilePath"]
      localRuntimeState["downloadKind"] = "model"
      startLocalModelDownload(task: task)
      desktopShellState["lastAction"] = "downloadLocalModel"
      persistLocalRuntimeState() // [小葵 2026-07-21] 立即寫入檔案，避免 Flutter 輪詢讀到舊狀態
    case "startServer":
      let requestedModelId = actionPayload["modelId"] as? String
      // [小葵 2026-09-16 Blue 令] 啟動稽核——llama-server 兩次悄悄啟動找不到呼叫者，
      // 此後每次啟動都打 timestamp 到 stdout log，供孤兒獵人與偵錯對照
      print("[LocalRuntimeAudit] startServer requested at \(Date()) modelId=\(requestedModelId ?? "nil")")
      startLocalRuntimeServer(modelId: requestedModelId)
      desktopShellState["lastAction"] = "startLocalRuntimeServer"
    case "stopServer":
      stopLocalRuntimeServer()
      localRuntimeState.removeValue(forKey: "progress")
      desktopShellState["lastAction"] = "stopLocalRuntimeServer"
    case "deleteModel":
      let modelId = actionPayload["modelId"] as? String ?? ""
      deleteLocalModel(modelId: modelId)
      desktopShellState["lastAction"] = "deleteLocalModel"
    case "listInstalledModels":
      let models = listInstalledLocalModels()
      localRuntimeState["installedModels"] = models
    case "testModel":
      let modelId = actionPayload["modelId"] as? String ?? ""
      // 先回傳「測試中」狀態，實際測試在背景 queue 跑
      localRuntimeState["phase"] = "installed"
      localRuntimeState["detail"] = "正在測試模型 \(modelId)..."
      localRuntimeState["testResult"] = ["modelId": modelId, "passed": false, "status": "starting"]
      desktopShellState["lastAction"] = "testLocalModel"
      // 背景執行測試
      DispatchQueue.global(qos: .userInitiated).async {
        self.testLocalModel(modelId: modelId)
      }
    case "startLabServer":
      // [小葵 2026-09-29 A案] 模型實驗室專用引擎（port 18799）——不動 18789 主生產線。
      // 12B thinking 模型批次推論會自殺（實測兩次），快測引擎改用穩定的 E4B。
      let modelId = actionPayload["modelId"] as? String ?? ""
      print("[LocalRuntimeAudit] startLabServer requested at \(Date()) modelId=\(modelId)")
      localRuntimeState["labServer"] = ["modelId": modelId, "status": "starting", "port": 18799]
      DispatchQueue.global(qos: .userInitiated).async {
        self.startLabServer(modelId: modelId)
      }
    case "stopLabServer":
      stopLabServer()
      desktopShellState["lastAction"] = "stopLabServer"
    default:
      break
    }
    let currentCount = desktopShellState["commandCount"] as? Int ?? 0
    desktopShellState["commandCount"] = currentCount + 1
    persistLocalRuntimeState()
    return localRuntimeState
  }

  private func localRuntimeRootDirectory() -> URL? {
    guard let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
      return nil
    }
    return applicationSupport
      .appendingPathComponent("Bridge", isDirectory: true)
      .appendingPathComponent("LocalRuntime", isDirectory: true)
  }

  private func prepareLocalRuntimeStorage() -> String {
    guard let root = localRuntimeRootDirectory() else {
      localRuntimeState["phase"] = "failed"
      localRuntimeState["detail"] = "無法取得 Application Support 資料夾。"
      localRuntimeState["primaryCommand"] = "prepareRuntime"
      localRuntimeState["primaryActionLabel"] = "重新準備"
      localRuntimeState["primaryActionEnabled"] = true
      return ""
    }
    do {
      try FileManager.default.createDirectory(at: root.appendingPathComponent("models", isDirectory: true), withIntermediateDirectories: true, attributes: nil)
      try FileManager.default.createDirectory(at: root.appendingPathComponent("tasks", isDirectory: true), withIntermediateDirectories: true, attributes: nil)
      try FileManager.default.createDirectory(at: root.appendingPathComponent("runtime", isDirectory: true), withIntermediateDirectories: true, attributes: nil)
      try FileManager.default.createDirectory(at: root.appendingPathComponent("runtime", isDirectory: true).appendingPathComponent("bin", isDirectory: true), withIntermediateDirectories: true, attributes: nil)
      try FileManager.default.createDirectory(at: root.appendingPathComponent("runtime", isDirectory: true).appendingPathComponent("logs", isDirectory: true), withIntermediateDirectories: true, attributes: nil)
      writeLocalRuntimeInstallPlan(root: root)
    } catch {
      localRuntimeState["phase"] = "failed"
      localRuntimeState["detail"] = "建立 Bridge Local Runtime 資料夾失敗：\(error.localizedDescription)"
      localRuntimeState["primaryCommand"] = "prepareRuntime"
      localRuntimeState["primaryActionLabel"] = "重新準備"
      localRuntimeState["primaryActionEnabled"] = true
    }
    return root.path
  }

  // [小葵 2026-07-20] 動態查詢 llama.cpp 最新版本，不再寫死版本號。
  // 橋樑精神：最新、最開源、最去中心化、最自由。
  private func fetchLatestLlamaCppRelease() -> (tag: String, assetName: String, archiveUrl: String)? {
    // 先檢查本地快取（24 小時內）
    if let root = localRuntimeRootDirectory() {
      let cacheURL = root.appendingPathComponent("llama-cpp-release-cache.json")
      if let cache = readJSONObject(from: cacheURL),
         let cachedAt = cache["cachedAt"] as? String,
         let date = ISO8601DateFormatter().date(from: cachedAt),
         Date().timeIntervalSince(date) < 86400,
         let tag = cache["tag"] as? String,
         let assetName = cache["assetName"] as? String,
         let archiveUrl = cache["archiveUrl"] as? String {
        return (tag, assetName, archiveUrl)
      }
    }

    // 查 GitHub API（同步等待，因為在 MethodChannel handler 中）
    guard let apiUrl = URL(string: "https://api.github.com/repos/ggml-org/llama.cpp/releases/latest") else {
      return nil
    }
    var request = URLRequest(url: apiUrl)
    request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
    request.timeoutInterval = 10

    var responseData: Data?
    let semaphore = DispatchSemaphore(value: 0)
    URLSession.shared.dataTask(with: request) { data, _, _ in
      responseData = data
      semaphore.signal()
    }.resume()
    _ = semaphore.wait(timeout: .now() + 10)

    guard let data = responseData,
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let tag = json["tag_name"] as? String,
          let assets = json["assets"] as? [[String: Any]]
    else {
      // fallback 到已知的穩定版本
      return ("b9393", "llama-b9393-bin-macos-arm64.tar.gz",
              "https://github.com/ggml-org/llama.cpp/releases/download/b9393/llama-b9393-bin-macos-arm64.tar.gz")
    }

    // 找 macOS arm64 asset
    let asset = assets.first { asset in
      let name = (asset["name"] as? String ?? "").lowercased()
      return name.contains("macos") && (name.contains("arm64") || name.contains("aarch64"))
    }

    guard let assetName = asset?["name"] as? String,
          let downloadUrl = asset?["browser_download_url"] as? String
    else {
      // fallback
      return ("b9393", "llama-b9393-bin-macos-arm64.tar.gz",
              "https://github.com/ggml-org/llama.cpp/releases/download/b9393/llama-b9393-bin-macos-arm64.tar.gz")
    }

    // 快取結果
    if let root = localRuntimeRootDirectory() {
      let releaseBody = json["body"] as? String ?? ""
      let cache: [String: Any] = [
        "tag": tag,
        "assetName": assetName,
        "archiveUrl": downloadUrl,
        "cachedAt": ISO8601DateFormatter().string(from: Date()),
        "releaseUrl": json["html_url"] as? String ?? "",
        "releaseBody": String(releaseBody.prefix(2000)),
      ]
      writeJSONObject(cache, to: root.appendingPathComponent("llama-cpp-release-cache.json"))
    }

    return (tag, assetName, downloadUrl)
  }

  // URLSession synchronous wrapper
  private func writeLocalRuntimeInstallPlan(root: URL) {
    let runtimeRoot = root.appendingPathComponent("runtime", isDirectory: true)
    let release = fetchLatestLlamaCppRelease()
    let plan: [String: Any] = [
      "schema": "bridge.local-runtime.install-plan.v1",
      "createdAt": ISO8601DateFormatter().string(from: Date()),
      "runtimeRoot": runtimeRoot.path,
      "engine": [
        "id": "llama.cpp.macos-arm64",
        "name": "llama.cpp llama-server",
        "sourceLabel": "ggml-org/llama.cpp GitHub Releases",
        "releasePageUrl": "https://github.com/ggml-org/llama.cpp/releases",
        "recommendedTag": release?.tag ?? "b9393",
        "assetName": release?.assetName ?? "llama-b9393-bin-macos-arm64.tar.gz",
        "archiveUrl": release?.archiveUrl ?? "https://github.com/ggml-org/llama.cpp/releases/download/b9393/llama-b9393-bin-macos-arm64.tar.gz",
        "expectedExecutablePath": expectedRuntimeExecutablePath(root: root),
        "status": FileManager.default.isExecutableFile(atPath: expectedRuntimeExecutablePath(root: root)) ? "available" : "missing",
      ],
      "server": [
        "host": "127.0.0.1",
        "port": 18789,
        "baseUrl": "http://127.0.0.1:18789",
      ],
      "installSteps": [
        "downloadRuntimeArchive",
        "verifyRuntimeArchive",
        "extractLlamaServer",
        "downloadSelectedModel",
        "verifyModelFile",
        "startLocalServer",
      ],
    ]
    writeJSONObject(plan, to: runtimeRoot.appendingPathComponent("install-plan.json"))
  }

  private func startLocalRuntimeDownload() {
    guard localRuntimeDownloadProcess?.isRunning != true else {
      localRuntimeState["detail"] = "推論引擎下載正在進行中。"
      return
    }
    guard let root = localRuntimeRootDirectory() else {
      localRuntimeState["phase"] = "failed"
      localRuntimeState["detail"] = "無法取得 Bridge Local Runtime 資料夾。"
      localRuntimeState["primaryCommand"] = "prepareRuntime"
      localRuntimeState["primaryActionLabel"] = "重新準備"
      localRuntimeState["primaryActionEnabled"] = true
      return
    }
    let runtimeRoot = root.appendingPathComponent("runtime", isDirectory: true)
    let archiveURL = runtimeRoot.appendingPathComponent("llama.cpp-macos-arm64.tar.gz")
    // [小葵 2026-07-20] 動態取得最新版本 URL，不再寫死 b9393
    let release = fetchLatestLlamaCppRelease()
    let sourceURL = release?.archiveUrl ?? "https://github.com/ggml-org/llama.cpp/releases/download/b9393/llama-b9393-bin-macos-arm64.tar.gz"
    do {
      let process = Process()
      process.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
      process.arguments = [
        "--location",
        "--fail",
        "--retry",
        "2",
        "--continue-at",
        "-",
        "--output",
        archiveURL.path,
        sourceURL,
      ]
      let pipe = Pipe()
      process.standardOutput = pipe
      process.standardError = pipe
      process.terminationHandler = { [weak self] finishedProcess in
        DispatchQueue.main.async {
          self?.finishLocalRuntimeDownload(
            statusCode: finishedProcess.terminationStatus,
            archivePath: archiveURL.path
          )
        }
      }
      try process.run()
      localRuntimeDownloadProcess = process
      localRuntimeState["phase"] = "downloading"
      localRuntimeState["detail"] = "Bridge Desktop 正在下載本地推論引擎。"
      localRuntimeState["primaryCommand"] = "status"
      localRuntimeState["primaryActionLabel"] = "下載推論引擎中"
      localRuntimeState["primaryActionEnabled"] = false
      localRuntimeState["downloadKind"] = "runtime"
      localRuntimeState["runtimeArchivePath"] = archiveURL.path
      localRuntimeState["expectedRuntimeExecutablePath"] = expectedRuntimeExecutablePath(root: root)
      persistLocalRuntimeState()
    } catch {
      localRuntimeState["phase"] = "failed"
      localRuntimeState["detail"] = "啟動推論引擎下載失敗：\(error.localizedDescription)"
      localRuntimeState["primaryCommand"] = "prepareRuntime"
      localRuntimeState["primaryActionLabel"] = "重新下載推論引擎"
      localRuntimeState["primaryActionEnabled"] = true
    }
  }

  private func finishLocalRuntimeDownload(statusCode: Int32, archivePath: String) {
    localRuntimeDownloadProcess = nil
    guard statusCode == 0,
          FileManager.default.fileExists(atPath: archivePath),
          fileSize(atPath: archivePath) > 0
    else {
      localRuntimeState["phase"] = "failed"
      localRuntimeState["detail"] = "推論引擎下載失敗或檔案不完整，可重新下載。"
      localRuntimeState["primaryCommand"] = "prepareRuntime"
      localRuntimeState["primaryActionLabel"] = "重新下載推論引擎"
      localRuntimeState["primaryActionEnabled"] = true
      persistLocalRuntimeState()
      return
    }

    guard let installedPath = installLocalRuntimeArchive(archivePath: archivePath) else {
      localRuntimeState["phase"] = "failed"
      localRuntimeState["detail"] = "推論引擎已下載，但沒有找到可用的 llama-server。"
      localRuntimeState["primaryCommand"] = "prepareRuntime"
      localRuntimeState["primaryActionLabel"] = "重新安裝推論引擎"
      localRuntimeState["primaryActionEnabled"] = true
      persistLocalRuntimeState()
      return
    }

    localRuntimeState["phase"] = "installed"
    localRuntimeState["detail"] = "推論引擎已安裝，可以下載建議模型。"
    localRuntimeState["primaryCommand"] = "downloadModel"
    localRuntimeState["primaryActionLabel"] = "下載推薦模型"
    localRuntimeState["primaryActionEnabled"] = true
    localRuntimeState["runtimeExecutablePath"] = installedPath
    localRuntimeState["expectedRuntimeExecutablePath"] = installedPath
    localRuntimeState.removeValue(forKey: "downloadKind")
    localRuntimeState.removeValue(forKey: "progress")
    persistLocalRuntimeState()
  }

  private func installLocalRuntimeArchive(archivePath: String) -> String? {
    guard let root = localRuntimeRootDirectory() else {
      return nil
    }
    let runtimeRoot = root.appendingPathComponent("runtime", isDirectory: true)
    let extractRoot = runtimeRoot.appendingPathComponent("extracted", isDirectory: true)
    let binRoot = runtimeRoot.appendingPathComponent("bin", isDirectory: true)
    do {
      if FileManager.default.fileExists(atPath: extractRoot.path) {
        try FileManager.default.removeItem(at: extractRoot)
      }
      try FileManager.default.createDirectory(at: extractRoot, withIntermediateDirectories: true, attributes: nil)
      let tar = Process()
      tar.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
      tar.arguments = ["-xzf", archivePath, "-C", extractRoot.path]
      try tar.run()
      tar.waitUntilExit()
      guard tar.terminationStatus == 0,
            let extractedServer = findFile(named: "llama-server", under: extractRoot)
      else {
        return nil
      }
      try FileManager.default.createDirectory(at: binRoot, withIntermediateDirectories: true, attributes: nil)
      let targetURL = binRoot.appendingPathComponent("llama-server")
      if FileManager.default.fileExists(atPath: targetURL.path) {
        try FileManager.default.removeItem(at: targetURL)
      }
      // [小葵 2026-07-21] 不用 copyItem（保留 quarantine），改為讀資料建新檔
      // 沙盒內 removexattr 無法移除 com.apple.quarantine，新建檔不會帶此屬性
      if let data = try? Data(contentsOf: extractedServer) {
        FileManager.default.createFile(atPath: targetURL.path, contents: data, attributes: [.posixPermissions: 0o755])
      } else {
        try FileManager.default.copyItem(at: extractedServer, to: targetURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: targetURL.path)
      }

      // [小葵 2026-07-20] 複製所有 dylib 到 bin/，llama-server 需要動態庫才能運行
      let extractedDir = extractedServer.deletingLastPathComponent()
      if let dirContents = try? FileManager.default.contentsOfDirectory(at: extractedDir, includingPropertiesForKeys: nil) {
        for file in dirContents {
          let ext = file.pathExtension
          if ext == "dylib" {
            let dylibTarget = binRoot.appendingPathComponent(file.lastPathComponent)
            if FileManager.default.fileExists(atPath: dylibTarget.path) {
              try? FileManager.default.removeItem(at: dylibTarget)
            }
            // [小葵 2026-07-21] 同樣用讀資料建新檔，避免 quarantine
            if let data = try? Data(contentsOf: file) {
              FileManager.default.createFile(atPath: dylibTarget.path, contents: data, attributes: [.posixPermissions: 0o755])
            } else {
              try? FileManager.default.copyItem(at: file, to: dylibTarget)
            }
          }
        }
      }

      // [小葵 2026-07-20] 移除 quarantine 屬性，否則 macOS Gatekeeper 阻擋執行
      removeQuarantineFromBin(binRoot: binRoot)

      // [小葵 2026-07-20] 記錄安裝版本，供未來更新比對
      let release = fetchLatestLlamaCppRelease()
      if let version = release?.tag {
        writeRuntimeVersion(version)
      }

      writeLocalRuntimeInstallPlan(root: root)
      return targetURL.path
    } catch {
      return nil
    }
  }

  private func findFile(named fileName: String, under root: URL) -> URL? {
    guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else {
      return nil
    }
    for case let url as URL in enumerator {
      if url.lastPathComponent == fileName {
        return url
      }
    }
    return nil
  }

  private func createLocalModelDownloadTask(model: [String: Any], fit: String?, reason: String?) -> [String: Any] {
    let runtimePath = prepareLocalRuntimeStorage()
    let modelId = model["id"] as? String ?? "local-model"
    let now = ISO8601DateFormatter().string(from: Date())
    var task: [String: Any] = [
      "id": "download-\(modelId)",
      "kind": "modelDownload",
      "phase": "downloading",
      "progress": 0.12,
      "modelId": modelId,
      "modelName": model["name"] as? String ?? "模型",
      "modelSize": model["downloadSize"] as? String ?? "",
      "model": model,
      "sourceManifest": model["sourceManifest"] as? [String: Any] ?? [:],
      "fit": fit ?? "unknown",
      "reason": reason ?? "",
      "runtimePath": runtimePath,
      "createdAt": now,
      "updatedAt": now,
    ]
    if let root = localRuntimeRootDirectory() {
      let modelDirectory = root.appendingPathComponent("models", isDirectory: true).appendingPathComponent(modelId, isDirectory: true)
      let taskURL = root.appendingPathComponent("tasks", isDirectory: true).appendingPathComponent("\(modelId).download.json")
      do {
        try FileManager.default.createDirectory(at: modelDirectory, withIntermediateDirectories: true, attributes: nil)
        let sourceManifest = model["sourceManifest"] as? [String: Any] ?? [:]
        let fileName = sourceManifest["fileName"] as? String ?? "\(modelId).gguf"
        let partialFileURL = modelDirectory.appendingPathComponent("\(fileName).part")
        let expectedModelFileURL = modelDirectory.appendingPathComponent(fileName)
        let manifestURL = modelDirectory.appendingPathComponent("manifest.json")
        let licenseURL = modelDirectory.appendingPathComponent("license-notice.txt")
        writeJSONObject(buildResolvedModelManifest(model: model, modelDirectory: modelDirectory, partialFileURL: partialFileURL), to: manifestURL)
        writeLicenseNotice(sourceManifest: sourceManifest, to: licenseURL)
        FileManager.default.createFile(atPath: partialFileURL.path, contents: Data(), attributes: nil)
        task["modelPath"] = modelDirectory.path
        task["partialFilePath"] = partialFileURL.path
        task["expectedModelFilePath"] = expectedModelFileURL.path
        task["manifestPath"] = manifestURL.path
        task["licenseNoticePath"] = licenseURL.path
        task["taskPath"] = taskURL.path
        writeJSONObject(task, to: taskURL)
      } catch {
        task["phase"] = "failed"
        task["error"] = error.localizedDescription
      }
    }
    writeCurrentDownloadTaskId(task["id"] as? String ?? "download-\(modelId)")
    return task
  }

  private func buildResolvedModelManifest(model: [String: Any], modelDirectory: URL, partialFileURL: URL) -> [String: Any] {
    let sourceManifest = model["sourceManifest"] as? [String: Any] ?? [:]
    return [
      "schema": "bridge.local-model.manifest.v1",
      "modelId": model["id"] as? String ?? "local-model",
      "name": model["name"] as? String ?? "Local Model",
      "sizeClass": model["sizeClass"] as? String ?? "",
      "quantization": model["quantization"] as? String ?? "",
      "downloadSize": model["downloadSize"] as? String ?? "",
      "runtime": model["runtime"] as? String ?? "Bridge Local Runtime",
      "source": sourceManifest,
      "downloadUrl": sourceManifest["downloadUrl"] as? String ?? "",
      "repoId": sourceManifest["repoId"] as? String ?? "",
      "modelDirectory": modelDirectory.path,
      "partialFilePath": partialFileURL.path,
      "expectedModelFilePath": modelDirectory.appendingPathComponent(sourceManifest["fileName"] as? String ?? "\(model["id"] as? String ?? "local-model").gguf").path,
      "status": "reserved",
      "createdAt": ISO8601DateFormatter().string(from: Date()),
    ]
  }

  private func startLocalModelDownload(task: [String: Any]) {
    // [小葵 2026-07-21] 改用 URLSession 取代 curl（沙盒內 curl 會寫入 orphan inode，檔案看不見）
    guard localModelDownloadTask == nil else {
      localRuntimeState["detail"] = "模型下載正在進行中。"
      return
    }
    guard let downloadUrl = (task["sourceManifest"] as? [String: Any])?["downloadUrl"] as? String,
          !downloadUrl.isEmpty,
          let url = URL(string: downloadUrl),
          let partialFilePath = task["partialFilePath"] as? String,
          let expectedModelFilePath = task["expectedModelFilePath"] as? String,
          let taskPath = task["taskPath"] as? String
    else {
      localRuntimeState["phase"] = "failed"
      localRuntimeState["detail"] = "模型來源缺少可下載 URL，請換一個模型或等待來源清單更新。"
      localRuntimeState["primaryCommand"] = "downloadModel"
      localRuntimeState["primaryActionLabel"] = "重新下載模型"
      localRuntimeState["primaryActionEnabled"] = true
      return
    }

    do {
      // 確保模型目錄存在
      let modelDir = (partialFilePath as NSString).deletingLastPathComponent
      try FileManager.default.createDirectory(atPath: modelDir, withIntermediateDirectories: true, attributes: nil)
      print("[startLocalModelDownload] 模型目錄已建立: \(modelDir)")

      // 儲存路徑供 delegate 使用
      localModelDownloadTaskPath = taskPath
      localModelDownloadPartialPath = partialFilePath
      localModelDownloadExpectedPath = expectedModelFilePath

      // 建立 delegate 和 session
      let delegate = LocalModelDownloadDelegate()
      delegate.targetPath = partialFilePath // [小葵 2026-07-21] 告訴 delegate 目標路徑
      delegate.onProgress = { [weak self] written, total in
        DispatchQueue.main.async {
          guard let self = self else { return }
          let progress = total > 0 ? Double(written) / Double(total) : 0.0
          self.localRuntimeState["progress"] = progress
          self.localRuntimeState["detail"] = "模型下載中，已取得 \(self.formatBytes(written)) / \(self.formatBytes(total))。"
          self.persistLocalRuntimeState()
        }
      }
      delegate.onComplete = { [weak self] location, error in
        DispatchQueue.main.async {
          guard let self = self else { return }
          self.localModelDownloadTask = nil
          self.localModelDownloadSession = nil
          self.localModelDownloadDelegate = nil
          if let error = error {
            self.finishLocalModelDownload(
              statusCode: -1,
              partialFilePath: partialFilePath,
              expectedModelFilePath: expectedModelFilePath,
              taskPath: taskPath,
              curlLogPath: nil,
              curlOutput: "URLSession error: \(error.localizedDescription)"
            )
            return
          }
          // [小葵 2026-07-21] Bug #16 修復 + 下載流程小重寫（Blue 授權）
          //
          // 【這段流程的職責地圖——全程只有兩次搬檔，多一次就是 bug】
          //   第 1 次：LocalModelDownloadDelegate.didFinishDownloadingTo
          //           系統暫存 → .part（必須在 delegate 回傳前完成，暫存檔會被系統刪）
          //   第 2 次：finishLocalModelDownload
          //           .part → 最終 .gguf，並收尾狀態（installed / failed + persist）
          //   本 closure：只判斷成功/失敗，把結果交給 finishLocalModelDownload。
          //           ❌ 絕對不在這裡搬檔案。
          //
          // Bug #16 根因：成功時 delegate 傳進來的 location 就是 .part 本身，
          // 舊碼卻「先刪 .part 再 moveItem(.part → .part)」——檔案先被自己刪掉，
          // 搬移必然報 "former doesn't exist"。這是 Bug #13 修復（搬移移進 delegate）
          // 時該刪未刪的殘留。教訓：修復「把動作搬位置」時，舊位置的動作必須一起刪。
          guard location != nil else {
            self.finishLocalModelDownload(
              statusCode: -1,
              partialFilePath: partialFilePath,
              expectedModelFilePath: expectedModelFilePath,
              taskPath: taskPath,
              curlLogPath: nil,
              curlOutput: "URLSession completed but no file location"
            )
            return
          }
          self.finishLocalModelDownload(
            statusCode: 0,
            partialFilePath: partialFilePath,
            expectedModelFilePath: expectedModelFilePath,
            taskPath: taskPath,
            curlLogPath: nil,
            curlOutput: nil
          )
        }
      }

      let config = URLSessionConfiguration.default
      config.timeoutIntervalForRequest = 60
      config.timeoutIntervalForResource = 3600 // 1小時，夠下載大模型
      let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
      let downloadTask = session.downloadTask(with: url)
      downloadTask.resume()

      localModelDownloadTask = downloadTask
      localModelDownloadSession = session
      localModelDownloadDelegate = delegate

      localRuntimeState["detail"] = "Bridge Desktop 正在下載模型檔（URLSession），完成後會自動切換成可啟動狀態。"
      localRuntimeState["progress"] = 0.0
      persistLocalRuntimeState()
    } catch {
      print("[startLocalModelDownload] 啟動失敗: \(error.localizedDescription)")
      localRuntimeState["phase"] = "failed"
      localRuntimeState["detail"] = "啟動模型下載失敗：\(error.localizedDescription)"
      localRuntimeState["primaryCommand"] = "downloadModel"
      localRuntimeState["primaryActionLabel"] = "重新下載模型"
      localRuntimeState["primaryActionEnabled"] = true
    }
  }

  /// [小葵 2026-07-21] 下載流程收尾：負責【第 2 次搬檔】.part → 最終 .gguf + 狀態收尾。
  /// 成功：搬檔 → task/state 設 installed → persist。失敗：設 failed → 清暫存 → persist。
  /// 這是 .part → .gguf 的唯一搬移點；delegate 已完成「暫存 → .part」，此處前置檢查
  /// .part 存在且非空才搬，不存在即 failed（代表上游出問題，看 task curlOutput 追查）。
  private func finishLocalModelDownload(statusCode: Int32, partialFilePath: String, expectedModelFilePath: String, taskPath: String, curlLogPath: String? = nil, curlOutput: String? = nil) {
    localModelDownloadProcess = nil
    localModelDownloadTask = nil
    localModelDownloadSession = nil
    localModelDownloadDelegate = nil
    var task = readJSONObject(from: URL(fileURLWithPath: taskPath)) ?? [:]
    let partialURL = URL(fileURLWithPath: partialFilePath)
    let finalURL = URL(fileURLWithPath: expectedModelFilePath)
    let now = ISO8601DateFormatter().string(from: Date())

    guard statusCode == 0, FileManager.default.fileExists(atPath: partialFilePath), fileSize(atPath: partialFilePath) > 0 else {
      task["phase"] = "failed"
      task["updatedAt"] = now
      task["error"] = statusCode == 0 ? "下載完成但檔案不存在或為空" : "下載失敗（代碼：\(statusCode)）"
      if let output = curlOutput, !output.isEmpty {
        task["curlOutput"] = output
      }
      if let logPath = curlLogPath {
        task["curlLogPath"] = logPath
      }
      writeJSONObject(task, to: URL(fileURLWithPath: taskPath))
      localRuntimeState["phase"] = "failed"
      localRuntimeState["detail"] = "模型下載失敗或檔案不完整，可重新下載。"
      if let output = curlOutput, !output.isEmpty {
        localRuntimeState["detail"] = "模型下載失敗：\(output.prefix(200))"
      }
      localRuntimeState["primaryCommand"] = "downloadModel"
      localRuntimeState["primaryActionLabel"] = "重新下載模型"
      localRuntimeState["primaryActionEnabled"] = true
      localRuntimeState["expectedModelFilePath"] = expectedModelFilePath
      persistLocalRuntimeState()
      return
    }

    do {
      if FileManager.default.fileExists(atPath: expectedModelFilePath) {
        try FileManager.default.removeItem(at: finalURL)
      }
      try FileManager.default.moveItem(at: partialURL, to: finalURL)
      let bytes = fileSize(atPath: expectedModelFilePath)
      task["phase"] = "installed"
      task["progress"] = 1.0
      task["modelFilePath"] = expectedModelFilePath
      task["downloadedBytes"] = bytes
      task["updatedAt"] = now
      writeJSONObject(task, to: URL(fileURLWithPath: taskPath))
      updateModelManifestStatus(modelFilePath: expectedModelFilePath, status: "downloaded", bytes: bytes)
      localRuntimeState["phase"] = "installed"
      localRuntimeState["detail"] = "模型下載完成（\(formatBytes(bytes))），可以啟動本地 server。"
      localRuntimeState["primaryCommand"] = "startServer"
      localRuntimeState["primaryActionLabel"] = "啟動本地 server"
      localRuntimeState["primaryActionEnabled"] = true
      localRuntimeState["progress"] = 1.0
      localRuntimeState["modelFilePath"] = expectedModelFilePath
      localRuntimeState["expectedModelFilePath"] = expectedModelFilePath
      persistLocalRuntimeState()
    } catch {
      localRuntimeState["phase"] = "failed"
      localRuntimeState["detail"] = "模型下載完成但整理檔案失敗：\(error.localizedDescription)"
      localRuntimeState["primaryCommand"] = "downloadModel"
      localRuntimeState["primaryActionLabel"] = "重新下載模型"
      localRuntimeState["primaryActionEnabled"] = true
      
      // [小葵 2026-07-21] 下載失敗時自動刪除暫存檔
      cleanupFailedDownloadTempFiles(taskPath: localModelDownloadTaskPath)
      
      persistLocalRuntimeState()
    }
  }

  private func updateModelManifestStatus(modelFilePath: String, status: String, bytes: Int64) {
    let modelURL = URL(fileURLWithPath: modelFilePath)
    let manifestURL = modelURL.deletingLastPathComponent().appendingPathComponent("manifest.json")
    var manifest = readJSONObject(from: manifestURL) ?? [:]
    manifest["status"] = status
    manifest["modelFilePath"] = modelFilePath
    manifest["downloadedBytes"] = bytes
    manifest["updatedAt"] = ISO8601DateFormatter().string(from: Date())
    writeJSONObject(manifest, to: manifestURL)
  }

  private func fileSize(atPath path: String) -> Int64 {
    guard !path.isEmpty,
          let attributes = try? FileManager.default.attributesOfItem(atPath: path),
          let size = attributes[.size] as? NSNumber
    else {
      return 0
    }
    return size.int64Value
  }

  private func formatBytes(_ bytes: Int64) -> String {
    let value = Double(bytes)
    if value >= 1_073_741_824 {
      return String(format: "%.2f GB", value / 1_073_741_824)
    }
    if value >= 1_048_576 {
      return String(format: "%.1f MB", value / 1_048_576)
    }
    if value >= 1024 {
      return String(format: "%.1f KB", value / 1024)
    }
    return "\(bytes) bytes"
  }

  /// [小葵 2026-07-21] 從 "2.52 GB" 這類字串解析出位元組數
  /// [小葵 2026-07-21] 從 "約 2.52 GB" 這類帶中文字串解析出位元組數
  private func parseBytesFromSizeString(_ sizeStr: String) -> Int64? {
    let trimmed = sizeStr.trimmingCharacters(in: .whitespaces)
    // 用 Scanner 跳過非數字前綴（如「約」），抓第一個浮點數 + 單位
    let scanner = Scanner(string: trimmed)
    scanner.charactersToBeSkipped = CharacterSet(charactersIn: "約约about ")
    var number: Double = 0
    guard scanner.scanDouble(&number) else { return nil }
    let remaining = String(scanner.string[scanner.currentIndex...]).trimmingCharacters(in: .whitespaces)
    let upper = remaining.uppercased()
    if upper.hasPrefix("GB") { return Int64(number * 1_073_741_824) }
    if upper.hasPrefix("MB") { return Int64(number * 1_048_576) }
    if upper.hasPrefix("KB") { return Int64(number * 1024) }
    return Int64(number)
  }

  private func writeLicenseNotice(sourceManifest: [String: Any], to url: URL) {
    let sourceLabel = sourceManifest["sourceLabel"] as? String ?? "Unknown source"
    let licenseLabel = sourceManifest["licenseLabel"] as? String ?? "Unknown license"
    let manifestUrl = sourceManifest["manifestUrl"] as? String ?? ""
    let downloadUrl = sourceManifest["downloadUrl"] as? String ?? ""
    let notice = """
    Bridge Local Runtime model notice

    Source: \(sourceLabel)
    License: \(licenseLabel)
    Manifest: \(manifestUrl)
    Download: \(downloadUrl)

    This placeholder is created before the real downloader fetches and verifies model files.
    """
    try? notice.data(using: .utf8)?.write(to: url, options: [.atomic])
  }

  private func advanceLocalRuntimeDownloadIfNeeded() {
    refreshLocalRuntimeProcessState()
    if (localRuntimeState["phase"] as? String) == "running" {
      return
    }
    if (localRuntimeState["downloadKind"] as? String) == "runtime" {
      let archivePath = localRuntimeState["runtimeArchivePath"] as? String ?? ""
      let bytes = fileSize(atPath: archivePath)
      if localRuntimeDownloadProcess?.isRunning == true {
        localRuntimeState["detail"] = bytes > 0
          ? "推論引擎下載中，已取得 \(formatBytes(bytes))。"
          : "推論引擎下載中，正在連接來源。"
        localRuntimeState["primaryCommand"] = "status"
        localRuntimeState["primaryActionLabel"] = "下載推論引擎中"
        localRuntimeState["primaryActionEnabled"] = false
      } else if !FileManager.default.isExecutableFile(atPath: expectedRuntimeExecutablePath()) {
        localRuntimeState["phase"] = "failed"
        localRuntimeState["detail"] = bytes > 0
          ? "推論引擎下載中斷，已保留 \(formatBytes(bytes))，可重新下載續傳。"
          : "推論引擎尚未下載完成，可重新下載。"
        localRuntimeState["primaryCommand"] = "prepareRuntime"
        localRuntimeState["primaryActionLabel"] = "重新下載推論引擎"
        localRuntimeState["primaryActionEnabled"] = true
      }
      return
    }
    guard (localRuntimeState["phase"] as? String) == "downloading",
          let modelId = localRuntimeState["modelId"] as? String,
          let root = localRuntimeRootDirectory()
    else {
      return
    }
    let taskURL = root.appendingPathComponent("tasks", isDirectory: true).appendingPathComponent("\(modelId).download.json")
    var task = readJSONObject(from: taskURL) ?? [:]
    if let modelURL = resolvedModelFileURL(modelId: modelId), FileManager.default.fileExists(atPath: modelURL.path) {
      task["phase"] = "installed"
      task["progress"] = 1.0
      task["modelFilePath"] = modelURL.path
      task["updatedAt"] = ISO8601DateFormatter().string(from: Date())
      localRuntimeState["phase"] = "installed"
      localRuntimeState["detail"] = "已找到本地模型檔，可以啟動本地 server。"
      localRuntimeState["primaryCommand"] = "startServer"
      localRuntimeState["primaryActionLabel"] = "啟動本地 server"
      localRuntimeState["primaryActionEnabled"] = true
      localRuntimeState["progress"] = 1.0
      localRuntimeState["modelFilePath"] = modelURL.path
      localRuntimeState["expectedModelFilePath"] = modelURL.path
      writeJSONObject(task, to: taskURL)
      return
    }
    task["updatedAt"] = ISO8601DateFormatter().string(from: Date())
    // [小葵 2026-07-21] modelSize 可能存在 task["modelSize"] 或 task["model"]["downloadSize"]
    func resolveModelSize(_ t: [String: Any]) -> String {
      if let s = t["modelSize"] as? String, !s.isEmpty { return s }
      if let m = t["model"] as? [String: Any], let s = m["downloadSize"] as? String, !s.isEmpty { return s }
      return ""
    }
    func resolveModelName(_ t: [String: Any]) -> String {
      if let s = t["modelName"] as? String, !s.isEmpty { return s }
      if let m = t["model"] as? [String: Any], let s = m["name"] as? String, !s.isEmpty { return s }
      return "模型"
    }

    // [小葵 2026-07-21] 檢查 URLSession task 是否還在跑
    if localModelDownloadTask != nil {
      // [小葵 2026-07-21] 不要覆蓋 onProgress 設定的進度！
      // URLSession 還沒完成時，.part 檔案不存在，bytes = 0，會導致 progressPct = nil
      // 保留 onProgress 設定的 progress，只更新 task JSON
      let modelName = resolveModelName(task)
      let modelSize = resolveModelSize(task)
      task["phase"] = "downloading"
      // 從 localRuntimeState 取得目前的 progress（由 onProgress 設定）
      if let currentProgress = localRuntimeState["progress"] as? Double,
         let totalBytes = parseBytesFromSizeString(modelSize) {
        task["downloadedBytes"] = Int64(currentProgress * Double(totalBytes))
      }
      localRuntimeState["title"] = modelName
      // detail 已由 onProgress 設定，這裡不需要覆蓋
    } else if let partialFilePath = task["partialFilePath"] as? String,
              FileManager.default.fileExists(atPath: partialFilePath),
              fileSize(atPath: partialFilePath) > 0 {
      // [小葵 2026-07-21] URLSession 可能已結束但檔案還在 — 檢查是否完成
      let bytes = fileSize(atPath: partialFilePath)
      let modelName = resolveModelName(task)
      let modelSize = resolveModelSize(task)
      var progressPct: Double? = nil
      if let totalBytes = parseBytesFromSizeString(modelSize), totalBytes > 0 {
        progressPct = min(100.0, Double(bytes) / Double(totalBytes) * 100.0)
      }
      // 如果進度接近 100%，嘗試完成下載
      if let pct = progressPct, pct > 95.0 {
        task["phase"] = "completing"
        task["downloadedBytes"] = bytes
        localRuntimeState["phase"] = "downloading"
        localRuntimeState["progress"] = pct
        localRuntimeState["title"] = modelName
        localRuntimeState["detail"] = "\(modelName)（\(modelSize)）下載完成，正在處理..."
      } else {
        // 下載中斷，但檔案還在 — 可續傳
        task["phase"] = "paused"
        task["downloadedBytes"] = bytes
        localRuntimeState["phase"] = "downloading"
        localRuntimeState["progress"] = progressPct
        localRuntimeState["title"] = modelName
        localRuntimeState["detail"] = "\(modelName)（\(modelSize)）下載中，已取得 \(formatBytes(bytes))。"
        localRuntimeState["primaryCommand"] = "status"
        localRuntimeState["primaryActionLabel"] = "下載中"
        localRuntimeState["primaryActionEnabled"] = false
      }
    } else {
      let partialFilePath = task["partialFilePath"] as? String ?? ""
      let bytes = fileSize(atPath: partialFilePath)
      task["phase"] = "failed"
      task["downloadedBytes"] = bytes
      localRuntimeState["phase"] = "failed"
      localRuntimeState["progress"] = nil
      localRuntimeState["detail"] = bytes > 0
        ? "模型下載中斷，已保留 \(formatBytes(bytes)) 暫存檔，可重新下載續傳。"
        : "模型下載尚未開始或已中斷，可重新下載。"
      localRuntimeState["primaryCommand"] = "downloadModel"
      localRuntimeState["primaryActionLabel"] = "重新下載模型"
      localRuntimeState["primaryActionEnabled"] = true
    }
    writeJSONObject(task, to: taskURL)
  }

  /// [小葵 2026-07-20] 啟動本地 server，可指定 modelId 切換模型
  /// 16GB 機器一次只跑一個模型（順序模式），切換時先停舊的再啟新的
  // [小葵 2026-08-25] 偵測 18789 是否已有外部引擎在服務（例如 launchd 常駐的 llama-server）。
  // 回呼（serving, modelName）：modelName 取自 /v1/models 第一個模型，失敗則為 nil。
  private func probeExternalLlamaServer() -> (serving: Bool, modelName: String?) {
    guard let url = URL(string: "http://127.0.0.1:18789/v1/models") else { return (false, nil) }
    var request = URLRequest(url: url)
    request.timeoutInterval = 2
    var ok = false
    var modelName: String? = nil
    let semaphore = DispatchSemaphore(value: 0)
    URLSession.shared.dataTask(with: request) { data, response, _ in
      defer { semaphore.signal() }
      guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return }
      ok = true
      if let data = data,
         let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
         let models = json["models"] as? [[String: Any]],
         let first = models.first {
        let raw = (first["model"] as? String) ?? (first["id"] as? String) ?? ""
        if !raw.isEmpty {
          // 只留檔名部分，避免整條路徑塞進 UI
          modelName = (raw as NSString).lastPathComponent
        }
      }
    }.resume()
    _ = semaphore.wait(timeout: .now() + 3)
    return (ok, modelName)
  }

  private func startLocalRuntimeServer(modelId: String? = nil) {
    restoreLocalRuntimeState()
    // preflight 前先移除 quarantine
    if let root = localRuntimeRootDirectory() {
      let binDir = root.appendingPathComponent("runtime/bin")
      removeQuarantineFromBin(binRoot: binDir)
    }

    // 如果指定了 modelId，先找到對應的 .gguf 檔案路徑
    var targetModelPath: String? = nil
    var targetModelName: String = ""
    if let requestedId = modelId {
      // [小葵 2026-08-25] 外部引擎已在服務且載的就是同一個模型 → 直接重用
      if localRuntimeProcess?.isRunning != true {
        let probe = probeExternalLlamaServer()
        if probe.serving,
           let externalName = probe.modelName,
           let root = localRuntimeRootDirectory() {
          let modelDir = root.appendingPathComponent("models", isDirectory: true)
                            .appendingPathComponent(requestedId, isDirectory: true)
          if let files = try? FileManager.default.contentsOfDirectory(atPath: modelDir.path),
             files.contains(where: { $0.hasSuffix(".gguf") && externalName.contains($0.replacingOccurrences(of: ".gguf", with: "")) }) {
            NSLog("[LocalRuntime] 外部引擎已載入 \(requestedId)，直接重用。")
            localRuntimeState["modelId"] = requestedId
            localRuntimeState["modelFilePath"] = modelDir.path
            localRuntimeState["activeModelName"] = externalName
            // [小葵 2026-10-01] 外部引擎重用時 title 也要更正——
            // 否則卡片大字殘留下一次登基的模型名（Blue 抓包：12B 外部登基、卡顯示 E4B）
            localRuntimeState["title"] = externalName
            localRuntimeState["phase"] = "running"
            localRuntimeState["detail"] = "偵測到 18789 已有引擎載入 \(requestedId)，直接重用（不重複啟動）。"
            localRuntimeState["primaryCommand"] = "startServer"
            localRuntimeState["primaryActionLabel"] = "已在服務（外部引擎）"
            localRuntimeState["primaryActionEnabled"] = false
            localRuntimeState["progress"] = 1.0
            localRuntimeState["serverUrl"] = "http://127.0.0.1:18789"
            localRuntimeState["engineSource"] = "external"
            persistLocalRuntimeState()
            return
          }
        }
      }
      // 如果 server 正在跑且是同一個模型，不用重啟
      if localRuntimeProcess?.isRunning == true,
         let currentModelId = localRuntimeState["modelId"] as? String,
         currentModelId == requestedId {
        localRuntimeState["phase"] = "running"
        localRuntimeState["detail"] = "本地模型 server 已在 http://127.0.0.1:18789 運行。"
        localRuntimeState["primaryCommand"] = "stopServer"
        localRuntimeState["primaryActionLabel"] = "停止本地 server"
        localRuntimeState["primaryActionEnabled"] = true
        return
      }
      // 先停掉目前正在跑的 server
      if localRuntimeProcess?.isRunning == true {
        localRuntimeProcess?.terminate()
        localRuntimeProcess = nil
      }
      // 找到指定的模型檔案
      if let root = localRuntimeRootDirectory() {
        let modelDir = root.appendingPathComponent("models", isDirectory: true)
                          .appendingPathComponent(requestedId, isDirectory: true)
        if FileManager.default.fileExists(atPath: modelDir.path) {
          if let files = try? FileManager.default.contentsOfDirectory(atPath: modelDir.path) {
            for f in files where f.hasSuffix(".gguf") {
              targetModelPath = modelDir.appendingPathComponent(f).path
              targetModelName = f
              break
            }
          }
        }
      }
      if targetModelPath == nil {
        localRuntimeState["phase"] = "failed"
        localRuntimeState["detail"] = "找不到模型 \(requestedId)，請先下載。"
        localRuntimeState["primaryCommand"] = "downloadModel"
        localRuntimeState["primaryActionLabel"] = "下載推薦模型"
        localRuntimeState["primaryActionEnabled"] = true
        return
      }
      // 更新 state 指向新模型
      localRuntimeState["modelId"] = requestedId
      localRuntimeState["modelFilePath"] = targetModelPath
      localRuntimeState["activeModelName"] = targetModelName
      persistLocalRuntimeState()
    }

    // [小葵 2026-07-27] 啟動前移除 quarantine + provenance 屬性
    // 沒有這一步，sandbox 內 Process.run() 可能靜默失敗
    if let root = localRuntimeRootDirectory() {
      let binDir = root.appendingPathComponent("runtime/bin")
      removeQuarantineFromBin(binRoot: binDir)
    }

    let preflight = localRuntimePreflight()
    guard let executableURL = preflight.executableURL else {
      localRuntimeState["phase"] = "failed"
      localRuntimeState["detail"] = "尚未找到本地推論引擎。請將 llama-server 放到 \\(preflight.expectedExecutablePath)。"
      localRuntimeState["primaryCommand"] = "prepareRuntime"
      localRuntimeState["primaryActionLabel"] = "重新安裝引擎"
      localRuntimeState["primaryActionEnabled"] = true
      localRuntimeState["expectedRuntimeExecutablePath"] = preflight.expectedExecutablePath
      localRuntimeState["expectedModelFilePath"] = preflight.expectedModelPath
      return
    }
    guard let modelURL = preflight.modelURL else {
      localRuntimeState["phase"] = "failed"
      localRuntimeState["detail"] = "尚未找到可啟動的 .gguf 模型檔。請先完成模型下載或放入模型檔。"
      localRuntimeState["primaryCommand"] = "status"
      localRuntimeState["primaryActionLabel"] = "等待模型檔"
      localRuntimeState["primaryActionEnabled"] = false
      localRuntimeState["runtimeExecutablePath"] = executableURL.path
      localRuntimeState["expectedRuntimeExecutablePath"] = preflight.expectedExecutablePath
      localRuntimeState["expectedModelFilePath"] = preflight.expectedModelPath
      return
    }
    if localRuntimeProcess?.isRunning == true {
      localRuntimeState["phase"] = "running"
      localRuntimeState["detail"] = "本地模型 server 已在 http://127.0.0.1:18789 運行。"
      localRuntimeState["primaryCommand"] = "stopServer"
      localRuntimeState["primaryActionLabel"] = "停止本地 server"
      localRuntimeState["primaryActionEnabled"] = true
      localRuntimeState["runtimeExecutablePath"] = executableURL.path
      localRuntimeState["expectedRuntimeExecutablePath"] = preflight.expectedExecutablePath
      localRuntimeState["modelFilePath"] = modelURL.path
      localRuntimeState["expectedModelFilePath"] = modelURL.path
      localRuntimeState["activeModelName"] = activeLocalModelName(modelURL: modelURL)
      localRuntimeState["serverUrl"] = "http://127.0.0.1:18789"
      return
    }
    // [小葵 2026-08-25] port 被佔就重用現有引擎：launchd 常駐 llama-server（或其他外部引擎）
    // 已在 18789 服務時，不搶 port、不重複載入模型，直接標記 running 並重用。
    if localRuntimeProcess?.isRunning != true {
      let probe = probeExternalLlamaServer()
      if probe.serving {
        NSLog("[LocalRuntime] 18789 已有外部引擎服務中（launchd 或其他），重用之，不另啟動。")
        localRuntimeState["phase"] = "running"
        localRuntimeState["detail"] = "偵測到 127.0.0.1:18789 已有推論引擎服務中，直接重用（不重複啟動）。"
        localRuntimeState["primaryCommand"] = "startServer"
        localRuntimeState["primaryActionLabel"] = "已在服務（外部引擎）"
        localRuntimeState["primaryActionEnabled"] = false
        localRuntimeState["progress"] = 1.0
        localRuntimeState["serverUrl"] = "http://127.0.0.1:18789"
        localRuntimeState["engineSource"] = "external"
        if let name = probe.modelName {
          localRuntimeState["activeModelName"] = name
        }
        localRuntimeState["runtimeExecutablePath"] = executableURL.path
        localRuntimeState["expectedRuntimeExecutablePath"] = preflight.expectedExecutablePath
        localRuntimeState["modelFilePath"] = modelURL.path
        localRuntimeState["expectedModelFilePath"] = preflight.expectedModelPath
        persistLocalRuntimeState()
        return
      }
    }
    do {
      let process = Process()
      process.executableURL = executableURL
      // [小葵 2026-07-27] 根據模型大小動態調整 context size
      // 16GB RAM 機器：模型 + KV cache 不能超過 ~12GB
      // Qwen 2.7GB → 65536 context（KV cache ~4GB）= ~7GB ✅
      // Gemma E4B 5.3GB → 32768 context（KV cache ~2GB）= ~7.5GB ✅
      // [小葵 2026-09-28] Gemma 12B 7.1GB（unified KV）→ 4096 context
      // 實測（09-27/28）：32768 在 12B 上 = 16GB 機直接 Jetsam OOM 重開機；
      // 4096 穩定運行（bench 20 張全跑完），RAM ~5.8GB。
      let modelAttrs = try? FileManager.default.attributesOfItem(atPath: modelURL.path)
      let modelSize = (modelAttrs?[.size] as? Int) ?? 0
      let ctxSize: String
      if modelSize > 6_500_000_000 {
        // > 6.5GB 模型（如 12B）→ 4096 context（16GB 機防 OOM）
        ctxSize = "4096"
      } else if modelSize > 4_000_000_000 {
        // > 4GB 模型用 32768 context
        ctxSize = "32768"
      } else {
        // ≤ 4GB 模型用 65536 context
        ctxSize = "65536"
      }
      // [小葵 2026-07-27] 多模態支援 — 如果同目錄有 mmproj 檔案，加上 --mmproj 參數
      let modelDir = modelURL.deletingLastPathComponent()
      let mmprojURL = modelDir.appendingPathComponent("mmproj-f16.gguf")
      var args = ["-m", modelURL.path, "--host", "127.0.0.1", "--port", "18789", "-c", ctxSize, "-b", "512", "-ub", "512", "-ngl", "99"]
      if FileManager.default.fileExists(atPath: mmprojURL.path) {
        args += ["--mmproj", mmprojURL.path]
        NSLog("[LocalRuntime] 多模態已啟用: mmproj=\(mmprojURL.path)")
      }
      process.arguments = args
      // [小葵 2026-07-20] 設定 DYLD_LIBRARY_PATH 讓 llama-server 找到同目錄的 dylib
      let binDir = executableURL.deletingLastPathComponent().path
      var env = ProcessInfo.processInfo.environment
      env["DYLD_LIBRARY_PATH"] = binDir
      process.environment = env
      // [小葵 2026-08-13] 不用 Pipe——pipe buffer 滿了會讓 llama-server write 卡住被殺
      // 改寫到 log 檔案，方便除錯
      let logDir = URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent("Library/Application Support/Bridge/LocalRuntime/runtime/logs")
      try? FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)
      let logFile = logDir.appendingPathComponent("llama-server-\(Int(Date().timeIntervalSince1970)).log")
      FileManager.default.createFile(atPath: logFile.path, contents: nil)
      let logHandle = FileHandle(forWritingAtPath: logFile.path)!
      process.standardOutput = logHandle
      process.standardError = logHandle
      NSLog("[LocalRuntime] spawning llama-server: \(executableURL.path) args=\(args)")
      NSLog("[LocalRuntime] log file: \(logFile.path)")
      try process.run()
      NSLog("[LocalRuntime] process.run() succeeded, pid=\(process.processIdentifier)")
      localRuntimeProcess = process
      localRuntimeState["phase"] = "running"
      localRuntimeState["detail"] = "本地模型 server 已啟動：http://127.0.0.1:18789。"
      localRuntimeState["primaryCommand"] = "stopServer"
      localRuntimeState["primaryActionLabel"] = "停止本地 server"
      localRuntimeState["primaryActionEnabled"] = true
      localRuntimeState["progress"] = 1.0
      localRuntimeState["runtimeExecutablePath"] = executableURL.path
      localRuntimeState["expectedRuntimeExecutablePath"] = preflight.expectedExecutablePath
      localRuntimeState["modelFilePath"] = modelURL.path
      localRuntimeState["expectedModelFilePath"] = modelURL.path
      localRuntimeState["activeModelName"] = activeLocalModelName(modelURL: modelURL)
      localRuntimeState["serverUrl"] = "http://127.0.0.1:18789"
    } catch {
      localRuntimeState["phase"] = "failed"
      localRuntimeState["detail"] = "啟動本地模型 server 失敗：\(error.localizedDescription)"
      localRuntimeState["primaryCommand"] = "startServer"
      localRuntimeState["primaryActionLabel"] = "重新啟動"
      localRuntimeState["primaryActionEnabled"] = true
      localRuntimeState["runtimeExecutablePath"] = executableURL.path
      localRuntimeState["expectedRuntimeExecutablePath"] = preflight.expectedExecutablePath
      localRuntimeState["modelFilePath"] = modelURL.path
      localRuntimeState["expectedModelFilePath"] = modelURL.path
      localRuntimeState["activeModelName"] = activeLocalModelName(modelURL: modelURL)
    }
  }

  /// [小葵 2026-07-20] 測試模型是否可用
  /// 完全複用 startLocalRuntimeServer 的邏輯，用 port 18799 測試
  private func testLocalModel(modelId: String) {
    // 先停掉目前跑的 server
    if localRuntimeProcess?.isRunning == true {
      localRuntimeProcess?.terminate()
      localRuntimeProcess = nil
    }

    // 移除 quarantine + provenance
    if let root = localRuntimeRootDirectory() {
      let binDir = root.appendingPathComponent("runtime/bin")
      removeQuarantineFromBin(binRoot: binDir)
    }

    // 用 preflight 取得 executableURL（跟 startLocalRuntimeServer 一樣）
    // 但臨時設定 modelId 讓 preflight 找到正確的模型
    let savedModelId = localRuntimeState["modelId"] as? String
    localRuntimeState["modelId"] = modelId

    let preflight = localRuntimePreflight()
    // Debug: 記錄 preflight 結果
    localRuntimeState["testDebug"] = [
      "executableURL": preflight.executableURL?.path ?? "nil",
      "modelURL": preflight.modelURL?.path ?? "nil",
      "expectedExecutablePath": preflight.expectedExecutablePath,
      "expectedModelPath": preflight.expectedModelPath ?? "nil",
      "runtimeRoot": localRuntimeRootDirectory()?.path ?? "nil",
    ]
    persistLocalRuntimeState()
    guard let executableURL = preflight.executableURL else {
      localRuntimeState["phase"] = "installed"
      localRuntimeState["detail"] = "llama-server 不存在或不可執行。"
      localRuntimeState["testResult"] = ["modelId": modelId, "passed": false, "error": "llama-server not found"]
      saveTestResult(modelId: modelId, passed: false, error: "llama-server 不存在或不可執行")
      localRuntimeState["modelId"] = savedModelId
      return
    }
    guard let modelURL = preflight.modelURL else {
      localRuntimeState["phase"] = "installed"
      localRuntimeState["detail"] = "找不到模型 \(modelId) 的 .gguf 檔案。"
      localRuntimeState["testResult"] = ["modelId": modelId, "passed": false, "error": "model not found"]
      saveTestResult(modelId: modelId, passed: false, error: "找不到模型檔案")
      localRuntimeState["modelId"] = savedModelId
      return
    }

    // 啟動臨時 server（用 port 18799 避免衝突）
    let testPort = 18799
    let binDir = executableURL.deletingLastPathComponent().path
    var env = ProcessInfo.processInfo.environment
    env["DYLD_LIBRARY_PATH"] = binDir

    let process = Process()
    process.executableURL = executableURL
    process.arguments = ["-m", modelURL.path, "--host", "127.0.0.1", "--port", "\(testPort)", "-c", "32768", "-b", "512", "-ub", "512"]
    process.environment = env
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe

    localRuntimeState["phase"] = "installed"
    localRuntimeState["detail"] = "正在測試模型 \(modelId)..."
    localRuntimeState["testResult"] = ["modelId": modelId, "passed": false, "status": "starting"]

    do {
      try process.run()
    } catch {
      let errMsg = "啟動 server 失敗：\(error.localizedDescription)"
      localRuntimeState["detail"] = errMsg
      localRuntimeState["testResult"] = ["modelId": modelId, "passed": false, "error": "process run failed: \(error.localizedDescription)"]
      saveTestResult(modelId: modelId, passed: false, error: errMsg)
      localRuntimeState["modelId"] = savedModelId
      return
    }

    // 等 server 啟動（最多 20 秒）
    var serverReady = false
    for _ in 0..<40 {
      Thread.sleep(forTimeInterval: 0.5)
      if isServerReady(port: testPort) {
        serverReady = true
        break
      }
      if !process.isRunning {
        break
      }
    }

    if !serverReady {
      process.terminate()
      let errMsg = process.isRunning ? "server 未在 20 秒內就緒" : "server 啟動後立即結束"
      localRuntimeState["detail"] = "模型 \(modelId) 測試失敗：\(errMsg)"
      localRuntimeState["testResult"] = ["modelId": modelId, "passed": false, "error": errMsg]
      saveTestResult(modelId: modelId, passed: false, error: errMsg)
      localRuntimeState["modelId"] = savedModelId
      return
    }

    // 送測試 prompt
    let testPrompt = "你好，請用一句話介紹你自己。"
    let testResult = sendTestRequest(port: testPort, prompt: testPrompt)

    // 停止臨時 server
    process.terminate()
    process.waitUntilExit()

    // 恢復原本的 modelId
    localRuntimeState["modelId"] = savedModelId

    if testResult.success && !testResult.response.isEmpty {
      localRuntimeState["phase"] = "installed"
      localRuntimeState["detail"] = "模型 \(modelId) 測試通過！可以加入候選列表。"
      localRuntimeState["testResult"] = [
        "modelId": modelId,
        "passed": true,
        "response": String(testResult.response.prefix(200)),
        "latencyMs": testResult.latencyMs,
      ]
      saveTestResult(modelId: modelId, passed: true, response: String(testResult.response.prefix(200)), latencyMs: testResult.latencyMs)
    } else {
      localRuntimeState["phase"] = "installed"
      localRuntimeState["detail"] = "模型 \(modelId) 測試失敗：\(testResult.error)"
      localRuntimeState["testResult"] = ["modelId": modelId, "passed": false, "error": testResult.error]
      saveTestResult(modelId: modelId, passed: false, error: testResult.error)
    }
  }

  /// 檢查 server 是否就緒
  // ══════════════════════════════════════════════════════════════
  // [小葵 2026-09-29 A案] 模型實驗室 lab server（port 18799）
  // 與 18789 主生產線完全獨立——快測用穩定的 E4B，
  // 12B thinking 模型批次推論會自殺的問題不影響生產線。
  // ══════════════════════════════════════════════════════════════
  private var labServerProcess: Process?

  private func startLabServer(modelId: String) {
    // 若已在跑先停掉（換模型重測）
    stopLabServer()

    // 找模型（與 testLocalModel 同邏輯但不動 localRuntimeState.modelId）
    let savedModelId = localRuntimeState["modelId"] as? String
    localRuntimeState["modelId"] = modelId
    let preflight = localRuntimePreflight()
    localRuntimeState["modelId"] = savedModelId // 立刻還原，主生產線不受影響

    guard let executableURL = preflight.executableURL,
          let modelURL = preflight.modelURL else {
      DispatchQueue.main.async {
        self.localRuntimeState["labServer"] = ["modelId": modelId, "status": "error", "error": "找不到模型 \(modelId) 或 llama-server"]
        self.persistLocalRuntimeState()
      }
      return
    }

    let binDir = executableURL.deletingLastPathComponent().path
    var env = ProcessInfo.processInfo.environment
    env["DYLD_LIBRARY_PATH"] = binDir

    let process = Process()
    process.executableURL = executableURL
    // [小葵 2026-09-29 修] 補 mmproj（視覺投影器——沒它 E4B 看不到照片，實測 HTTP 500）+ -ngl 99 GPU 卸載
    let modelDir = modelURL.deletingLastPathComponent()
    let mmprojURL = modelDir.appendingPathComponent("mmproj-f16.gguf")
    var labArgs = ["-m", modelURL.path, "--host", "127.0.0.1", "--port", "18799",
                   "-c", "8192", "-b", "512", "-ub", "512", "-ngl", "99"]
    if FileManager.default.fileExists(atPath: mmprojURL.path) {
      labArgs += ["--mmproj", mmprojURL.path]
      print("[LocalRuntimeAudit] labServer 多模態已啟用: mmproj=\(mmprojURL.path)")
    } else {
      print("[LocalRuntimeAudit] labServer ⚠️ 無 mmproj——此模型不支援視覺（快測會失敗）")
    }
    process.arguments = labArgs
    process.environment = env
    do {
      try process.run()
    } catch {
      DispatchQueue.main.async {
        self.localRuntimeState["labServer"] = ["modelId": modelId, "status": "error", "error": error.localizedDescription]
        self.persistLocalRuntimeState()
      }
      return
    }
    labServerProcess = process

    // 等就緒（最多 60s，大模型載入較久）
    DispatchQueue.global(qos: .userInitiated).async {
      var ready = false
      for _ in 0..<120 {
        Thread.sleep(forTimeInterval: 0.5)
        if !process.isRunning { break }
        if self.isServerReady(port: 18799) { ready = true; break }
      }
      DispatchQueue.main.async {
        self.localRuntimeState["labServer"] = [
          "modelId": modelId,
          "status": ready ? "running" : (process.isRunning ? "timeout" : "crashed"),
          "port": 18799,
        ]
        self.persistLocalRuntimeState()
        print("[LocalRuntimeAudit] labServer \(ready ? "ready" : "failed") modelId=\(modelId)")
      }
    }
  }

  private func stopLabServer() {
    if let p = labServerProcess, p.isRunning {
      p.terminate()
      p.waitUntilExit()
    }
    labServerProcess = nil
    localRuntimeState.removeValue(forKey: "labServer")
  }

  private func isServerReady(port: Int) -> Bool {
    let url = URL(string: "http://127.0.0.1:\(port)/health")!
    var request = URLRequest(url: url)
    request.timeoutInterval = 2
    let semaphore = DispatchSemaphore(value: 0)
    var ready = false
    URLSession.shared.dataTask(with: request) { _, response, _ in
      if let resp = response as? HTTPURLResponse, resp.statusCode == 200 {
        ready = true
      }
      semaphore.signal()
    }.resume()
    semaphore.wait()
    return ready
  }

  /// 送測試請求
  private func sendTestRequest(port: Int, prompt: String) -> (success: Bool, response: String, latencyMs: Int, error: String) {
    let url = URL(string: "http://127.0.0.1:\(port)/v1/chat/completions")!
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.timeoutInterval = 30

    let body: [String: Any] = [
      "messages": [["role": "user", "content": prompt]],
      "max_tokens": 200,
      "temperature": 0.7,
      "chat_template_kwargs": ["enable_thinking": false], // [小葵 2026-07-22] Qwen3.5-4B thinking mode 修復
    ]
    request.httpBody = try? JSONSerialization.data(withJSONObject: body)

    let semaphore = DispatchSemaphore(value: 0)
    var responseData: Data?
    var responseError: Error?
    let startTime = Date()

    URLSession.shared.dataTask(with: request) { data, _, error in
      responseData = data
      responseError = error
      semaphore.signal()
    }.resume()
    semaphore.wait()

    let latencyMs = Int(Date().timeIntervalSince(startTime) * 1000)

    if let error = responseError {
      return (false, "", latencyMs, "請求失敗：\(error.localizedDescription)")
    }
    guard let data = responseData,
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let choices = json["choices"] as? [[String: Any]],
          let message = choices.first?["message"] as? [String: Any],
          let content = message["content"] as? String else {
      return (false, "", latencyMs, "無法解析回應")
    }
    return (true, content, latencyMs, "")
  }

  /// 儲存測試結果到 manifest.json
  private func saveTestResult(modelId: String, passed: Bool, response: String? = nil, latencyMs: Int? = nil, error: String? = nil) {
    guard let root = localRuntimeRootDirectory() else { return }
    let manifestURL = root.appendingPathComponent("models", isDirectory: true)
                          .appendingPathComponent(modelId, isDirectory: true)
                          .appendingPathComponent("manifest.json")
    guard var manifest = try? JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as? [String: Any] else { return }

    var testResult: [String: Any] = [
      "passed": passed,
      "testedAt": ISO8601DateFormatter().string(from: Date()),
    ]
    if let r = response { testResult["response"] = r }
    if let l = latencyMs { testResult["latencyMs"] = l }
    if let e = error { testResult["error"] = e }
    manifest["testResult"] = testResult
    manifest["testedAt"] = ISO8601DateFormatter().string(from: Date())

    if let data = try? JSONSerialization.data(withJSONObject: manifest, options: .prettyPrinted) {
      try? data.write(to: manifestURL)
    }
  }

  /// [小葵 2026-07-20] 列出硬碟上已安裝的模型（掃描 models/ 目錄）
  /// 回傳 [[modelId: String, fileSize: Int64, fileName: String]]
  /// 同時自動清理不完整的殘留檔案
  private func listInstalledLocalModels() -> [[String: Any]] {
    guard let root = localRuntimeRootDirectory() else { return [] }
    let modelsDir = root.appendingPathComponent("models", isDirectory: true)
    guard FileManager.default.fileExists(atPath: modelsDir.path) else { return [] }

    var installed: [[String: Any]] = []
    guard let entries = try? FileManager.default.contentsOfDirectory(atPath: modelsDir.path) else { return [] }

    for entry in entries {
      let modelDir = modelsDir.appendingPathComponent(entry, isDirectory: true)
      var isDir: ObjCBool = false
      guard FileManager.default.fileExists(atPath: modelDir.path, isDirectory: &isDir), isDir.boolValue else { continue }

      guard let files = try? FileManager.default.contentsOfDirectory(atPath: modelDir.path) else { continue }
      var hasCompleteGguf = false
      var hasPartial = false
      var ggufSize: Int64 = 0
      var ggufName = ""
      for f in files {
        if f.hasSuffix(".gguf") {
          let filePath = modelDir.appendingPathComponent(f)
          let attrs = try? FileManager.default.attributesOfItem(atPath: filePath.path)
          let size = (attrs?[.size] as? Int64) ?? 0
          if size > 1024 * 1024 {
            // 完整模型（>1MB）
            hasCompleteGguf = true
            ggufSize = size
            ggufName = f
          } else {
            // 不完整的 .gguf（<=1MB）— 清理
            try? FileManager.default.removeItem(at: modelDir)
          }
        } else if f.hasSuffix(".part") {
          hasPartial = true
        }
      }
      if hasCompleteGguf {
        // 讀取 manifest.json 裡的測試結果
        let manifestPath = modelDir.appendingPathComponent("manifest.json")
        var testPassed: Bool? = nil
        var testResponse: String? = nil
        var testLatencyMs: Int? = nil
        if let manifestData = try? Data(contentsOf: manifestPath),
           let manifest = try? JSONSerialization.jsonObject(with: manifestData) as? [String: Any],
           let testResult = manifest["testResult"] as? [String: Any] {
          testPassed = testResult["passed"] as? Bool
          testResponse = testResult["response"] as? String
          testLatencyMs = testResult["latencyMs"] as? Int
        }
        var entry: [String: Any] = [
          "modelId": entry,
          "fileSize": ggufSize,
          "fileName": ggufName,
        ]
        if let tp = testPassed { entry["testPassed"] = tp }
        if let tr = testResponse { entry["testResponse"] = tr }
        if let tl = testLatencyMs { entry["testLatencyMs"] = tl }
        installed.append(entry)
      } else if hasPartial {
        // 殘留 .part — 清理
        try? FileManager.default.removeItem(at: modelDir)
      }
    }
    return installed
  }

  /// [小葵 2026-07-20] 刪除已下載的模型檔案
  private func deleteLocalModel(modelId: String) {
    guard let root = localRuntimeRootDirectory() else { return }
    let modelDir = root.appendingPathComponent("models", isDirectory: true)
                        .appendingPathComponent(modelId, isDirectory: true)
    // 如果 server 正在跑且使用此模型，先停止
    if localRuntimeProcess?.isRunning == true {
      localRuntimeProcess?.terminate()
      localRuntimeProcess = nil
    }
    // 刪除整個模型目錄
    if FileManager.default.fileExists(atPath: modelDir.path) {
      try? FileManager.default.removeItem(at: modelDir)
    }
    // 刪除任務檔案
    let taskURL = root.appendingPathComponent("tasks", isDirectory: true)
                       .appendingPathComponent("\(modelId).download.json")
    if FileManager.default.fileExists(atPath: taskURL.path) {
      try? FileManager.default.removeItem(at: taskURL)
    }
    // 更新狀態
    localRuntimeState["phase"] = "installed"
    localRuntimeState["detail"] = "模型 \(modelId) 已刪除。"
    localRuntimeState["primaryCommand"] = "downloadModel"
    localRuntimeState["primaryActionLabel"] = "下載推薦模型"
    localRuntimeState["primaryActionEnabled"] = true
    localRuntimeState.removeValue(forKey: "modelId")
    localRuntimeState.removeValue(forKey: "modelFilePath")
    localRuntimeState.removeValue(forKey: "taskId")
    persistLocalRuntimeState()
  }

  private func stopLocalRuntimeServer() {
    // [小葵 2026-10-05 Blue 令·開關要真的能關] 原設計只停 localRuntimeProcess
    // （App 自己 spawn 的 handle）。App 重啟後 handle 丟失 → 孤兒引擎
    // （父進程=launchd）永遠關不掉——「停止本地 server」按了等於沒按。
    // 修：自己有 handle 就 terminate；沒有但 18789 有引擎在跑 = 孤兒 →
    // pkill 獵殺（launchd 常駐已退役，孤兒不該活）。
    if localRuntimeProcess?.isRunning == true {
      localRuntimeProcess?.terminate()
    } else {
      let orphanKiller = Process()
      orphanKiller.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
      orphanKiller.arguments = ["-f", "LocalRuntime/runtime/bin/llama-server"]
      try? orphanKiller.run()
      orphanKiller.waitUntilExit()
    }
    localRuntimeProcess = nil
    localRuntimeState["phase"] = "installed"
    localRuntimeState["detail"] = "本地模型 server 已停止。"
    localRuntimeState["primaryCommand"] = "startServer"
    localRuntimeState["primaryActionLabel"] = "啟動本地 server"
    localRuntimeState["primaryActionEnabled"] = true
    localRuntimeState.removeValue(forKey: "engineSource")
  }

  private func refreshLocalRuntimeProcessState() {
    if localRuntimeProcess?.isRunning == true {
      localRuntimeState["phase"] = "running"
      localRuntimeState["detail"] = "本地模型 server 已在 http://127.0.0.1:18789 運行。"
      localRuntimeState["primaryCommand"] = "stopServer"
      localRuntimeState["primaryActionLabel"] = "停止本地 server"
      localRuntimeState["primaryActionEnabled"] = true
      localRuntimeState["serverUrl"] = "http://127.0.0.1:18789"
    }
  }

  private func localRuntimePreflight() -> (executableURL: URL?, modelURL: URL?, expectedExecutablePath: String, expectedModelPath: String?) {
    let root = localRuntimeRootDirectory()
    let executableURL = resolvedRuntimeExecutableURL(root: root)
    let modelId = localRuntimeState["modelId"] as? String
    let modelURL = modelId.flatMap { resolvedModelFileURL(modelId: $0) } ?? firstAvailableModelFileURL(root: root)
    let expectedExecutablePath = expectedRuntimeExecutablePath(root: root)
    let expectedModelPath = modelURL?.path ?? expectedModelFileURL(modelId: modelId)?.path
    return (executableURL, modelURL, expectedExecutablePath, expectedModelPath)
  }

  private func expectedRuntimeExecutablePath(root: URL? = nil) -> String {
    let runtimeRoot = root ?? localRuntimeRootDirectory()
    return runtimeRoot?
      .appendingPathComponent("runtime", isDirectory: true)
      .appendingPathComponent("bin", isDirectory: true)
      .appendingPathComponent("llama-server")
      .path ?? "~/Library/Application Support/Bridge/LocalRuntime/runtime/bin/llama-server"
  }

  /// [小葵 2026-07-21] 移除 bin/ 目錄下所有檔案的 quarantine 屬性
  /// macOS Gatekeeper 會阻止執行從網路下載的二進位檔案
  /// 沙盒內 removexattr() 無法移除 com.apple.quarantine（靜默失敗）
  /// 改用 Process 執行 /usr/bin/xattr -cr（系統 binary 沙盒允許）
  private func removeQuarantineFromBin(binRoot: URL) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/bin/sh")
    p.arguments = ["-c", "/usr/bin/xattr -cr \"\(binRoot.path)\""]
    do {
      try p.run()
      p.waitUntilExit()
      // [小葵 2026-07-21] 檢查 xattr exit code；非零時 fallback 到 C API
      if p.terminationStatus != 0 {
        NSLog("[LocalRuntime] xattr -cr exit=\(p.terminationStatus), falling back to removexattr")
        if let dirContents = try? FileManager.default.contentsOfDirectory(at: binRoot, includingPropertiesForKeys: nil) {
          for file in dirContents {
            removexattr(file.path, "com.apple.quarantine", 0)
            removexattr(file.path, "com.apple.provenance", 0)
          }
        }
      }
    } catch {
      NSLog("[LocalRuntime] xattr Process.run failed: \(error), falling back to removexattr")
      // fallback: 嘗試 C API（可能失敗但不影響流程）
      if let dirContents = try? FileManager.default.contentsOfDirectory(at: binRoot, includingPropertiesForKeys: nil) {
        for file in dirContents {
          removexattr(file.path, "com.apple.quarantine", 0)
          removexattr(file.path, "com.apple.provenance", 0)
        }
      }
    }
  }

  /// [小葵 2026-07-20] 從 dylib 檔名讀取已安裝的 llama.cpp 版本號
  /// dylib 命名格式：libllama.0.0.10069.dylib → 版本 b10069
  private func readInstalledRuntimeVersion() -> String? {
    guard let root = localRuntimeRootDirectory() else { return nil }
    let binDir = root.appendingPathComponent("runtime/bin")
    if let files = try? FileManager.default.contentsOfDirectory(atPath: binDir.path) {
      for file in files where file.hasPrefix("libllama.") && file.hasSuffix(".dylib") && !file.contains("-") {
        // libllama.0.0.10069.dylib → 10069
        let parts = file.replacingOccurrences(of: "libllama.", with: "")
                         .replacingOccurrences(of: ".dylib", with: "")
                         .split(separator: ".")
        if let lastPart = parts.last, let buildNum = Int(lastPart) {
          return "b\(buildNum)"
        }
      }
    }
    // Fallback: read from install plan
    let planURL = root.appendingPathComponent("runtime/llama-cpp-install-plan.json")
    if let plan = readJSONObject(from: planURL),
       let version = plan["version"] as? String {
      return version
    }
    return nil
  }

  /// [小葵 2026-07-20] 寫入安裝版本資訊
  private func writeRuntimeVersion(_ version: String) {
    guard let root = localRuntimeRootDirectory() else { return }
    let plan: [String: Any] = [
      "version": version,
      "installedAt": ISO8601DateFormatter().string(from: Date()),
    ]
    writeJSONObject(plan, to: root.appendingPathComponent("runtime/llama-cpp-install-plan.json"))
  }

  private func resolvedRuntimeExecutableURL(root: URL?) -> URL? {
    // [小葵 2026-07-30] 修復：加入系統安裝的 llama-server 路徑作為 fallback
    // Homebrew 安裝的 llama-server 在 /opt/homebrew/bin/llama-server（Apple Silicon）
    var candidates: [URL] = []
    if let root {
      candidates.append(root.appendingPathComponent("runtime", isDirectory: true).appendingPathComponent("bin", isDirectory: true).appendingPathComponent("llama-server"))
      candidates.append(root.appendingPathComponent("runtime", isDirectory: true).appendingPathComponent("bin", isDirectory: true).appendingPathComponent("llama.cpp", isDirectory: true).appendingPathComponent("llama-server"))
    }
    // [小葵 2026-07-30] 系統級 fallback：Homebrew Apple Silicon 路徑
    candidates.append(URL(fileURLWithPath: "/opt/homebrew/bin/llama-server"))
    // [小葵 2026-07-30] 系統級 fallback：Homebrew Intel 路徑
    candidates.append(URL(fileURLWithPath: "/usr/local/bin/llama-server"))
    for candidate in candidates {
      // [小葵 2026-07-21] 沙盒內 isExecutableFile() 和 access(X_OK) 都會因
      // com.apple.provenance 屬性回傳 false。只檢查檔案存在，讓 Process.run() 驗證。
      if FileManager.default.fileExists(atPath: candidate.path) {
        return candidate
      }
    }
    return nil
  }

  private func resolvedModelFileURL(modelId: String) -> URL? {
    guard let root = localRuntimeRootDirectory() else {
      return nil
    }
    let modelDirectory = root.appendingPathComponent("models", isDirectory: true).appendingPathComponent(modelId, isDirectory: true)

    // [小葵 2026-07-25] 優先從 manifest 的 modelFilePath 或 source.fileName 取得檔名
    let manifestURL = modelDirectory.appendingPathComponent("manifest.json")
    let manifest = readJSONObject(from: manifestURL) ?? [:]
    let source = manifest["source"] as? [String: Any] ?? [:]

    // 嘗試 manifest 裡的各種欄位
    var fileName = source["fileName"] as? String
    if fileName == nil {
      // manifest 裡的 modelFilePath（完整路徑）取最後一段
      if let modelFilePath = manifest["modelFilePath"] as? String {
        fileName = (modelFilePath as NSString).lastPathComponent
      }
    }

    if let fn = fileName {
      let modelURL = modelDirectory.appendingPathComponent(fn)
      if FileManager.default.fileExists(atPath: modelURL.path) {
        return modelURL
      }
    }

    // [小葵 2026-07-25] fallback：掃描目錄找 .gguf 檔案（>1MB 才算完整）
    if let files = try? FileManager.default.contentsOfDirectory(atPath: modelDirectory.path) {
      for f in files where f.hasSuffix(".gguf") {
        let candidate = modelDirectory.appendingPathComponent(f)
        let attrs = try? FileManager.default.attributesOfItem(atPath: candidate.path)
        let size = (attrs?[.size] as? Int64) ?? 0
        if size > 1024 * 1024 {
          return candidate
        }
      }
    }

    return nil
  }

  private func expectedModelFileURL(modelId: String?) -> URL? {
    guard let root = localRuntimeRootDirectory(),
          let modelId = modelId,
          !modelId.isEmpty
    else {
      return nil
    }
    let modelDirectory = root.appendingPathComponent("models", isDirectory: true).appendingPathComponent(modelId, isDirectory: true)
    let manifestURL = modelDirectory.appendingPathComponent("manifest.json")
    let manifest = readJSONObject(from: manifestURL) ?? [:]
    let source = manifest["source"] as? [String: Any] ?? [:]
    let fileName = source["fileName"] as? String ?? "\(modelId).gguf"
    return modelDirectory.appendingPathComponent(fileName)
  }

  private func activeLocalModelName(modelURL: URL) -> String {
    let manifestURL = modelURL.deletingLastPathComponent().appendingPathComponent("manifest.json")
    let manifest = readJSONObject(from: manifestURL) ?? [:]
    if let name = manifest["name"] as? String, !name.isEmpty {
      return name
    }
    if let modelId = manifest["modelId"] as? String, !modelId.isEmpty {
      return modelId
    }
    return modelURL.deletingPathExtension().lastPathComponent
  }

  private func firstAvailableModelFileURL(root: URL?) -> URL? {
    guard let modelsRoot = root?.appendingPathComponent("models", isDirectory: true),
          let enumerator = FileManager.default.enumerator(at: modelsRoot, includingPropertiesForKeys: nil)
    else {
      return nil
    }
    for case let url as URL in enumerator {
      if url.pathExtension.lowercased() == "gguf" {
        return url
      }
    }
    return nil
  }

  private func restoreLocalRuntimeState() {
    guard let root = localRuntimeRootDirectory() else {
      return
    }
    let stateURL = root.appendingPathComponent("runtime-state.json")
    if let state = readJSONObject(from: stateURL) {
      localRuntimeState.merge(state) { _, new in new }
    }
    // [小葵 2026-08-13] 驗證 running 狀態——如果 port 18789 沒有 server，
    // 降級為 installed，讓 APP 重新啟動 server
    if let phase = localRuntimeState["phase"] as? String, phase == "running" {
      if !isPort18789Alive() {
        NSLog("[LocalRuntime] restoreLocalRuntimeState: phase=running 但 port 18789 沒有 server，降級為 installed")
        localRuntimeState["phase"] = "installed"
        localRuntimeState["detail"] = "本地模型 server 尚未啟動。"
        localRuntimeState["primaryCommand"] = "startServer"
        localRuntimeState["primaryActionLabel"] = "啟動本地 server"
        localRuntimeState["primaryActionEnabled"] = true
        localRuntimeState["serverHealthy"] = false
        persistLocalRuntimeState()
      }
    }
  }

  /// [小葵 2026-08-13] 快速檢查 port 18789 是否有 server 在跑
  private func isPort18789Alive() -> Bool {
    let socketFD = socket(AF_INET, SOCK_STREAM, 0)
    guard socketFD >= 0 else { return false }

    var addr = sockaddr_in()
    addr.sin_family = sa_family_t(AF_INET)
    addr.sin_port = UInt16(18789).bigEndian
    addr.sin_addr.s_addr = inet_addr("127.0.0.1")

    let result = withUnsafePointer(to: &addr) { ptr in
      ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
        Darwin.connect(socketFD, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
      }
    }
    Darwin.close(socketFD)
    return result == 0
  }

  private func persistLocalRuntimeState() {
    _ = prepareLocalRuntimeStorage()
    guard let root = localRuntimeRootDirectory() else {
      return
    }
    writeJSONObject(localRuntimeState, to: root.appendingPathComponent("runtime-state.json"))
  }

  private func writeCurrentDownloadTaskId(_ taskId: String) {
    guard let root = localRuntimeRootDirectory() else {
      return
    }
    writeJSONObject(["currentDownloadTaskId": taskId], to: root.appendingPathComponent("current-task.json"))
  }

  private func readJSONObject(from url: URL) -> [String: Any]? {
    guard let data = try? Data(contentsOf: url),
          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
      return nil
    }
    return object
  }

  private func writeJSONObject(_ object: [String: Any], to url: URL) {
    guard JSONSerialization.isValidJSONObject(object),
          let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
    else {
      return
    }
    try? data.write(to: url, options: [.atomic])
  }

  private func syncRuntime(payload: [String: Any]) {
    let runtime = payload["runtime"] as? [String: Any] ?? [:]
    if let name = runtime["activeCompanionName"] as? String {
      desktopShellState["companionName"] = name
    }
    if let role = runtime["activeCompanionRole"] as? String {
      desktopShellState["companionRole"] = role
    }
    if let statusText = runtime["statusText"] as? String {
      desktopShellState["statusText"] = statusText
    }
    if let imagePath = runtime["companionImagePath"] as? String {
      desktopShellState["companionImagePath"] = imagePath
    }
    if let videoPath = runtime["companionVideoPath"] as? String {
      desktopShellState["companionVideoPath"] = videoPath
    }
    // [小葵 2026-09-12] rig 活體——這兩個 key 先前沒搬進來，rig 永遠不會啟動
    if let rigState = runtime["rigStateId"] as? String {
      desktopShellState["rigStateId"] = rigState
    }
    desktopShellState["activeCompanionName"] = runtime["activeCompanionName"] ?? ""
    desktopShellState["runtimeSynced"] = true
    desktopShellState["lastAction"] = "syncRuntime"
    let currentCount = desktopShellState["commandCount"] as? Int ?? 0
    desktopShellState["commandCount"] = currentCount + 1
    // [小葵 2026-08-13] 只更新 runtime 資料，不重設 panel size
    // 舊做法呼叫 apply(state:) → configure → setContentSize，會把用戶拉大的面板重置
    desktopCompanionPanel.applyRuntimeOnly(state: desktopShellState)
  }

  private func nativeActionName(for commandId: String) -> String {
    switch commandId {
    case "runtime.subscribe":
      return "runtimeSubscribe"
    case "window.shape":
      return "configureTransparentWindow"
    case "window.drag-anchor":
      return "configureDragAnchor"
    case "window.wander-loop":
      return "configureWanderLoop"
    case "window.always-on-top":
      return "configureAlwaysOnTop"
    case "tray.install":
      return "installStatusItem"
    case "login-item.configure":
      return "configureLoginItem"
    default:
      return "unknown"
    }
  }
}

private final class DesktopCompanionPanelController {
  private var panel: NSPanel?
  private let companionView = DesktopCompanionPanelView()

  func apply(state: [String: Any]) {
    let panel = ensurePanel(state: state)
    configure(panel: panel, state: state)
  }

  /// [小葵 2026-08-13] 只更新 runtime 資料（name, status, image），不動 panel size
  /// 用於 syncRuntime —— AI 思考時頻繁呼叫，不能重設用戶拉大的面板尺寸
  func applyRuntimeOnly(state: [String: Any]) {
    let panel = ensurePanel(state: state)
    // 只更新 view，不呼叫 configure（configure 裡有 setContentSize）
    companionView.setRuntime(
      name: stringValue(state["companionName"], fallback: "Bridge Companion"),
      role: stringValue(state["companionRole"], fallback: "橋樑代理人"),
      statusText: stringValue(state["statusText"], fallback: "自由待機"),
      imagePath: state["companionImagePath"] as? String,
      companionName: stringValue(state["activeCompanionName"], fallback: ""),
      stateId: stringValue(state["rigStateId"], fallback: "idle"),
      videoPath: state["companionVideoPath"] as? String
    )
    // [小葵 2026-09-30 根修] 移除「不可見就強制開窗」——
    // 使用者關閉懸浮窗是明確意志；每 6 秒的 idle 輪播推送會把關掉的窗反覆打開。
    // 現在：隱藏時推送只更新內部狀態（下次 show 時內容已是最新）。
    // 只有 Dart 端明確 lifecycle('show') 才開窗（ensurePanel 在 show 路徑）。
  }

  func show(state: [String: Any]) {
    let panel = ensurePanel(state: state)
    configure(panel: panel, state: state)
    // [W4.6 Blue 報案 2026-10-09] watchdog/launchd 背景拉起的 App——
    // orderFrontRegardless 對非前景 app 不浮現（macOS 規定）。
    // 修：show 時把 app 帶到前台 context（不搶焦點——ignoresOtherWindows），
    // panel 才畫得出來。前景路徑行為不變。
    NSApp.activate(ignoringOtherApps: false)
    panel.orderFrontRegardless()
  }

  func hide() {
    panel?.orderOut(nil)
  }

  func pause(state: [String: Any]) {
    companionView.setPaused(true)
    apply(state: state)
  }

  func resume(state: [String: Any]) {
    companionView.setPaused(false)
    show(state: state)
  }

  func snapshot(base: [String: Any]) -> [String: Any] {
    var next = base
    if let panel {
      next["visible"] = panel.isVisible
      next["width"] = panel.frame.width
      next["height"] = panel.frame.height
    }
    return next
  }

  private func ensurePanel(state: [String: Any]) -> NSPanel {
    if let panel {
      return panel
    }

    let width = doubleValue(state["width"], fallback: 320)
    let height = doubleValue(state["height"], fallback: 400)
    let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 80, y: 80, width: 1200, height: 800)
    // [小葵 2026-08-12] 預設位置改為左下角（macOS 版本，Windows 留在原處）
    let origin = NSPoint(
      x: screenFrame.minX + 48,
      y: screenFrame.minY + 96
    )
    let panel = NSPanel(
      contentRect: NSRect(x: origin.x, y: origin.y, width: width, height: height),
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )
    panel.contentView = companionView
    panel.isReleasedWhenClosed = false
    panel.hidesOnDeactivate = false
    panel.hasShadow = false
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    panel.isMovableByWindowBackground = true
    panel.isMovable = true
    // [小葵 2026-08-11] nonactivatingPanel + borderless，不需先點擊啟動
    panel.styleMask = [.borderless, .nonactivatingPanel]
    // [小葵 2026-08-11] 關鍵：切換 App 頁面後不需先點擊「選取」面板就能直接拖曳
    // becomesKeyOnlyIfNeeded = true 讓面板不會搶走 key window 狀態
    // 主視窗保持 key，但面板仍可直接 performDrag
    panel.becomesKeyOnlyIfNeeded = true
    panel.acceptsMouseMovedEvents = true
    panel.hidesOnDeactivate = false
    panel.titleVisibility = .hidden
    panel.titlebarAppearsTransparent = true
    configure(panel: panel, state: state)
    self.panel = panel
    return panel
  }

  private func configure(panel: NSPanel, state: [String: Any]) {
    let width = doubleValue(state["width"], fallback: panel.frame.width)
    let height = doubleValue(state["height"], fallback: panel.frame.height)
    let transparent = boolValue(state["transparent"], fallback: true)
    let alwaysOnTop = boolValue(state["alwaysOnTop"], fallback: false)
    let draggable = boolValue(state["draggable"], fallback: true)
    let paused = boolValue(state["paused"], fallback: false)

    panel.setContentSize(NSSize(width: width, height: height))
    panel.isOpaque = !transparent
    panel.backgroundColor = transparent ? .clear : .windowBackgroundColor
    panel.level = alwaysOnTop ? .floating : .normal
    panel.isMovableByWindowBackground = draggable
    companionView.setPaused(paused)
    companionView.setRuntime(
      name: stringValue(state["companionName"], fallback: "Bridge Companion"),
      role: stringValue(state["companionRole"], fallback: "橋樑代理人"),
      statusText: stringValue(state["statusText"], fallback: "自由待機"),
      imagePath: state["companionImagePath"] as? String,
      companionName: stringValue(state["activeCompanionName"], fallback: ""),
      stateId: stringValue(state["rigStateId"], fallback: "idle"),
      videoPath: state["companionVideoPath"] as? String
    )
  }

  private func boolValue(_ value: Any?, fallback: Bool) -> Bool {
    return value as? Bool ?? fallback
  }

  private func doubleValue(_ value: Any?, fallback: Double) -> Double {
    if let value = value as? Double {
      return value
    }
    if let value = value as? Int {
      return Double(value)
    }
    if let value = value as? CGFloat {
      return Double(value)
    }
    return fallback
  }

  private func stringValue(_ value: Any?, fallback: String) -> String {
    return value as? String ?? fallback
  }
}

private final class DesktopCompanionPanelView: NSView {
  // [小葵 2026-09-12] 翻轉容器：rig 的 y-down 佈局鏈（panel root → avatarView → rigView）
  private final class FlippedView: NSView { override var isFlipped: Bool { true } }
  private let avatarView = FlippedView()
  private let companionImageView = NSImageView()
  // [小葵 2026-09-24 出道令 v2] 循環影片＋cyan 去背（ChromaKeyPlayerView）
  private var chromaVideoView: ChromaKeyPlayerView?

  private var playingVideoPath: String? = nil
  // [小葵 2026-09-24 出道令] 雙緩衝換片：新片疊在舊片下，首幀渲染好才退役舊片——零黑幀
  private var retiringVideoViews: [ChromaKeyPlayerView] = []
  private func playVideo(path: String) {
    // [小葵 2026-10-02 根修] 播影片前先清空靜態頭像層——
    // 症狀：切到別的夥伴（載入其靜態圖+呼吸帶）再切回有動圖的夥伴時，
    // 舊夥伴的立繪/呼吸帶 z-order 在影片之上，把動圖蓋住。
    // 影片成功接手畫面後靜態層本來就不該存在——清圖、停帶、停呼吸動畫。
    _clearStaticAvatar()
    // [出道令] 同一支影片已在播→不重啟（避免狀態推送閃跳）
    if playingVideoPath == path, let v = chromaVideoView, v.isPlaying { return }
    let old = chromaVideoView
    if let oldV = old {
      // [小葵 2026-09-30 根修] 舊 view 進退役名單「同時立刻停掉它的 display link」——
      // 舊幀已上螢幕不會消失（layer 內容保留），但不再每秒 60 次 renderFrame。
      // 原設計等 onFirstFrame 才停：鏈條斷裂（首幀未達+guard 失敗）就永久洩漏。
      oldV.stopDisplayLink()
      retiringVideoViews.append(oldV)
    }
    // 影片自帶 alpha（cyan→透明）——新 view 先放舊 view 之下載入
    let view = ChromaKeyPlayerView(frame: avatarView.bounds)
    view.autoresizingMask = [.width, .height]
    if let oldV = old {
      avatarView.addSubview(view, positioned: .below, relativeTo: oldV)
    } else {
      avatarView.addSubview(view)
    }
    chromaVideoView = view
    playingVideoPath = path
    // 首幀抵達 → 退役所有舊 view（此後畫面由新片接手，無縫）
    view.onFirstFrame = { [weak self, weak view] in
      guard let self = self, let view = view else { return }
      guard self.chromaVideoView === view else { return } // 又被更新的片取代→交給它清
      for r in self.retiringVideoViews { r.stop(); r.removeFromSuperview() }
      self.retiringVideoViews.removeAll()
    }
    // 保險：2 秒內首幀沒到（罕見解碼失敗）也強制換血，避免殭屍舊片疊著
    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self, weak view] in
      guard let self = self, let view = view else { return }
      guard self.chromaVideoView === view else { return }
      for r in self.retiringVideoViews { r.stop(); r.removeFromSuperview() }
      self.retiringVideoViews.removeAll()
    }
    view.playLoop(path: path)
  }

  private func stopVideoPlayback() {
    ChromaKeyPlayerView.stopAllDisplayLinks() // [小葵 2026-09-30 根修] 先砍所有殘留 link
    chromaVideoView?.stop()
    chromaVideoView?.removeFromSuperview()
    chromaVideoView = nil
    for r in retiringVideoViews { r.stop(); r.removeFromSuperview() }
    retiringVideoViews.removeAll()
    playingVideoPath = nil
  }
  // [小葵 2026-09-12] 活體 rig——有素材的夥伴用四層動畫蓋過靜態圖
  private let rigView = CompanionRigView(frame: .zero)
  private var rigActive = false
  // [小葵 2026-09-13] 胸口呼吸覆蓋層：與靜態立繪同源裁切（_torso.png），疊在 companionImageView 上
  private let bandViews: [NSImageView] = [NSImageView(), NSImageView(), NSImageView()]
  private var torsoTimer: Timer?
  private var torsoT: Double = 0
  private let statusLabel = NSTextField(labelWithString: "Bridge Companion")
  private let modeLabel = NSTextField(labelWithString: "running")
  private let closeButton = NSButton()
  // [小葵 2026-08-12] 不攔截事件的 NSButton——用於 resize 鈕
  // mouseDownCanMoveWindow=false 讓 mouseDown 傳到我們的 handler
  private final class PassThroughButton: NSButton {
    override var mouseDownCanMoveWindow: Bool { false }
    override func mouseDown(with event: NSEvent) {
      // 不做任何事——讓 superview 的 mouseDown 處理
      self.nextResponder?.mouseDown(with: event)
    }
  }

  private let resizeHandle = PassThroughButton()
  private var resizeOrigin: NSPoint?
  private var resizeStartSize: NSSize?

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    layer?.backgroundColor = NSColor.clear.cgColor

    avatarView.wantsLayer = true
    avatarView.layer?.cornerRadius = 32
    avatarView.layer?.backgroundColor = NSColor.clear.cgColor
    avatarView.layer?.borderColor = NSColor.clear.cgColor
    avatarView.layer?.borderWidth = 0

    // [小葵 2026-08-11] 夥伴狀態圖——不攔截 mouseDown，讓拖曳零延遲
    companionImageView.wantsLayer = true
    companionImageView.imageScaling = .scaleProportionallyUpOrDown
    companionImageView.imageAlignment = .alignCenter
    companionImageView.allowsCutCopyPaste = false

    statusLabel.alignment = .center
    statusLabel.font = NSFont.systemFont(ofSize: 18, weight: .semibold)
    statusLabel.textColor = .white
    // [小葵 2026-08-12] 文字陰影——深色淺色背景都能看清楚
    statusLabel.wantsLayer = true
    statusLabel.layer?.shadowColor = NSColor.black.cgColor
    statusLabel.layer?.shadowOpacity = 0.8
    statusLabel.layer?.shadowRadius = 3
    statusLabel.layer?.shadowOffset = NSSize(width: 0, height: 1)

    modeLabel.alignment = .center
    modeLabel.font = NSFont.monospacedSystemFont(ofSize: 16, weight: .medium)
    modeLabel.textColor = .white
    modeLabel.wantsLayer = true
    modeLabel.layer?.shadowColor = NSColor.black.cgColor
    modeLabel.layer?.shadowOpacity = 0.8
    modeLabel.layer?.shadowRadius = 3
    modeLabel.layer?.shadowOffset = NSSize(width: 0, height: 1)

    // [小葵 2026-08-11] 關閉按鈕——白底黑線，圖標填滿
    closeButton.bezelStyle = .accessoryBarAction
    closeButton.image = NSImage(systemSymbolName: "xmark.circle", accessibilityDescription: "關閉")
    closeButton.contentTintColor = .black
    closeButton.isBordered = false
    closeButton.imagePosition = .imageOnly
    closeButton.imageScaling = .scaleProportionallyUpOrDown
    closeButton.wantsLayer = true
    closeButton.layer?.backgroundColor = NSColor.white.cgColor
    closeButton.layer?.cornerRadius = 9
    closeButton.layer?.shadowColor = NSColor.black.cgColor
    closeButton.layer?.shadowOpacity = 0.3
    closeButton.layer?.shadowRadius = 2
    closeButton.layer?.shadowOffset = NSSize(width: 0, height: 1)
    closeButton.target = self
    closeButton.action = #selector(closePanel)

    // [小葵 2026-08-12] 右下角 resize 把手——用 SF Symbol 跟關閉鈕一樣風格
    resizeHandle.bezelStyle = .accessoryBarAction
    resizeHandle.image = NSImage(systemSymbolName: "arrow.up.left.and.arrow.down.right.circle", accessibilityDescription: "縮放")
    resizeHandle.contentTintColor = .black
    resizeHandle.isBordered = false
    resizeHandle.imagePosition = .imageOnly
    resizeHandle.imageScaling = .scaleProportionallyUpOrDown
    resizeHandle.wantsLayer = true
    resizeHandle.layer?.backgroundColor = NSColor.white.cgColor
    resizeHandle.layer?.cornerRadius = 9
    resizeHandle.layer?.shadowColor = NSColor.black.cgColor
    resizeHandle.layer?.shadowOpacity = 0.3
    resizeHandle.layer?.shadowRadius = 2
    resizeHandle.layer?.shadowOffset = NSSize(width: 0, height: 1)

    addSubview(avatarView)
    addSubview(companionImageView)
    for bv in bandViews {
      bv.imageScaling = .scaleProportionallyUpOrDown
      addSubview(bv)  // [小葵 2026-09-13] 三帶覆蓋層（同源裁切，蓋在立繪上）
    }
    addSubview(statusLabel)
    addSubview(modeLabel)
    addSubview(closeButton)
    addSubview(resizeHandle)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  // [小葵 2026-08-11] 讓整個面板可以被拖曳——所有 subview 都允許 mouseDown 傳遞給 window
  override var mouseDownCanMoveWindow: Bool { true }

  // [小葵 2026-09-12] 面板根視圖翻轉為 y-down：layout() 的 textArea 在底、圖片在頂的
  // 佈局意圖才能正確實現（此前靜態圖時代上下相反但對稱看不出；rig 有頭腳方向後露餡）
  override var isFlipped: Bool { true }

  override func layout() {
    super.layout()
    // [小葵 2026-08-11] 簡單版：圖片佔面板上方大部分，文字在最下面
    let textAreaHeight: CGFloat = 70
    let imageHeight = bounds.height - textAreaHeight
    let imageSize = min(bounds.width, imageHeight)

    avatarView.frame = NSRect(
      x: (bounds.width - imageSize) / 2,
      y: textAreaHeight + (imageHeight - imageSize) / 2,
      width: imageSize,
      height: imageSize
    )
    let padding: CGFloat = 4
    // [小葵 2026-09-13] 胸口覆蓋層跟著立繪 frame 佈局（相對位置在 timer 裡精算）
    _layoutBands()
    companionImageView.frame = NSRect(
      x: avatarView.frame.minX + padding,
      y: avatarView.frame.minY + padding,
      width: imageSize - padding * 2,
      height: imageSize - padding * 2
    )
    // [小葵 2026-09-12] rigView 跟著同尺寸佈局（先前漏設 frame → rig 永遠 0x0）
    // [小葵 2026-09-12] rigView 鋪滿圖區（全寬×去掉底部文字列的高度）——
    // 正方形 avatarView 對全身圖構圖不利（寬度浪費、頭腳被擠）
    rigView.frame = NSRect(
      x: 0,
      y: 2,
      width: bounds.width,
      height: max(100, bounds.height - 68)
    )
    // [小葵 2026-09-12] 根視圖已翻轉 y-down：文字列放底部（statusLabel 上、modeLabel 下）
    statusLabel.frame = NSRect(
      x: 12,
      y: bounds.height - 46,
      width: bounds.width - 24,
      height: 26
    )
    modeLabel.frame = NSRect(
      x: 12,
      y: bounds.height - 22,
      width: bounds.width - 24,
      height: 22
    )
    closeButton.frame = NSRect(
      x: companionImageView.frame.maxX - 22,
      y: companionImageView.frame.minY + 4,
      width: 18,
      height: 18
    )
    resizeHandle.frame = NSRect(
      x: bounds.width - 22,
      y: bounds.height - 22,
      width: 18,
      height: 18
    )
  }

  func setPaused(_ paused: Bool) {
    modeLabel.stringValue = paused ? "paused" : "running"
  }

  func setRuntime(name: String, role: String, statusText: String, imagePath: String?, companionName: String = "", stateId: String = "idle", videoPath: String? = nil) {
    statusLabel.stringValue = name
    modeLabel.stringValue = "\(role) · \(statusText)"

    // ═══ [小葵 2026-09-24 出道令] 影片優先：companionVideoPath 有值 → AVPlayer 循環播放 ═══
    if let vp = videoPath, !vp.isEmpty {
      let expanded = vp.hasPrefix("~") ? (vp as NSString).expandingTildeInPath : vp
      if FileManager.default.fileExists(atPath: expanded) {
        playVideo(path: expanded)
        return
      }
    }
    stopVideoPlayback()  // 沒影片→停掉舊 player 回靜態圖鏈

    // [小葵 2026-09-13] Blue 拍板：動態 rig 封存，回歸靜態圖+呼吸感。
    // rig 架構保留（NSImageView v4 全部代碼與素材規格都在），重啟=把 rigEnabled 改 true。
    let rigEnabled = false  // [小葵 2026-09-13] rig 保持封存——胸口呼吸改走 torsoOverlay（靜態圖+覆蓋層）
    if rigEnabled, let geo = RigGeometry.forCompanion(companionName), !companionName.isEmpty {
      let assetDir = Self.rigAssetDir(for: geo.name)
      if FileManager.default.fileExists(atPath: assetDir.path + "/body_full.png") {
        if !rigActive {
          if companionImageView.superview != nil { companionImageView.removeFromSuperview() }
          if rigView.superview == nil {
            addSubview(rigView)  // 掛 panel root（y-down 翻轉鏈）鋪滿圖區
            rigView.frame = NSRect(x: 0, y: 2, width: bounds.width, height: max(100, bounds.height - 68))
            rigView.autoresizingMask = [.width, .height]
          }
          rigActive = true
        }
        rigView.load(geo: geo, assetDir: assetDir)
        rigView.setState(stateId)
        return
      }
    }
    // 沒有 rig 素材——退回靜態圖（原行為）
    if rigActive {
      rigView.removeFromSuperview()
      if companionImageView.superview == nil { avatarView.addSubview(companionImageView) }
      rigActive = false
    }

    // [小葵 2026-08-11 debug]
    print("[DesktopCompanionPanel] setRuntime: imagePath=\(imagePath ?? "nil")")

    // [小葵 2026-08-11] 載入夥伴狀態圖
    if let path = imagePath, !path.isEmpty {
      let expandedPath = path.hasPrefix("~")
        ? (path as NSString).expandingTildeInPath
        : path
      // [小葵 2026-08-31 v181 主執行緒解凍] 原同步 NSImage(contentsOfFile:)
      // 在 main thread 讀檔——sample 鐵證：懸浮面板 setRuntime 卡在
      // readBytesFromFile/_fcntl_overlay_open 數分鐘=AppleEvent/MCP 全堵死。
      // 改背景佇列解碼，main thread 只貼圖（失敗回彩色圓圈）。
      DispatchQueue.global(qos: .utility).async { [weak self] in
        let loaded = FileManager.default.fileExists(atPath: expandedPath)
          ? NSImage(contentsOfFile: expandedPath) : nil
        DispatchQueue.main.async {
          guard let self = self else { return }
          if let nsImage = loaded {
            self.companionImageView.image = nsImage
            self.avatarView.layer?.backgroundColor = NSColor.clear.cgColor
            self.avatarView.layer?.borderColor = NSColor.clear.cgColor
            self._startBandBreathing(path: expandedPath)  // [小葵 2026-09-13] 三帶覆蓋層呼吸
          } else {
            self._setDefaultAvatarColor()
          }
        }
      }
    } else {
      // 沒有圖片路徑——保持彩色圓圈
      companionImageView.image = nil
      _setDefaultAvatarColor()
    }
  }

  /// [小葵 2026-09-13 v3] 三帶覆蓋層呼吸：立繪完全不動，三條同源裁切帶以胸口錨點縮放，
  /// 振幅 1.0/0.4/0.1（Blue 三層分帶方案）。地籍=同目錄 _rigmap.json（相對座標 0-1）。
  private struct BandSpec {
    let from: CGFloat; let to: CGFloat; let amp: CGFloat
    // v2：矩形帶＋獨立圓心（rect 全 0 = v1 橫帶模式）
    let rectX: CGFloat; let rectY: CGFloat; let rectW: CGFloat; let rectH: CGFloat
    let cx: CGFloat; let cy: CGFloat
    var isRect: Bool { rectW > 0 }
  }
  private var bandSpecs: [BandSpec] = []
  private var bandAnchorY: CGFloat = 0.5
  private var bandAmp: CGFloat = 0.018
  private var bandSrcSize: CGSize = .zero

  private func _startBandBreathing(path: String) {
    let base = (path as NSString).deletingPathExtension
    // ① rigmap（新標準）
    if let data = FileManager.default.contents(atPath: base + "_rigmap.json"),
       let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
      let anchor = (obj["anchor"] as? [String: Any])?["y"] as? Double ?? 0.5
      let breath = obj["breath"] as? [String: Any]
      let amp = (breath?["amp"] as? Double) ?? 0.018
      var specs: [BandSpec] = []
      if let bands = obj["bands"] as? [[String: Any]] {
        for b in bands {
          let amp = CGFloat((b["amp"] as? Double) ?? 1.0)
          if let rect = b["rect"] as? [String: Any], let center = b["center"] as? [String: Any] {
            // v2 矩形帶：rect{x,y,w,h} + center{x,y}（各自獨立圓心）
            specs.append(BandSpec(from: 0, to: 0, amp: amp,
                                  rectX: CGFloat((rect["x"] as? Double) ?? 0),
                                  rectY: CGFloat((rect["y"] as? Double) ?? 0),
                                  rectW: CGFloat((rect["w"] as? Double) ?? 0),
                                  rectH: CGFloat((rect["h"] as? Double) ?? 0),
                                  cx: CGFloat((center["x"] as? Double) ?? 0.5),
                                  cy: CGFloat((center["y"] as? Double) ?? 0.5)))
          } else {
            // v1 橫帶（向後相容）
            specs.append(BandSpec(from: CGFloat((b["from"] as? Double) ?? 0),
                                  to: CGFloat((b["to"] as? Double) ?? 1),
                                  amp: amp, rectX: 0, rectY: 0, rectW: 0, rectH: 0,
                                  cx: 0.5, cy: bandAnchorY))
          }
        }
      }
      if !specs.isEmpty {
        bandAnchorY = CGFloat(anchor)
        bandAmp = CGFloat(amp)
        var loaded = 0
        for (i, bv) in bandViews.enumerated() {
          if i < specs.count, let img = NSImage(contentsOfFile: base + "_band\(i).png") {
            bv.image = img; bv.isHidden = false; loaded += 1
          } else {
            bv.image = nil; bv.isHidden = true
          }
        }
        if loaded > 0, let chk = NSImage(contentsOfFile: path) {
          bandSrcSize = chk.size
          bandSpecs = specs
          _layoutBands()
          if torsoTimer == nil {
            torsoTimer = Timer.scheduledTimer(withTimeInterval: 1.0/60.0, repeats: true) { [weak self] _ in
              guard let self = self else { return }
              self.torsoT += 1.0/60.0
              let breathe = 1.0 + Foundation.sin(self.torsoT * 0.7) * Double(self.bandAmp)
              self._layoutBands(breathe: CGFloat(breathe))
            }
          }
          return
        }
      }
    }
    // ② fallback：單帶 torso（v2）
    if FileManager.default.fileExists(atPath: base + "_torso.png"),
       let img = NSImage(contentsOfFile: base + "_torso.png") {
      bandViews[0].image = img; bandViews[0].isHidden = false
      for i in 1..<bandViews.count { bandViews[i].image = nil; bandViews[i].isHidden = true }
      bandAnchorY = 0.30
      bandAmp = 0.018
      bandSpecs = [BandSpec(from: 0.16, to: 0.57, amp: 1.0, rectX: 0, rectY: 0, rectW: 0, rectH: 0, cx: 0.5, cy: 0.30)]
      if let chk = NSImage(contentsOfFile: path) { bandSrcSize = chk.size }
      _layoutBands()
      if torsoTimer == nil {
        torsoTimer = Timer.scheduledTimer(withTimeInterval: 1.0/60.0, repeats: true) { [weak self] _ in
          guard let self = self else { return }
          self.torsoT += 1.0/60.0
          let breathe = 1.0 + Foundation.sin(self.torsoT * 0.7) * Double(self.bandAmp)
          self._layoutBands(breathe: CGFloat(breathe))
        }
      }
      return
    }
    // ③ fallback：整圖微縮
    _startBreathing()
  }

  /// 三帶佈局：每帶框 = 原圖座標映射 → 以胸口點乘上「帶振幅的縮放」
  private func _layoutBands(breathe: CGFloat = 1.0) {
    guard !bandSpecs.isEmpty, bandSrcSize.width > 0 else { return }
    let iv = companionImageView
    let ivF = iv.frame
    let scale = min(ivF.width / bandSrcSize.width, ivF.height / bandSrcSize.height)
    let dispW = bandSrcSize.width * scale, dispH = bandSrcSize.height * scale
    let dispX = ivF.minX + (ivF.width - dispW) / 2
    let dispY = ivF.minY + (ivF.height - dispH) / 2
    for (i, spec) in bandSpecs.enumerated() where i < bandViews.count {
      guard bandViews[i].image != nil else { continue }
      let b = 1.0 + (breathe - 1.0) * spec.amp   // 帶振幅係數
      let center: CGPoint
      var frame: NSRect
      if spec.isRect {
        // v2：矩形帶以「自己的圓心」縮放
        center = CGPoint(x: dispX + spec.cx * dispW, y: dispY + spec.cy * dispH)
        frame = NSRect(x: dispX + spec.rectX * dispW,
                       y: dispY + spec.rectY * dispH,
                       width: spec.rectW * dispW,
                       height: spec.rectH * dispH)
      } else {
        // v1：橫帶以胸口縮放
        center = CGPoint(x: dispX + dispW / 2, y: dispY + bandAnchorY * dispH)
        frame = NSRect(x: dispX,
                       y: dispY + spec.from * dispH,
                       width: dispW,
                       height: (spec.to - spec.from) * dispH)
      }
      frame = NSRect(x: center.x - (center.x - frame.minX) * b,
                     y: center.y - (center.y - frame.minY) * b,
                     width: frame.width * b,
                     height: frame.height * b)
      bandViews[i].frame = frame
    }
  }


  /// fallback：沒有 _torso.png 時整圖微縮（舊行為）
  private func _startBreathing() {
    companionImageView.wantsLayer = true
    guard let layer = companionImageView.layer else { return }
    if layer.animation(forKey: "breathing") != nil { return }
    let f = companionImageView.frame
    layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
    layer.position = CGPoint(x: f.midX, y: f.midY)
    let anim = CABasicAnimation(keyPath: "transform.scale")
    anim.fromValue = 1.0
    anim.toValue = 1.012
    anim.duration = 2.8
    anim.autoreverses = true
    anim.repeatCount = .infinity
    anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
    layer.add(anim, forKey: "breathing")
  }

  /// [小葵 2026-10-02 根修] 清空靜態頭像層——影片接手畫面時呼叫。
  /// 舊夥伴的立繪、三帶呼吸覆蓋層、整圖呼吸動畫全部退場，
  /// 避免殘影疊在動圖上方（症狀：切夥伴回來後動圖被蓋住）。
  private func _clearStaticAvatar() {
    // 立繪本體
    companionImageView.image = nil
    // 三帶呼吸覆蓋層：圖清掉、藏起來、停掉 60fps 帶動畫 timer
    for bv in bandViews {
      bv.image = nil
      bv.isHidden = true
    }
    torsoTimer?.invalidate()
    torsoTimer = nil
    bandSpecs = []
    // 整圖呼吸 layer 動畫
    companionImageView.layer?.removeAnimation(forKey: "breathing")
  }

  private func _setDefaultAvatarColor() {
    avatarView.layer?.backgroundColor = NSColor.clear.cgColor
    avatarView.layer?.borderColor = NSColor.clear.cgColor
  }

  /// rig 素材目錄：Flutter path_provider 寫到 App Support/<bundleId>/bridge_rig/<name>/
  /// Swift 的 applicationSupportDirectory 沒有 bundleId 子目錄——兩邊路徑不同，掃兩處
  static func rigAssetDir(for name: String) -> URL {
    let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    let flutterDir = support.appendingPathComponent("farm.semiwasabi.bridgeApp/bridge_rig/\(name)")
    if FileManager.default.fileExists(atPath: flutterDir.path + "/body_full.png") {
      return flutterDir
    }
    return support.appendingPathComponent("bridge_rig/\(name)")
  }

  @objc func closePanel() {
    self.window?.orderOut(nil)
  }

  // [小葵 2026-08-11] resize handle 拖曳——調整面板大小
  override func mouseDown(with event: NSEvent) {
    let point = self.convert(event.locationInWindow, from: nil)
    // 點到 resize handle → 調整大小；否則 → 拖曳視窗
    if resizeHandle.frame.contains(point) {
      resizeOrigin = NSEvent.mouseLocation
      resizeStartSize = self.window?.frame.size
    } else {
      self.window?.performDrag(with: event)
    }
  }

  override func mouseDragged(with event: NSEvent) {
    guard let origin = resizeOrigin,
          let startSize = resizeStartSize,
          let window = self.window else { return }

    let current = NSEvent.mouseLocation
    let dx = current.x - origin.x
    let dy = origin.y - current.y  // 往上拖 = 變大

    // [小葵 2026-08-12] 等比例縮放——以對角線變化量的最大值為準
    let delta = max(dx, dy)
    var newSize = startSize.width + delta

    // 最小尺寸限制——不能小於狀態文字寬度
    // statusLabel 18pt semibold + modeLabel 16pt，最長狀態約 180px
    let minPanelSize: CGFloat = 200
    newSize = max(minPanelSize, newSize)

    let frame = window.frame
    let newFrame = NSRect(
      x: frame.minX,
      y: frame.maxY - newSize,
      width: newSize,
      height: newSize
    )
    window.setFrame(newFrame, display: true, animate: false)
  }

  override func mouseUp(with event: NSEvent) {
    resizeOrigin = nil
    resizeStartSize = nil
  }
}

// [小葵 2026-07-21] URLSession 下載 delegate，取代 curl（沙盒內 curl 會寫入 orphan inode）
// [小葵 2026-07-21] 下載流程職責：本 delegate 負責【第 1 次搬檔】系統暫存 → .part。
// 暫存檔生命週期只到 didFinishDownloadingTo 回傳為止，所以搬移必須在這裡一步到位。
// 搬完後 onComplete 只傳結果（.part URL 或 error），接收方不得再搬檔案。
// 第 2 次搬檔（.part → 最終 .gguf）在 finishLocalModelDownload。全程僅這兩次。
class LocalModelDownloadDelegate: NSObject, URLSessionDownloadDelegate {
  var onProgress: ((Int64, Int64) -> Void)?
  var onComplete: ((URL?, Error?) -> Void)?
  var targetPath: String? // [小葵 2026-07-21] 直接移到目標 .part 檔案，避免暫存被系統刪除

  func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
    onProgress?(totalBytesWritten, totalBytesExpectedToWrite)
  }

  func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
    // [小葵 2026-07-21] 直接移到目標 .part 檔案，不要經過第二次暫存
    guard let targetPath = targetPath else {
      onComplete?(nil, NSError(domain: "LocalModelDownload", code: -1, userInfo: [NSLocalizedDescriptionKey: "targetPath not set"]))
      return
    }
    let targetURL = URL(fileURLWithPath: targetPath)
    do {
      // 確保目標資料夾存在
      try FileManager.default.createDirectory(
        at: targetURL.deletingLastPathComponent(),
        withIntermediateDirectories: true,
        attributes: nil
      )
      // 刪除舊的 .part（如果存在）
      if FileManager.default.fileExists(atPath: targetURL.path) {
        try FileManager.default.removeItem(at: targetURL)
      }
      // 直接移動（必須在 delegate 回傳前完成，否則 location 會被系統刪除）
      try FileManager.default.moveItem(at: location, to: targetURL)
      print("[LocalModelDownloadDelegate] 已移動下載檔案到: \(targetPath)")
      onComplete?(targetURL, nil)
    } catch {
      print("[LocalModelDownloadDelegate] 移動失敗: \(error.localizedDescription)")
      onComplete?(nil, error)
    }
  }

  func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
    if let error = error {
      onComplete?(nil, error)
    }
  }
}

// [小葵 2026-07-21] 清理舊暫存檔案
extension MainFlutterWindow {
  /// App 啟動時清理舊的 URLSession 暫存檔（.download、CFNetworkDownload_*.tmp）
  /// 避免下載失敗後暫存檔累積佔用空間
  func cleanupOldTemporaryFiles() {
    let tempDir = FileManager.default.temporaryDirectory
    let containerTempDir = URL(fileURLWithPath: NSHomeDirectory())
      .appendingPathComponent("Library/Containers/farm.semiwasabi.bridgeApp/Data/tmp")
    
    // 清理系統暫存區
    cleanupTempDirectory(tempDir)
    // 清理容器暫存區
    cleanupTempDirectory(containerTempDir)
  }
  
  private func cleanupTempDirectory(_ dir: URL) {
    guard FileManager.default.fileExists(atPath: dir.path) else { return }
    
    do {
      let contents = try FileManager.default.contentsOfDirectory(
        at: dir,
        includingPropertiesForKeys: [.fileSizeKey, .creationDateKey],
        options: .skipsHiddenFiles
      )
      
      var totalCleaned: Int64 = 0
      var fileCount = 0
      
      for fileURL in contents {
        let filename = fileURL.lastPathComponent
        
        // 只清理下載暫存檔
        let isDownloadTemp = filename.hasSuffix(".download") ||
                            filename.hasPrefix("CFNetworkDownload_") ||
                            filename.hasSuffix(".part")
        
        guard isDownloadTemp else { continue }
        
        // 檢查檔案年齡（超過 1 小時才刪除，避免刪到正在下載的檔案）
        if let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
           let creationDate = attrs[.creationDate] as? Date,
           Date().timeIntervalSince(creationDate) < 3600 {
          continue // 檔案太新，可能是正在下載
        }
        
        // 取得檔案大小
        let fileSize = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        
        // 刪除檔案
        do {
          try FileManager.default.removeItem(at: fileURL)
          totalCleaned += Int64(fileSize)
          fileCount += 1
          print("[Cleanup] 已刪除舊暫存: \(filename) (\(formatBytes(Int64(fileSize))))")
        } catch {
          print("[Cleanup] 刪除失敗: \(filename) - \(error.localizedDescription)")
        }
      }
      
      if fileCount > 0 {
        print("[Cleanup] 總共清理 \(fileCount) 個檔案，釋放 \(formatBytes(totalCleaned))")
      }
    } catch {
      print("[Cleanup] 讀取目錄失敗: \(dir.path) - \(error.localizedDescription)")
    }
  }
  
  /// [小葵 2026-07-21] 下載失敗時自動刪除暫存檔
  /// 刪除 URLSession 暫存檔（.download、CFNetworkDownload_*.tmp）和 .part 檔
  func cleanupFailedDownloadTempFiles(taskPath: String?) {
    var cleanedFiles: [String] = []
    var totalSize: Int64 = 0
    
    // 1. 刪除 URLSession 暫存檔（系統暫存區）
    let systemTempDir = FileManager.default.temporaryDirectory
    if let contents = try? FileManager.default.contentsOfDirectory(
      at: systemTempDir,
      includingPropertiesForKeys: [.fileSizeKey],
      options: .skipsHiddenFiles
    ) {
      for fileURL in contents {
        let filename = fileURL.lastPathComponent
        if filename.hasSuffix(".download") || filename.hasPrefix("CFNetworkDownload_") {
          let size = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
          try? FileManager.default.removeItem(at: fileURL)
          cleanedFiles.append(filename)
          totalSize += Int64(size)
        }
      }
    }
    
    // 2. 刪除容器暫存區
    let containerTempDir = URL(fileURLWithPath: NSHomeDirectory())
      .appendingPathComponent("Library/Containers/farm.semiwasabi.bridgeApp/Data/tmp")
    if let contents = try? FileManager.default.contentsOfDirectory(
      at: containerTempDir,
      includingPropertiesForKeys: [.fileSizeKey],
      options: .skipsHiddenFiles
    ) {
      for fileURL in contents {
        let filename = fileURL.lastPathComponent
        if filename.hasSuffix(".download") || filename.hasPrefix("CFNetworkDownload_") {
          let size = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
          try? FileManager.default.removeItem(at: fileURL)
          cleanedFiles.append(filename)
          totalSize += Int64(size)
        }
      }
    }
    
    // 3. 刪除 .part 檔（如果存在）
    if let taskPath = taskPath,
       let task = readJSONObject(from: URL(fileURLWithPath: taskPath)),
       let partialFilePath = task["partialFilePath"] as? String,
       FileManager.default.fileExists(atPath: partialFilePath) {
      let size = fileSize(atPath: partialFilePath)
      try? FileManager.default.removeItem(atPath: partialFilePath)
      cleanedFiles.append(URL(fileURLWithPath: partialFilePath).lastPathComponent)
      totalSize += size
    }
    
    if !cleanedFiles.isEmpty {
      print("[Cleanup] 下載失敗，已刪除暫存檔: \(cleanedFiles.joined(separator: ", "))，釋放 \(formatBytes(totalSize))")
    }
  }
}


// ============================================================
// [小葵 2026-08-31 v180] 星系獨立視窗——WKWebView 專屬 NSWindow
// 頁面=視窗主人 → document.hasFocus()=true → WebKit 不節流 → 絲滑
// ============================================================
final class GalaxyWindowController: NSObject, NSWindowDelegate {
  static let shared = GalaxyWindowController()
  private var window: NSWindow?
  private var webView: WKWebView?
  private var hasOpened = false

  func open(urlString: String?) {
    guard let urlString = urlString, let url = URL(string: urlString) else { return }
    if let w = window, let wv = webView {
      wv.load(URLRequest(url: url))
      w.makeKeyAndOrderFront(nil)
      return
    }
    let wv = WKWebView(frame: NSRect(x: 0, y: 0, width: 1280, height: 800))
    wv.load(URLRequest(url: url))
    let w = NSWindow(contentRect: wv.frame,
                     styleMask: [.titled, .closable, .miniaturizable, .resizable],
                     backing: .buffered, defer: false)
    w.title = "大腦星系 · Bridge"
    w.contentView = wv
    w.setFrameAutosaveName("GalaxyWindow") // 記住使用者調的位置大小
    // [小葵 2026-09-01 v182 崩潰修] NSWindow 預設 isReleasedWhenClosed=true：
    // AppKit 關窗時自動 release + 我們 windowWillClose 再清參照=過度釋放
    // → SIGSEGV（crash report 鐵證：objc_release/_NSWindowTransformAnimation
    // dealloc，Blue 關獨立視窗兩次、App 跟著崩兩次）。
    // 三寶：isReleasedWhenClosed=false（我們自己持有 strong ref）+
    // 關窗只清 delegate 不多 release。
    w.isReleasedWhenClosed = false
    w.delegate = self
    w.makeKeyAndOrderFront(nil)
    self.window = w
    self.webView = wv
    self.hasOpened = true
    startFpsWatch() // [v253] 節流自動重置
  }

  func close() {
    window?.close()
  }

  // [v253 Blue 令] 節流重置——about:blank 導航（跨頁面導航可能觸發
  // WebContent 進程更換）再回原頁；無效時升級為「關窗重開」（新 WKWebView）。
  private var _lastURL: URL?
  func resetWebview(level: Int) {
    guard let wv = webView else { return }
    _lastURL = _lastURL ?? wv.url
    if level == 1 {
      // L1：about:blank 往返
      wv.load(URLRequest(url: URL(string: "about:blank")!))
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
        if let url = self?._lastURL { wv.load(URLRequest(url: url)) }
      }
    } else {
      // L2：關窗重開（整個 WKWebView 重建）
      if let w = window { w.close() }
      if let url = _lastURL {
        window = nil; webView = nil
        open(urlString: url.absoluteString)
      }
    }
  }

  // [v253] fps 監視——每 30 秒問頁面 fps；連續低 → 自動 L1，再低 → L2
  private var _lowFpsCount = 0
  private var _fpsTimer: Timer?
  func startFpsWatch() {
    _fpsTimer?.invalidate()
    _lowFpsCount = 0
    _fpsTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] t in
      guard let self = self, let wv = self.webView else { t.invalidate(); return }
      wv.evaluateJavaScript("(window.__fpsHist&&window.__fpsHist.length?window.__fpsHist[window.__fpsHist.length-1]:100)") { r, _ in
        // [v255] NSNumber→Int（舊碼 as? Int 永遠 nil=監視全瞎）
        let fps = (r as? NSNumber)?.intValue ?? 100
        if fps < 85 {
          self._lowFpsCount += 1
          if self._lowFpsCount >= 3 {
            let level = self._lowFpsCount >= 6 ? 2 : 1
            self.resetWebview(level: level)
            if level == 2 { self._lowFpsCount = 0 }
          }
        } else {
          self._lowFpsCount = 0
        }
      }
    }
  }

  func windowWillClose(_ notification: Notification) {
    // 只清內部參照（isReleasedWhenClosed=false 下安全）；delegate 在
    // windowDidClose 後解綁，避免 AppKit 回呼到已清空的狀態
    window?.delegate = nil
    window = nil
    webView = nil
  }
}


// ============================================================
// [小葵 2026-09-01 v183] 星系螢幕保護程式——閒置觸發全螢幕即時星系
// 即時性：頁面 ?saver=1 每 30 秒重抓 galaxy_data（新星淡入誕生）
// ============================================================
final class GalaxySaverController: NSObject, NSWindowDelegate {
  static let shared = GalaxySaverController()
  private var checkTimer: Timer?
  private var saverWindow: NSWindow?
  private var saverWebView: WKWebView?
  private var idleMinutes = 5
  private var urlString: String?
  private var enabled = false

  func configure(enabled: Bool, idleMinutes: Int, urlString: String?) {
    self.enabled = enabled
    self.idleMinutes = idleMinutes
    self.urlString = urlString
    checkTimer?.invalidate()
    saverWindow?.close()
    if enabled {
      checkTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
        self?.tick()
      }
    }
  }

  private func tick() {
    guard enabled else { return }
    let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState,
                                                       eventType: CGEventType(rawValue: ~0)!)
    let idleSec = TimeInterval(idle)
    if saverWindow == nil, idleSec >= Double(idleMinutes * 60) {
      showSaver()
    } else if saverWindow != nil, idleSec < Double(idleMinutes * 60) {
      // 使用者回來（任何輸入都會重置 idle）——退場。tick 週期 10 秒=最多 10 秒內退。
      // [v210 殭屍黑視窗修復 2026-09-02] close() 對 borderless+isReleasedWhenClosed=false
      // 的視窗在部分狀態下不會真正移除（隱形全螢幕層持續吞點擊——Blue 抓包）。
      // 加 orderOut(nil) 強制下架 + close 雙保險。
      saverWindow?.orderOut(nil)
      saverWindow?.close()
    }
  }

  private func showSaver() {
    guard let urlString = urlString, let base = URL(string: urlString) else { return }
    // base 已含 token；加 saver=1（保留既有 query）
    var comps = URLComponents(url: base, resolvingAgainstBaseURL: false)!
    var items = comps.queryItems ?? []
    items.append(URLQueryItem(name: "saver", value: "1"))
    comps.queryItems = items
    guard let url = comps.url else { return }

    let screen = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1920, height: 1080)
    let wv = WKWebView(frame: screen)
    wv.setValue(false, forKey: "drawsBackground") // 純黑融合
    wv.load(URLRequest(url: url))
    let w = NSWindow(contentRect: screen,
                     styleMask: [.borderless],
                     backing: .buffered, defer: false)
    w.level = .screenSaver
    w.isOpaque = false
    w.backgroundColor = .black
    w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    w.ignoresMouseEvents = false // 要能收到活動（其實靠 idle 偵測退場）
    w.contentView = wv
    w.isReleasedWhenClosed = false
    w.delegate = self
    w.makeKeyAndOrderFront(nil)
    saverWindow = w
    saverWebView = wv
  }

  func windowWillClose(_ notification: Notification) {
    saverWindow?.delegate = nil
    saverWindow = nil
    saverWebView = nil
  }
}


// ═══ [小葵 2026-09-24 出道令 v2] cyan 去背循環影片 ═══
// AVPlayerItemVideoOutput 逐幀取樣 → CIColorKernel chroma key（cyan #00FFFF → alpha）
// → CIContext 出 CGImage 貼 layer.contents。與 Morning Tea WebGL 引擎同鍵色。
final class ChromaKeyPlayerView: NSView {
  private let player = AVPlayer()
  private var videoOutput: AVPlayerItemVideoOutput?
  private var displayLink: CVDisplayLink?
  private var loopObserver: NSObjectProtocol?
  private let ciContext = CIContext(options: [.workingColorSpace: NSNull()])
  private let kernel: CIColorKernel?
  // [小葵 2026-10-05 去背版直通] .mov（ProRes 4444 alpha）用——AVPlayerLayer 硬解路徑
  private var playerLayer: AVPlayerLayer?
  // [小葵 2026-09-24 出道令] 首幀回調——雙緩衝換片用它判定「新片畫面已就緒」
  var onFirstFrame: (() -> Void)? = nil
  private var firstFrameFired = false
  // [小葵 2026-10-05 節能根修] 隔幀開關——30fps 上限用（見 startDisplayLink callback）
  private var frameSkipToggle = false

  private static let kernelSource = """
    kernel vec4 chromaKey(__sample s, vec3 keyColor, float threshold) {
      float dist = distance(s.rgb, keyColor);
      float alpha = smoothstep(threshold, threshold + 0.09, dist);
      // despill：半透明邊緣把 cyan 溢色壓掉（g 往 min(r,b) 收）
      float mn = min(s.r, s.b);
      float g = mix(s.g, mn, (1.0 - alpha) * 0.85);
      return vec4(vec3(s.r, g, s.b), s.a * alpha);
    }
    """

  override init(frame frameRect: NSRect) {
    kernel = try? CIColorKernel(source: Self.kernelSource)
    super.init(frame: frameRect)
    wantsLayer = true
    layer?.contentsGravity = .resizeAspect
  }

  required init?(coder: NSCoder) {
    kernel = try? CIColorKernel(source: Self.kernelSource)
    super.init(coder: coder)
    wantsLayer = true
    layer?.contentsGravity = .resizeAspect
  }

  deinit {
    stop()
  }

  func playLoop(path: String) {
    stop()
    firstFrameFired = false
    // [小葵 2026-10-05 去背版直通] .mov（ProRes 4444 自帶 alpha）走 AVPlayerLayer
    // 硬體解碼——零 CIContext 去背、零 displayLink 輪詢。CPU 從 200% 級降到近 0。
    // .mp4（cyan 底舊素材）保留原 chroma-key 軟體路徑向後相容。
    if path.hasSuffix(".mov") {
      let item = AVPlayerItem(url: URL(fileURLWithPath: path))
      player.replaceCurrentItem(with: item)
      player.isMuted = true
      let playerLayer = AVPlayerLayer(player: player)
      playerLayer.frame = bounds
      playerLayer.videoGravity = .resizeAspect
      playerLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
      layer?.addSublayer(playerLayer)
      self.playerLayer = playerLayer
      loopObserver = NotificationCenter.default.addObserver(
        forName: .AVPlayerItemDidPlayToEndTime,
        object: item, queue: .main
      ) { [weak self] _ in
        self?.player.seek(to: .zero)
        self?.player.play()
      }
      player.play()
      // 首幀通知：500ms 後觸發（AVPlayerLayer 自己管渲染，無需逐幀回調）
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
        guard let self = self, !self.firstFrameFired else { return }
        self.firstFrameFired = true
        self.onFirstFrame?()
      }
      return
    }
    let item = AVPlayerItem(url: URL(fileURLWithPath: path))
    let attrs: [String: Any] = [
      kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
    ]
    let output = AVPlayerItemVideoOutput(pixelBufferAttributes: attrs)
    item.add(output)
    videoOutput = output
    player.replaceCurrentItem(with: item)
    player.isMuted = true  // 影片純視覺——語音走 TTS
    loopObserver = NotificationCenter.default.addObserver(
      forName: .AVPlayerItemDidPlayToEndTime,
      object: item, queue: .main
    ) { [weak self] _ in
      self?.player.seek(to: .zero)
      self?.player.play()
    }
    player.play()
    startDisplayLink()
  }

  var isPlaying: Bool { player.timeControlStatus == .playing }

  func stop() {
    stopDisplayLink()
    // [小葵 2026-10-05 去背版直通] 移除 playerLayer（.mov 路徑專用）
    playerLayer?.removeFromSuperlayer()
    playerLayer = nil
    if let o = loopObserver {
      NotificationCenter.default.removeObserver(o)
      loopObserver = nil
    }
    player.pause()
    player.replaceCurrentItem(with: nil)
    videoOutput = nil
    layer?.contents = nil
  }

  // [小葵 2026-09-30 CPU 懸案根修] 追蹤所有 live display link——
  // 洩漏實證：114 個 CVDisplayLink thread（正常 1 個），殘留 link 每個
  // 每秒回呼 renderFrame 60 次 = CPU 200% 永動機（Swift 層洩漏，Dart log 無感）
  private static var liveLinks: [CVDisplayLink] = []

  private func startDisplayLink() {
    var link: CVDisplayLink?
    CVDisplayLinkCreateWithActiveCGDisplays(&link)
    guard let dl = link else { return }
    // [根修] 原本 passRetained(self) 過度保留 view（無人 release）——改弱引用 box，
    // view 釋放後 callback 自動 no-op，不再洩漏
    final class WeakBox { weak var view: ChromaKeyPlayerView?; init(_ v: ChromaKeyPlayerView) { view = v } }
    let box = WeakBox(self)
    let ctx = Unmanaged.passRetained(box).toOpaque()
    CVDisplayLinkSetOutputCallback(dl, { _, _, _, _, _, userInfo in
      guard let userInfo = userInfo else { return kCVReturnSuccess }
      let box = Unmanaged<WeakBox>.fromOpaque(userInfo).takeUnretainedValue()
      // [小葵 2026-10-05 節能根修] 30fps 上限——素材多為 20-30fps 循環短片，
      // 60Hz 回呼等於一半無效工。隔幀跳過：CPU 減半、視覺零差（人眼對 30fps
      // 動圖無感）。取樣鐵證：displayLink callback 289 樣本全是最大熱點。
      if box.view?.frameSkipToggle == false {
        box.view?.frameSkipToggle = true
        return kCVReturnSuccess  // 本幀跳過
      }
      box.view?.frameSkipToggle = false
      box.view?.renderFrame()
      return kCVReturnSuccess
    }, ctx)
    CVDisplayLinkStart(dl)
    displayLink = dl
    ChromaKeyPlayerView.liveLinks.append(dl)
  }

  /// [根修] 停止本 view 的 link 並從全域清單移除
  func stopDisplayLink() {
    if let link = displayLink {
      CVDisplayLinkStop(link)
      ChromaKeyPlayerView.liveLinks.removeAll { $0 == link }
      displayLink = nil
    }
  }

  /// [根修] 全域清道夫：停掉所有殘留 link（互換 view 鏈斷裂時的保險）
  static func stopAllDisplayLinks() {
    for link in liveLinks { CVDisplayLinkStop(link) }
    liveLinks.removeAll()
  }

  private func renderFrame() {
    guard let output = videoOutput, let item = player.currentItem else { return }
    // [小葵 2026-10-05 節能根修] 懸浮窗不在螢幕上（最小化/隱藏）→ 跳過渲染。
    // window.orderOut 後 displayLink 仍在跑——白燒 CPU。視窗不可見時完全跳過。
    if window == nil || !window!.isVisible { return }
    let time = item.currentTime()
    guard output.hasNewPixelBuffer(forItemTime: time),
          let pb = output.copyPixelBuffer(forItemTime: time, itemTimeForDisplay: nil)
    else { return }
    let base = CIImage(cvPixelBuffer: pb, options: [:])
    var ci = base
    // cyan #00FFFF = (0,1,1) in linear RGB（影片即此底色）
    if let k = kernel, let keyed = k.apply(
      extent: base.extent,
      arguments: [base, CIVector(x: 0.0, y: 1.0, z: 1.0), NSNumber(value: 0.32)]
    ) {
      ci = keyed
    }
    let extent = ci.extent
    if let cg = ciContext.createCGImage(ci, from: extent) {
      DispatchQueue.main.async { [weak self] in
        guard let self = self else { return }
        self.layer?.contents = cg
        // [小葵 2026-09-24 出道令] 首幀已上畫面→通知雙緩衝退役舊片
        if !self.firstFrameFired {
          self.firstFrameFired = true
          self.onFirstFrame?()
        }
      }
    }
  }
}
