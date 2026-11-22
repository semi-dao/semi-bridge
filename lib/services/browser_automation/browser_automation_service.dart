// browser_automation_service.dart
// 瀏覽器自動化引擎 — 用 puppeteer Dart 套件控制 Chrome。
// 實作 GatewayTaskHandler 介面，讓 Gateway 可以路由 taskRun 請求到此 service。
// Sprint 19b by 教練 Agent (CEO)

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:puppeteer/puppeteer.dart';

import '../../models/browser_automation/browser_task.dart';
import '../desktop_bridge_gateway_protocol.dart';
import '../desktop_bridge_local_gateway.dart' show ConfirmationRegistry;

/// 登入/付款頁面偵測結果。
enum _PageType {
  normal,
  login,
  payment,
  checkout,
}

/// 瀏覽器自動化服務。
///
/// 職責：
/// - 啟動 Chrome（headed mode，使用者可見）
/// - 執行 [BrowserTask] 步驟序列
/// - 偵測登入/付款頁面 → 暫停 → 推播 `taskAwaitingConfirmation`
/// - 每步完成推播 `taskProgress`
/// - 全部完成推播 `taskComplete`
///
/// 生命週期：
/// - 第一次收到 taskRun 時 lazy 啟動 Chrome
/// - Chrome 啟動後保持常駐（多個任務共用同一個 Browser 實例）
/// - App 關閉時 [dispose] 關閉 Chrome
class BrowserAutomationService implements GatewayTaskHandler {
  Browser? _browser;
  bool _starting = false;

  /// 進行中的任務（taskId → cancel flag）
  final Map<String, bool> _cancelledTasks = {};

  /// [S1 2026-10-31 補鏈] 拍板喚醒登記簿——可選注入。
  /// null 時沿用 v1 行為（awaiting 即結束）；注入後暫停等拍板。
  final ConfirmationRegistry? confirmationRegistry;

  BrowserAutomationService({this.confirmationRegistry});

  // ─────────────────────────────────────────────────────────
  // GatewayTaskHandler 實作
  // ─────────────────────────────────────────────────────────

  @override
  String startTask({
    required String taskType,
    required Map<String, dynamic> payload,
    required void Function(double progress, String message) onProgress,
    required void Function(bool success, Map<String, dynamic> result, String? error) onComplete,
    required void Function(String reason, Map<String, dynamic> context) onAwaitingConfirmation,
  }) {
    final taskId = 'browser-${DateTime.now().millisecondsSinceEpoch}';

    // 非同步執行，立即回傳 taskId
    _executeTask(
      taskId: taskId,
      taskType: taskType,
      payload: payload,
      onProgress: onProgress,
      onComplete: onComplete,
      onAwaitingConfirmation: onAwaitingConfirmation,
    );

    return taskId;
  }

  @override
  bool cancelTask(String taskId) {
    if (_cancelledTasks.containsKey(taskId)) {
      _cancelledTasks[taskId] = true;
      return true;
    }
    return false;
  }

  // ─────────────────────────────────────────────────────────
  // 任務執行
  // ─────────────────────────────────────────────────────────

