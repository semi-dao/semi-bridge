---
name: wizard
description: 生成 bash 精靈帶人類走過「只有人能做的步驟」——開網址、說點哪裡、接值、寫進該寫的地方、每階段確認、顯示剩幾關。
trigger_keywords:
  - 精靈
  - 帶我設定
  - 引導設定
  - 一步一步設定
trigger_patterns:
  - "(做|寫|生)成(一個)?(安裝|設定|引導)?精靈"
  - "帶我(走|做).*(設定|註冊|綁定|驗證)"
priority: normal
version: 1
---

# Wizard — bash 精靈帶人走人類關卡

有些步驟**只有人能做**：在第三方 dashboard 上點按鈕、綁信用卡、掃 QR code。
手做很煩，每次跟 AI 重講一遍更煩。

**精靈** = 一支 bash 腳本，把整段手動程序變成關卡遊戲：
開該開的網址 → 說清楚點哪裡複製什麼 → 接住值 → 寫進該去的地方
（.env / GitHub secrets）→ 每關確認 → 顯示剩幾關。

**Agent 自己做得到的步驟不開精靈**——精靈是給人類關卡的。

## 四步流程

### 1. 盤點程序
先讀 repo 再問人（.env*、README、workflows/*——每個 secrets.* 引用
都是精靈要產出的值）。把關卡列表給使用者確認：每關名字＋產出什麼值。
使用者可能加、刪、換序。

### 2. 畫每關的路徑
每關寫出人類的精確路徑：「Dashboard → Developers → API keys →
Reveal test key → 複製」。**不知道 UI 長怎樣就明說**，查文件或問——
絕不發明可能不存在的步驟。

### 3. 寫精靈

```bash
#!/usr/bin/env bash
set -euo pipefail

TOTAL_STAGES=3
CURRENT_STAGE=0

stage() {
  CURRENT_STAGE=$((CURRENT_STAGE + 1))
  clear
  echo "═══ 關卡 $CURRENT_STAGE / $TOTAL_STAGES ═══"
  echo "  $1"
  echo
}
say()   { echo "▸ $*"; }
pause() { echo; read -r -p "按 Enter 繼續… "; echo; }
confirm() {
  local reply
  while true; do
    read -r -p "$1 (y/N) " reply
    case "$reply" in
      [Yy]*) return 0 ;;
      *) echo "已中止。"; exit 1 ;;
    esac
  done
}
ask()        { read -r -p "$1: " "$2"; }
ask_secret() { read -r -s -p "$1: " "$2"; echo; }
write_env()  {
  local key="$1" val="$2" f="${3:-.env}"
  touch "$f"
  if grep -q "^${key}=" "$f"; then
    sed -i '' "s|^${key}=.*|${key}=${val}|" "$f"
  else
    echo "${key}=${val}" >> "$f"
  fi
}
open_url() { (open "$1" 2>/dev/null || echo "請手動開：$1"); }

# ─── STAGES：每顆精靈只改這段以下 ───

stage "開啟服務並登入"
open_url "https://example.com/settings/keys"
say "左側選單 → Developers → API keys"
ask_secret "貼上出現的 key" API_KEY
write_env API_KEY "$API_KEY"
confirm "值已寫入 .env，繼續？"

echo "✅ 全部 $TOTAL_STAGES 關完成"
```

紀律：問值之前先開網址；機密一律 ask_secret（隱藏輸入）；
持久值一律 write_env；**不可逆動作前一律 confirm**；一關一個專注任務。

### 4. 驗證與交付
`bash -n script.sh` 語法檢查過才交。交付時說明：跑法、產出什麼、卡住怎麼辦。

## 壽命

精靈預設**用完即棄**。只有使用者明說「這要變成可重複的 setup 流程」才 commit 進 repo。
