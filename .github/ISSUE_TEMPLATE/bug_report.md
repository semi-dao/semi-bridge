name: 🐛 Bug 回報 / Bug report
description: 有東西壞了——幫我們看見你看見的問題 / Something is broken — help us see what you saw
labels: ["bug"]
body:
  - type: textarea
    id: what-happened
    attributes:
      label: 發生了什麼 / What happened
      description: 用你的話描述。白話症狀是最好的線索 / Describe in your own words. Plain-language symptoms are the best clues.
      placeholder: 我做了…，然後我看到…，但我預期…
    validations:
      required: true
  - type: textarea
    id: steps
    attributes:
      label: 重現步驟 / Steps to reproduce
      description: 一步一步，讓我們能照著跑一次 / Step by step, so we can run it ourselves
      placeholder: |
        1. 開啟…
        2. 點選…
        3. …
    validations:
      required: true
  - type: textarea
    id: expected
    attributes:
      label: 你期待看見什麼 / What you expected to see
    validations:
      required: false
  - type: textarea
    id: logs
    attributes:
      label: 環境與截圖 / Environment & screenshots
      description: macOS 版本、App 版本、螢幕截圖（這是個重視「看見」的專案）/ macOS version, app version, screenshots (this project values seeing)
    validations:
      required: false
