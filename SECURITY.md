# Security Policy

## 支援版本

| 版本 | 支援狀態 |
|------|----------|
| 0.x（開發中） | ✅ 接受回報 |

## 回報弱點

**請勿就安全問題開 public issue。**

請透過 GitHub Security Advisories 回報：
1. Repo 頁面 → Security → Report a vulnerability
2. 或寄信到維護者的 GitHub 帳號（semiwasabi128）所登記的聯絡管道

回報時請包含：
- 問題類型（記憶體安全 / 注入 / 資料洩漏 / …）
- 重現步驟或 PoC
- 影響範圍評估（哪個模組、什麼資料會外洩）

我們會在 **72 小時內**回覆確認，修補後於 release notes 致謝（除非你希望匿名）。

## 特別注意面

這個 App 的特殊性：它管理使用者的**本地 AI 資料主權**（對話記憶、向量庫、API keys）。因此這幾類問題我們視為高優先：

- API key / token 的儲存與傳輸（本機檔案權限、defaults 洩漏）
- MCP 通道（localhost HTTP）的認證繞過
- 資料路徑 gate（DataPathGate）的攔截繞過
- 任何未經同意的外部網路連線

## Scope

- 本 repo 的程式碼（`lib/`、`macos/`、`tool/`、`tools/`）
- 不在 scope：第三方套件的漏洞（請回報上游）、使用者自行改 config 造成的暴露
