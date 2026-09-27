# Changelog

本專案版本跟隨**內部里程碑**（功能批次出貨），非連續遞增。公開 release 是里程碑快照。

## v0.1.0 — 2026-09-26 住棚節首發

首次公開 release。

- Canvas covision workspace（節點=工作流步驟，AI 動作即時可見）
- Brain Galaxy（本地向量 DB、語意搜尋、記憶衰減）
- Companion 系統（多 Agent 身分、記憶、成長）
- Golden Keys（API key 鎖定、全 App 自動偵測）
- DataPathGate（HTTP 流量分級 + 自動除痕）
- Tier 設計系統（33 語意 tier、主題包）
- Modding-first（主題/星系/工作流免重編譯）

## 版本哲學

- `pubspec.yaml` 的版本號 = 程式碼快照版本，可能領先公開 release（內部已出貨的功能會先進 main）。
- 公開 release tag = 對外里程碑。兩者暫時不同步屬正常，會在下一個公開里程碑對齊。

## v0.4.0 LightUp（開光）— 設計文件已公開

Agent-as-User：7 個語意工具讓 Agent 成為真正的使用者。設計輸入見 [docs/V040_AGENT_AS_USER_DESIGN_INPUTS.md](docs/V040_AGENT_AS_USER_DESIGN_INPUTS.md)——程式碼分批出貨中。