  Future<void> _executeTask({
    required String taskId,
    required String taskType,
    required Map<String, dynamic> payload,
    required void Function(double progress, String message) onProgress,
    required void Function(bool success, Map<String, dynamic> result, String? error) onComplete,
    required void Function(String reason, Map<String, dynamic> context) onAwaitingConfirmation,
  }) async {
    _cancelledTasks[taskId] = false;

    try {
      // 確保 Chrome 已啟動
      final browser = await _ensureBrowser(onProgress);
      if (browser == null) {
        onComplete(false, {}, 'Failed to start Chrome browser.');
        _cancelledTasks.remove(taskId);
        return;
      }

      final page = await browser.newPage();

      // 根據 taskType 分派
      if (taskType == 'browser.navigate') {
        await _executeNavigate(
          taskId: taskId,
          page: page,
          url: payload['url'] as String? ?? 'about:blank',
          onProgress: onProgress,
          onComplete: onComplete,
          onAwaitingConfirmation: onAwaitingConfirmation,
        );
      } else if (taskType == 'browser.fillForm') {
        await _executeFillForm(
          taskId: taskId,
          page: page,
          url: payload['url'] as String? ?? 'about:blank',
          fields: payload['fields'],
          submitSelector: payload['submitSelector'] as String?,
          onProgress: onProgress,
          onComplete: onComplete,
          onAwaitingConfirmation: onAwaitingConfirmation,
        );
      } else if (taskType == 'browser.screenshot') {
        await _executeScreenshot(
          taskId: taskId,
          page: page,
          url: payload['url'] as String? ?? 'about:blank',
          onProgress: onProgress,
          onComplete: onComplete,
          onAwaitingConfirmation: onAwaitingConfirmation,
        );
      } else if (taskType == 'browser.runSteps') {
        // 完整的步驟序列
        final task = BrowserTask.fromJson({
          ...payload,
          'id': taskId,
          'name': payload['name'] ?? 'custom',
        });
        await _executeSteps(
          taskId: taskId,
          page: page,
          task: task,
          onProgress: onProgress,
          onComplete: onComplete,
          onAwaitingConfirmation: onAwaitingConfirmation,
        );
      } else {
        onComplete(false, {}, 'Unknown task type: $taskType');
      }

      await page.close();
    } catch (e) {
      onComplete(false, {}, 'Browser task failed: $e');
    } finally {
      _cancelledTasks.remove(taskId);
    }
  }

  // ─────────────────────────────────────────────────────────
  // 任務類型實作
  // ─────────────────────────────────────────────────────────

  /// 導航到 URL + 偵測登入/付款頁
  Future<void> _executeNavigate({
    required String taskId,
    required Page page,
    required String url,
    required void Function(double progress, String message) onProgress,
    required void Function(bool success, Map<String, dynamic> result, String? error) onComplete,
    required void Function(String reason, Map<String, dynamic> context) onAwaitingConfirmation,
  }) async {
    onProgress(0.1, '正在導航到 $url...');
    await page.goto(url, wait: Until.networkIdle);

    // 偵測頁面類型
    final pageType = await _detectPageType(page);
    if (pageType != _PageType.normal) {
      final reason = pageType == _PageType.login
          ? '偵測到登入頁面，需要使用者確認'
          : pageType == _PageType.payment
              ? '偵測到付款頁面，需要使用者確認'
              : '偵測到結帳頁面，需要使用者確認';
      onAwaitingConfirmation(reason, {
        'url': url,
        'pageType': pageType.name,
      });
      // [S1 2026-10-31 補鏈] 不再「任務在此結束」——登記暫停等拍板：
      // approve → 繼續往下跑；reject/逾時（5 分鐘）→ 以 awaiting-rejected 收場。
      // registry 由 TaskQueue 建構時注入（S1 接線見 task_queue.dart）。
      if (confirmationRegistry != null) {
        final suspender = confirmationRegistry!.suspend(taskId);
        suspender.setTimeout(const Duration(minutes: 5));
        final approved = await suspender.future;
        if (!approved) {
          onComplete(true, {
            'url': url,
            'pageType': pageType.name,
            'status': 'awaiting_rejected',
          }, null);
          return;
        }
        onProgress(0.5, '已批准，繼續執行...');
      } else {
        // 無 registry（獨立使用/測試）——沿用 v1 行為：到此結束
        onComplete(true, {
          'url': url,
          'pageType': pageType.name,
          'status': 'awaiting_confirmation',
        }, null);
        return;
      }
    }

    onProgress(0.9, '頁面載入完成');
    onComplete(true, {
      'url': url,
      'title': await page.title,
      'status': 'completed',
    }, null);
  }

