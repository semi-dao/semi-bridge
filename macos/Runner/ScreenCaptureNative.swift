// ScreenCaptureNative.swift
// B4: 原生 macOS 螢幕截圖 — CGWindowListCreateImage
// Phase 1.5 Open Canvas 螢幕感知
//
// 功能：
// 1. listWindows — 列出所有可見視窗（ID + 標題 + App）
// 2. captureWindow — 截取指定視窗 ID 的截圖
//
// 隱私：截取指定視窗，不是全螢幕。需使用者啟用 screen_capture_enabled。

import Cocoa
import FlutterMacOS

struct ScreenCaptureNative {

    /// 列出所有可見視窗
    static func listWindows(result: @escaping FlutterResult) {
        var windowList: [[String: Any]] = []

        // CGWindowListCopyWindowInfo: 只取 on-screen 視窗
        guard let windows = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            result([])
            return
        }

        for window in windows {
            // 只要有層級 = Normal (0) 的視窗
            let layer = window[kCGWindowLayer as String] as? Int ?? -1
            guard layer == 0 else { continue }

            let windowID = window[kCGWindowNumber as String] as? Int ?? 0
            let title = window[kCGWindowName as String] as? String ?? ""
            let ownerName = window[kCGWindowOwnerName as String] as? String ?? ""

            // 取得 bounds
            let bounds = window[kCGWindowBounds as String] as? [String: Any] ?? [:]
            let boundsDict: [String: Any] = [
                "x": bounds["X"] ?? 0,
                "y": bounds["Y"] ?? 0,
                "width": bounds["Width"] ?? 0,
                "height": bounds["Height"] ?? 0,
            ]

            windowList.append([
                "windowId": windowID,
                "title": title,
                "ownerName": ownerName,
                "bounds": boundsDict,
            ])
        }

