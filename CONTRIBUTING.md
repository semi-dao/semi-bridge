# Contributing to Covision Bridge

謝謝你想貢獻！橋樑計畫歡迎人類與 AI 夥伴一起建造。

## 快速開始

```bash
git clone https://github.com/semiwasabi128/covision-bridge.git
cd covision-bridge
flutter pub get
flutter run -d macos
```

需求：Flutter ≥ 3.x、macOS 13+（桌面主要平台）、Xcode（macOS build）。

## 如何貢獻

1. Fork → 開分支（`feat/xxx`、`fix/xxx`）
2. 改完跑 `flutter analyze 2>&1 | tail -20` —— **零錯誤才算完成**
3. 有測試的改動請跑 `flutter test`，新功能請附測試
4. PR 描述請寫「做了什麼 + 為什麼」，截圖/GIF 更佳（這是個重視「看見」的專案）

## 設計系統鐵則

這個 repo 的 UI 紀律很嚴格，PR 前必讀：

- **[AGENTS.md](AGENTS.md)** 的「設計原則索引」——排版/色塊/Tier 系統三份規範
- 新 UI 程式碼：文字層級必走 Tier、顏色必走 `BridgeDSColors`、**禁** Material 預設色與 `Theme.of(context).textTheme`
- 違反設計系統的 PR 不會被 merge——這不是官僚，是整個 App 主題化的地基

## AI 夥伴貢獻者

本專案原生歡迎 agent 協作（本 repo 的多數程式碼就是人機共視的產物）：

- Agent 工作守則見 [AGENTS.md](AGENTS.md)
- 修改前必讀 [docs/APP_ARCHITECTURE_MAP.md](docs/APP_ARCHITECTURE_MAP.md)
- Agent 產生的 PR 一律標 `ai-assisted` label

## 回報問題

- Bug 請用 bug issue template，附重現步驟
- 功能想法請用 idea template——說清楚「你看見了什麼問題、你期待看見什麼」
- 安全問題請**不要**開 public issue，見 [SECURITY.md](SECURITY.md)

## 授權

貢獻即同意以 [LICENSE](LICENSE)（Apache-2.0）授權你的貢獻。
