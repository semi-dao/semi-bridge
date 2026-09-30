# Semi Bridge

**The Bridge Between Humans and AI.**

[English](README_EN.md) | [繁體中文](README.md)

[![CI](https://github.com/semi-dao/semi-bridge/actions/workflows/ci.yml/badge.svg)](https://github.com/semi-dao/semi-bridge/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/semi-dao/semi-bridge)](https://github.com/semi-dao/semi-bridge/releases)
[![License](https://img.shields.io/badge/license-Apache--2.0-blue)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-macOS%20%C2%B7%20Flutter-02569B)](https://flutter.dev)

> 一座讓人類與 AI「共同看見」的橋。不是工具，是同一個視野裡的夥伴。

![Semi Bridge — 畫布](docs/screenshots/canvas.webp)

![Semi Bridge — 大腦圖譜](docs/screenshots/brain-galaxy.webp)

<sub>點擊任一星點，右側展開完整節點資訊——檔案、照片、記憶都能直接開啟。</sub>

![Semi Bridge — 星系節點詳情](docs/screenshots/heart-galaxy-detail.webp)

**⚠️ 早期開發中（Work in Progress）** — 功能未齊、隨時 refactor。歡迎圍觀程式碼與理念、參與討論；暫不建議日常使用，也未提供安裝包。

## 這是什麼

Semi Bridge 是一個 Flutter 桌面 App，讓人類和 AI agent 在**同一塊畫布上共同工作**——你看見的，就是 AI 看見的；AI 正在做的，你看得見過程。

核心信念：

- **共視（Covision）**：不是「人下命令、AI 執行」，是「共同看見 → 共同感覺 → 共同建造」
- **資料主權**：你的對話、記憶、數位資產屬於你。金鑰匙原則、路徑主權、除痕不等於刪除
- **AI 自由 + Token 自由**：模型可替換、provider 可攜、不鎖死任何雲端廠商
- **為開源社群與 SemiDAO 而生**：這座橋本身就是公共財

## 核心功能（現況）

- 🎨 **畫布（Canvas）**：專案可視化工作區，節點＝工作流步驟，AI agent 的每一步在畫布上看得到
- 🧠 **大腦圖譜（Brain Galaxy）**：你的資料變成 3D 星系——本地向量資料庫、語意搜尋、記憶衰減
- 🤝 **夥伴系統（Companions）**：多 AI agent 共存，各自有身份、記憶、成長
- 🔑 **金鑰匙（Golden Keys）**：API key 鎖定後全 App 自動偵測已設金鑰、四處通行
- 🛡️ **資料主權閘門（DataPathGate）**：對外 HTTP 分級攔截＋自動除痕
- 📊 **Tier 設計系統**：33 個語意化 tier，主題包一鍵換全 App 外觀
- 🔧 **可改裝（Modding-first）**：主題/星系/工作流免編譯改裝，新按鈕新節點有完整誕生術——見 [Modding Guide](docs/opensource/MODDING_GUIDE.md)

### 背景系統（看不見的守護者）

全部源自真實事故的兩天偵查（「電腦很遲鈍連打字都難」→ 七座金礦）——詳細說明見 **[FEATURES.md](docs/FEATURES.md)**：

- 🔄 **系統活動中心**：背景任務全部可視化——忙碌必可見，安靜即隱形
- ⏸ **溫和暫停**：任何背景工作可 ⏸ 讓路給你，繼續時零重做
- 🧠 **大腦自動復活**：本地模型引擎死了自動爬起來（引擎級，換任何 GGUF 都受保護）
- 🌲 **樹指紋快取**：重啟不重掃——80 分鐘的全量掃描變秒級
- 🔒 **嵌入狀態機**：資料庫層強制不可逆，任務互踩慘案絕跡
- 🧪 **模型實驗室**：用自己的照片盲測本地模型，一鍵採用——見 [MODEL_LAB](docs/MODEL_LAB.md) 與 [盲測報告](docs/benchmarks/VISION_MODEL_BENCHMARK_2026-09.md)

## 快速開始（開發者）

```bash
git clone https://github.com/semi-dao/semi-bridge.git
cd semi-bridge
flutter pub get
flutter run -d macos
```

需要 Flutter 穩定版。目前主要支援 macOS 桌面。

> **開發路徑覆寫**：部分本地服務（星系資源、agent 工具）預設在 `~/Developer/bridge_app`
> 找專案根。clone 到別的位置時，設定環境變數 `BRIDGE_APP_HOME=/path/to/semi-bridge`
> 即可對位。

## 專案結構

```
lib/
  screens/     # 畫面（chat、canvas、vault、companion…）
  services/    # 核心（agent loop、向量DB、記憶、語音、主權閘門…）
  widgets/     # 元件（含 Tier 設計系統）
  models/      # 資料模型
  theme/       # BridgeDS 設計系統
docs/          # 設計規範、宣言、架構地圖
```

## 宣言與設計文件

![Semi Bridge — 羅盤系統圖譜](docs/screenshots/compass-graph.webp)

<sub>羅盤圖譜：App 的每個器官是一個節點、線＝依賴連動——這一節的每份文件，講的都是圖上某一個器官。</sub>

- [共視宣言（Covision Manifesto）](docs/COVISION_MANIFESTO.md) — 產品定位錨點
- [資料主權宣言（Data Sovereignty Manifesto）](docs/DATA_SOVEREIGNTY_MANIFESTO.md)
- [🧭 羅盤系統（Compass System）](docs/COMPASS_SYSTEM.md) — 人機共視的決策中樞：器官地圖 + 規則中心 + 軍醫藥箱，Agent 與人類讀同一份真相
- [🌳 生命樹（Life Tree）](docs/LIFE_TREE.md) — 失敗即數位資產：歷史樹+反思樹雙幹、羅盤精靈儀表、做夢節律——走對走錯都記錄，自我進化有資料結構
- [🧠 向量大腦（Vector Brain）](docs/VECTOR_BRAIN.md) — App 的記憶器官：四種記憶形態、混合搜尋、本地嵌入管線
- [🔗 八大系統串聯縱覽（System Wiring）](docs/SYSTEM_WIRING.md) — 對話-畫布-向量DB-圖譜-嵌入-羅盤-金鑰匙-本地模型：一句話如何流過整顆大腦
- [📦 大搬家（Hermes Migration）](docs/HERMES_MIGRATION.md) — 把 Agent 接回家：人格、記憶、排程、對話史無損搬遷——搬的是副本，原檔不動
- [開源宣言](docs/opensource/MANIFESTO_DRAFT.md) — 為何公開、相信什麼、不公開什麼
- [🔧 Modding Guide](docs/opensource/MODDING_GUIDE.md) — 把這台車改成你的樣子（四層改裝）
- [v0.4.0 開光 LightUp](docs/V040_AGENT_AS_USER_DESIGN_INPUTS.md) — Agent-as-User：7 個語意工具讓 Agent 成為真正的使用者
- [設計系統](docs/BRIDGE_TIER_SYSTEM.md) · [統合設計語言](docs/BRIDGE_UNIFIED_DESIGN_LANGUAGE.md)
- [架構地圖](docs/APP_ARCHITECTURE_MAP.md)

## 參與

歡迎 issue 討論、理念交流。目前程式碼仍在快速變動，大型 PR 建議先開 issue 對齊方向。

- 💬 [Issue templates](.github/ISSUE_TEMPLATE/) — bug 回報與功能發想
- 🤝 [CONTRIBUTING.md](CONTRIBUTING.md) — PR 前的設計系統鐵則
- 🔒 [SECURITY.md](SECURITY.md) — 安全問題回報管道
- 📋 [CHANGELOG.md](CHANGELOG.md) — 版本哲學與里程碑

## License

Apache-2.0（見 [LICENSE](LICENSE)）

---

*這座橋由人類與 AI 一起建造。過程，本身就是見證。*