  /// 填表
  Future<void> _executeFillForm({
    required String taskId,
    required Page page,
    required String url,
    required dynamic fields,
    required String? submitSelector,
    required void Function(double progress, String message) onProgress,
    required void Function(bool success, Map<String, dynamic> result, String? error) onComplete,
    required void Function(String reason, Map<String, dynamic> context) onAwaitingConfirmation,
  }) async {
    onProgress(0.1, '正在導航到 $url...');
    await page.goto(url, wait: Until.networkIdle);

    // 偵測登入/付款
    final pageType = await _detectPageType(page);
    if (pageType != _PageType.normal) {
      onAwaitingConfirmation('偵測到 ${pageType.name} 頁面，需要使用者確認', {
        'url': url,
        'pageType': pageType.name,
      });
      onComplete(true, {
        'url': url,
        'pageType': pageType.name,
        'status': 'awaiting_confirmation',
      }, null);
      return;
    }

    // 填寫欄位
    if (fields is! List) {
      onComplete(false, {}, 'fields must be a list of {selector, value} objects.');
      return;
    }

    final totalFields = fields.length;
    for (var i = 0; i < totalFields; i++) {
      if (_isCancelled(taskId)) {
        onComplete(false, {}, 'Task cancelled by user.');
        return;
      }

      final field = fields[i];
      if (field is! Map<String, dynamic>) continue;
      final selector = field['selector'] as String?;
      final value = field['value'] as String?;
      if (selector == null || value == null) continue;

      await page.type(selector, value);
      onProgress(0.1 + (0.7 * (i + 1) / totalFields), '已填寫欄位 ${i + 1}/$totalFields');
    }

    // 送出
    if (submitSelector != null) {
      onProgress(0.85, '正在送出表單...');
      await page.click(submitSelector);
      // 等待頁面反應（v1: 簡化處理，未來可用 waitForNavigation）
      await Future.delayed(const Duration(seconds: 2));
    }

    onProgress(1.0, '表單填寫完成');
    onComplete(true, {
      'url': url,
      'fieldsFilled': totalFields,
      'submitted': submitSelector != null,
      'finalUrl': page.url ?? '',
      'title': await page.title,
    }, null);
  }

  /// 截圖
  Future<void> _executeScreenshot({
    required String taskId,
    required Page page,
    required String url,
    required void Function(double progress, String message) onProgress,
    required void Function(bool success, Map<String, dynamic> result, String? error) onComplete,
    required void Function(String reason, Map<String, dynamic> context) onAwaitingConfirmation,
  }) async {
    onProgress(0.2, '正在導航到 $url...');
    await page.goto(url, wait: Until.networkIdle);

    onProgress(0.7, '正在截圖...');
    final screenshot = await page.screenshot();
    final base64 = base64Encode(screenshot);

    onProgress(1.0, '截圖完成');
    onComplete(true, {
      'url': url,
      'screenshotBase64': base64,
      'title': await page.title,
    }, null);
  }

