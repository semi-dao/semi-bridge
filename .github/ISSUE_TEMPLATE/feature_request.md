name: 💡 功能想法 / Feature idea
description: 你看見了什麼問題、你期待看見什麼 / What problem you see, what you wish to see
labels: ["enhancement"]
body:
  - type: textarea
    id: problem
    attributes:
      label: 你看見的問題 / The problem you see
      description: 這個專案在乎「共同看見」——先說清楚你看見了什麼 / This project cares about shared seeing — describe what you see first
    validations:
      required: true
  - type: textarea
    id: solution
    attributes:
      label: 你期待看見的樣子 / What you wish it looked like
    validations:
      required: true
  - type: textarea
    id: alternatives
    attributes:
      label: 其他可能的做法 / Alternatives you've considered
    validations:
      required: false
