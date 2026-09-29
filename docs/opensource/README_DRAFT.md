# Semi Bridge

**The Bridge Between Humans and AI.**

> 一座讓人類與 AI「共同看見」的橋。不是工具，是同一個視野裡的夥伴。

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

## 快速開始（開發者）

```bash
git clone https://github.com/semiwasabi128/semi-bridge.git
cd semi-bridge
flutter pub get
flutter run -d macos
```

需要 Flutter 穩定版。目前主要支援 macOS 桌面。

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

- [共視宣言（Covision Manifesto）](docs/COVISION_MANIFESTO.md) — 產品定位錨點
- [資料主權宣言（Data Sovereignty Manifesto）](docs/DATA_SOVEREIGNTY_MANIFESTO.md)
- [🔧 Modding Guide](docs/opensource/MODDING_GUIDE.md) — 把這台車改成你的樣子（四層改裝）
- [設計系統](docs/BRIDGE_TIER_SYSTEM.md) · [統合設計語言](docs/BRIDGE_UNIFIED_DESIGN_LANGUAGE.md)
- [架構地圖](docs/APP_ARCHITECTURE_MAP.md)

## 參與

歡迎 issue 討論、理念交流。目前程式碼仍在快速變動，大型 PR 建議先開 issue 對齊方向。

## License

Apache-2.0（見 [LICENSE](LICENSE)）

---

*這座橋由人類與 AI 一起建造。過程，本身就是見證。*