        result(windowList)
    }

    /// 截取指定視窗
    /// [開光 v0.4.x 2026-10-01] 全螢幕拍攝（CGRect.null + 所有視窗 = 整個桌面）
    static func captureScreen(result: @escaping FlutterResult) {
        let image = CGWindowListCreateImage(
            .null,
            [.optionOnScreenOnly],
            kCGNullWindowID,
            [.boundsIgnoreFraming, .nominalResolution]
        )
        guard let cgImage = image else {
            result(FlutterError(code: "capture_failed", message: "CGWindowListCreateImage 回 nil（可能未授螢幕錄製權限）", details: nil))
            return
        }
        let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
        guard let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
            result(FlutterError(code: "encode_failed", message: "PNG 編碼失敗", details: nil))
            return
        }
        // 寫到 App 沙盒暫存（Dart 讀完即刪）
        let tmp = NSTemporaryDirectory() + "bridge_os_retina_\(Int(Date().timeIntervalSince1970)).png"
        do {
            try pngData.write(to: URL(fileURLWithPath: tmp))
            result([
                "screenshotPath": tmp,
                "width": cgImage.width,
                "height": cgImage.height,
            ])
        } catch {
            result(FlutterError(code: "write_failed", message: "\(error.localizedDescription)", details: nil))
        }
    }

    static func captureWindow(call: FlutterMethodCall, result: @escaping FlutterResult) {
        let args = call.arguments as? [String: Any] ?? [:]
        let windowId = args["windowId"] as? Int
        let windowTitle = args["windowTitle"] as? String
        let appId = args["appId"] as? String

        // 1. 如果沒有 windowId，用 title/appId 查找
        var targetWindowId: CGWindowID = kCGNullWindowID
        var resolvedTitle = ""
        var resolvedApp = ""

        if let wid = windowId, wid > 0 {
            targetWindowId = CGWindowID(wid)
        } else {
            // 查找視窗
            guard let match = findWindow(title: windowTitle, appId: appId) else {
                result(FlutterError(
                    code: "no_window",
                    message: "找不到匹配的視窗",
                    details: "windowTitle=\(windowTitle ?? "nil"), appId=\(appId ?? "nil")"
                ))
                return
            }
            targetWindowId = match.id
            resolvedTitle = match.title
            resolvedApp = match.owner
        }

        // 2. CGWindowListCreateImage — 截取指定視窗
        let windowRect = CGRect.null
        let image = CGWindowListCreateImage(
            windowRect,
            [.optionIncludingWindow],
            targetWindowId,
            [.boundsIgnoreFraming, .nominalResolution]
        )

        guard let cgImage = image else {
            result(FlutterError(
                code: "capture_failed",
                message: "CGWindowListCreateImage 回傳 nil",
                details: "可能無螢幕錄製權限，或視窗已關閉。windowId=\(targetWindowId)"
            ))
            return
        }

        // 3. 存成 PNG 到暫存目錄
        let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
        guard let pngData = bitmapRep.representation(
            using: .png,
            properties: [:]
        ) else {
            result(FlutterError(
                code: "encode_failed",
                message: "PNG 編碼失敗",
                details: nil
            ))
            return
        }

        // 暫存路徑：~/Library/Application Support/Bridge/screenshots/
        let fm = FileManager.default
        guard let appSupport = fm.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            result(FlutterError(
                code: "no_app_support",
                message: "無法取得 Application Support 目錄",
                details: nil
            ))
            return
        }

        let screenshotDir = appSupport
            .appendingPathComponent("Bridge", isDirectory: true)
            .appendingPathComponent("screenshots", isDirectory: true)

        do {
            try fm.createDirectory(
                at: screenshotDir,
                withIntermediateDirectories: true
            )
        } catch {
            result(FlutterError(
                code: "mkdir_failed",
                message: "建立截圖目錄失敗：\(error.localizedDescription)",
                details: nil
            ))
            return
        }

        let timestamp = Int(Date().timeIntervalSince1970 * 1000)
        let filename = "screenshot_\(timestamp).png"
        let filePath = screenshotDir.appendingPathComponent(filename)

        do {
            try pngData.write(to: filePath)
        } catch {
            result(FlutterError(
                code: "write_failed",
                message: "寫入截圖檔案失敗：\(error.localizedDescription)",
                details: nil
            ))
            return
        }

        // 如果 title/app 沒有傳入，從 windowId 查
        if resolvedTitle.isEmpty {
            if let match = findWindowById(targetWindowId) {
                resolvedTitle = match.title
                resolvedApp = match.owner
            }
        }

        result([
            "screenshotPath": filePath.path,
            "windowTitle": resolvedTitle,
            "appBundleId": resolvedApp,
            "windowId": Int(targetWindowId),
            "width": cgImage.width,
            "height": cgImage.height,
        ])
    }

    // MARK: - 視窗查找

    private struct WindowMatch {
        let id: CGWindowID
        let title: String
        let owner: String
    }

    /// 用標題或 App 名稱查找視窗
    private static func findWindow(title: String?, appId: String?) -> WindowMatch? {
        guard let windows = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return nil
        }

        for window in windows {
            let layer = window[kCGWindowLayer as String] as? Int ?? -1
            guard layer == 0 else { continue }

            let windowTitle = window[kCGWindowName as String] as? String ?? ""
            let ownerName = window[kCGWindowOwnerName as String] as? String ?? ""
            let windowID = window[kCGWindowNumber as String] as? Int ?? 0

            // 模糊匹配 title
            if let t = title, !t.isEmpty {
                if windowTitle.lowercased().contains(t.lowercased()) {
                    return WindowMatch(id: CGWindowID(windowID), title: windowTitle, owner: ownerName)
                }
            }

            // 匹配 appId（用 ownerName 模糊匹配）
            if let a = appId, !a.isEmpty {
                if ownerName.lowercased().contains(a.lowercased()) {
                    return WindowMatch(id: CGWindowID(windowID), title: windowTitle, owner: ownerName)
                }
            }
        }

        // 如果都沒傳，取最上層可見視窗（非自己）
        for window in windows {
            let layer = window[kCGWindowLayer as String] as? Int ?? -1
            guard layer == 0 else { continue }

            let windowID = window[kCGWindowNumber as String] as? Int ?? 0
            let windowTitle = window[kCGWindowName as String] as? String ?? ""
            let ownerName = window[kCGWindowOwnerName as String] as? String ?? ""

            // 跳過 Bridge App 自己的視窗
            if ownerName.lowercased().contains("bridge") { continue }

            return WindowMatch(id: CGWindowID(windowID), title: windowTitle, owner: ownerName)
        }

        return nil
    }

    /// 用 windowId 查視窗資訊
    private static func findWindowById(_ windowId: CGWindowID) -> WindowMatch? {
        guard let windows = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return nil
        }

        for window in windows {
            let wid = window[kCGWindowNumber as String] as? Int ?? 0
            if CGWindowID(wid) == windowId {
                let windowTitle = window[kCGWindowName as String] as? String ?? ""
                let ownerName = window[kCGWindowOwnerName as String] as? String ?? ""
                return WindowMatch(id: windowId, title: windowTitle, owner: ownerName)
            }
        }

        return nil
    }
}