  /// 執行完整步驟序列
  Future<void> _executeSteps({
    required String taskId,
    required Page page,
    required BrowserTask task,
    required void Function(double progress, String message) onProgress,
    required void Function(bool success, Map<String, dynamic> result, String? error) onComplete,
    required void Function(String reason, Map<String, dynamic> context) onAwaitingConfirmation,
  }) async {
    final totalSteps = task.steps.length;
    final stepResults = <Map<String, dynamic>>[];

    for (var i = 0; i < totalSteps; i++) {
      if (_isCancelled(taskId)) {
        onComplete(false, {'stepResults': stepResults}, 'Task cancelled by user at step ${i + 1}.');
        return;
      }

      final step = task.steps[i];
      final progress = totalSteps > 0 ? (i / totalSteps) : 0.0;
      onProgress(progress, '步驟 ${i + 1}/$totalSteps: ${step.action.name}');

      try {
        final result = await _executeStep(page, step);
        stepResults.add({
          'step': i + 1,
          'action': step.action.name,
          'success': true,
          ...result,
        });
      } catch (e) {
        stepResults.add({
          'step': i + 1,
          'action': step.action.name,
          'success': false,
          'error': e.toString(),
        });
        onComplete(false, {'stepResults': stepResults}, 'Step ${i + 1} failed: $e');
        return;
      }

      // 每步之後偵測登入/付款（navigate 步驟後一定偵測，其他步驟後也偵測以防跳轉）
      if (step.action == BrowserStepAction.navigate ||
          step.action == BrowserStepAction.click) {
        final pageType = await _detectPageType(page);
        if (pageType != _PageType.normal) {
          onAwaitingConfirmation('偵測到 ${pageType.name} 頁面，需要使用者確認', {
            'url': page.url ?? '',
            'pageType': pageType.name,
            'step': i + 1,
          });
          onComplete(true, {
            'stepResults': stepResults,
            'status': 'awaiting_confirmation',
            'pageType': pageType.name,
          }, null);
          return;
        }
      }

      if (step.waitAfter != null) {
        await Future.delayed(step.waitAfter!);
      }
    }

    onProgress(1.0, '所有步驟完成');
    onComplete(true, {
      'stepResults': stepResults,
      'totalSteps': totalSteps,
      'status': 'completed',
    }, null);
  }

  /// 執行單一步驟
  Future<Map<String, dynamic>> _executeStep(Page page, BrowserStep step) async {
    switch (step.action) {
      case BrowserStepAction.navigate:
        final url = step.value ?? 'about:blank';
        await page.goto(url, wait: Until.networkIdle);
        return {'url': url, 'title': await page.title};

      case BrowserStepAction.click:
        final selector = step.selector;
        if (selector == null) return {'error': 'click requires selector'};
        await page.click(selector);
        return {'selector': selector};

      case BrowserStepAction.type:
        final selector = step.selector;
        final text = step.value;
        if (selector == null || text == null) return {'error': 'type requires selector and value'};
        await page.type(selector, text);
        return {'selector': selector, 'value': text};

      case BrowserStepAction.waitForSelector:
        final selector = step.selector;
        if (selector == null) return {'error': 'waitForSelector requires selector'};
        await page.waitForSelector(selector, timeout: step.timeout ?? const Duration(seconds: 30));
        return {'selector': selector};

      case BrowserStepAction.wait:
        final ms = int.tryParse(step.value ?? '1000') ?? 1000;
        await Future.delayed(Duration(milliseconds: ms));
        return {'waitedMs': ms};

      case BrowserStepAction.evaluate:
        final js = step.value;
        if (js == null) return {'error': 'evaluate requires value (JS code)'};
        final result = await page.evaluate(js);
        return {'result': result?.toString()};

      case BrowserStepAction.screenshot:
        final bytes = await page.screenshot();
        final base64 = base64Encode(bytes);
        return {'screenshotBase64': base64};

      case BrowserStepAction.download:
        final url = step.value;
        if (url == null) return {'error': 'download requires value (URL)'};
        // v1: 簡化 — 用 evaluate 觸發下載
        await page.evaluate('window.location.href = "$url"');
        return {'downloadUrl': url};

      case BrowserStepAction.getText:
        final selector = step.selector;
        if (selector == null) return {'error': 'getText requires selector'};
        final text = await page.evaluate(
          'document.querySelector("$selector")?.textContent ?? ""',
        ) as String?;
        return {'text': text ?? ''};

      case BrowserStepAction.scrollTo:
        final selector = step.selector;
        if (selector == null) return {'error': 'scrollTo requires selector'};
        await page.evaluate(
          'document.querySelector("$selector")?.scrollIntoView({behavior: "smooth"})',
        );
        return {'selector': selector};
    }
  }

  // ─────────────────────────────────────────────────────────
  // 登入/付款偵測
  // ─────────────────────────────────────────────────────────

  /// 偵測頁面是否為登入/付款/結帳頁。
  ///
  /// v1 用 URL pattern + 關鍵元素偵測，不靠 LLM 判斷。
  Future<_PageType> _detectPageType(Page page) async {
    try {
      final url = (page.url ?? '').toLowerCase();

      // URL pattern 偵測
      if (_matchesLoginUrl(url)) return _PageType.login;
      if (_matchesPaymentUrl(url)) return _PageType.payment;
      if (_matchesCheckoutUrl(url)) return _PageType.checkout;

      // 頁面元素偵測（password input 存在 → login）
      final hasPasswordInput = await page.evaluate(
        'document.querySelector("input[type=\\"password\\"]") !== null',
      ) as bool?;
      if (hasPasswordInput == true) return _PageType.login;

      // 付款表單偵測（信用卡 input 存在）
      final hasCardInput = await page.evaluate(
        '''(() => {
          const inputs = document.querySelectorAll("input");
          for (const input of inputs) {
            const name = (input.name || "").toLowerCase();
            const id = (input.id || "").toLowerCase();
            const placeholder = (input.placeholder || "").toLowerCase();
            if (name.includes("card") || id.includes("card") ||
                placeholder.includes("card") ||
                name.includes("ccnumber") || name.includes("cc-number") ||
                name.includes("creditcard") || name.includes("credit-card")) {
              return true;
            }
          }
          return false;
        })()''',
      ) as bool?;
      if (hasCardInput == true) return _PageType.payment;
    } catch (_) {
      // 偵測失敗不影響任務執行，當作 normal 頁面
    }

    return _PageType.normal;
  }

  bool _matchesLoginUrl(String url) {
    const loginPatterns = [
      '/login', '/signin', '/sign-in', '/auth', '/account/login',
      '/users/login', '/session/new', '/connect/login',
    ];
    return loginPatterns.any((p) => url.contains(p));
  }

  bool _matchesPaymentUrl(String url) {
    const paymentPatterns = [
      '/payment', '/pay', '/checkout', '/billing',
      '/cart/checkout', '/order/payment',
    ];
    return paymentPatterns.any((p) => url.contains(p));
  }

  bool _matchesCheckoutUrl(String url) {
    const checkoutPatterns = ['/checkout', '/order/checkout', '/shop/checkout'];
    return checkoutPatterns.any((p) => url.contains(p));
  }

  // ─────────────────────────────────────────────────────────
  // Chrome 管理
  // ─────────────────────────────────────────────────────────

  /// 確保 Chrome 已啟動。lazy 啟動，多任務共用。
  Future<Browser?> _ensureBrowser(
    void Function(double progress, String message) onProgress,
  ) async {
    if (_browser != null && !_browser!.isConnected) {
      _browser = null;
    }
    if (_browser != null) return _browser;
    if (_starting) {
      // 等待啟動中
      for (var i = 0; i < 30; i++) {
        await Future.delayed(const Duration(milliseconds: 500));
        if (_browser != null) return _browser;
        if (!_starting) break;
      }
      return _browser;
    }

    _starting = true;
    onProgress(0.05, '正在啟動 Chrome 瀏覽器...');

    try {
      _browser = await puppeteer.launch(
        headless: false, // 設計文件要求使用者看得到瀏覽器
        args: [
          '--no-first-run',
          '--no-default-browser-check',
          '--disable-background-timer-throttling',
        ],
      );
      debugPrint('[BrowserAutomation] Chrome started successfully');
      return _browser;
    } catch (e) {
      debugPrint('[BrowserAutomation] Failed to start Chrome: $e');
      _starting = false;
      return null;
    } finally {
      _starting = false;
    }
  }

  // ─────────────────────────────────────────────────────────
  // 工具方法
  // ─────────────────────────────────────────────────────────

  bool _isCancelled(String taskId) {
    return _cancelledTasks[taskId] == true;
  }

  /// 關閉 Chrome 瀏覽器。App 關閉時呼叫。
  Future<void> dispose() async {
    await _browser?.close();
    _browser = null;
  }

  /// Chrome 是否正在運行
  bool get isRunning => _browser != null && _browser!.isConnected;
}
