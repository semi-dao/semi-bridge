#!/usr/bin/env python3
"""
tool/fix_const_widget_bridge_safe.py

[小葵 2026-08-04] 安全版：拿掉 const widget 內含 BridgeDSColors.of(context) 的 const 標記

只處理單一 widget（例如 const Text(...)），不處理包含子 widget 的容器（例如 const Expanded(child: Text(...))）。
因為容器層的 const 拿掉只會去掉「編譯期常數化」優化，不影響運行。

策略：
  1. 找 "const Text("、"const Icon("、"const RichText("、"const Text.rich(" 等（純 widget）
  2. 用平衡括號掃描到對應的 ")"
  3. 中間包含 "BridgeDSColors.of(context)" → 拿掉這個 const
"""

import re
from pathlib import Path

PROJECT_ROOT = Path("<HOME>/Developer/bridge_app")

FILES = [
    "lib/screens/companion_list_screen.dart",
    "lib/screens/companion_create_screen.dart",
    "lib/screens/companion_appearance_screen.dart",
]

# 只處理單一 widget（不含子 widget 的容器）
SIMPLE_WIDGETS = [
    "Text", "Icon", "RichText", "Text.rich",
    "Tooltip", "IconTheme", "DefaultTextStyle",
]

# 容器 widget — 也安全（拿掉 const 不影響語意，只去掉編譯期常數化優化）
CONTAINER_WIDGETS = [
    "Expanded", "SizedBox", "Padding", "Center", "Align",
    "Row", "Column", "Container", "Stack", "Positioned",
    "Flexible", "Wrap", "Stack",
    "BorderSide", "BorderRadius", "Border.all", "BoxDecoration",
    "EdgeInsets", "TextStyle", "InputDecoration",
    "LinearGradient", "RadialGradient", "SweepGradient",
    "BoxShadow", "CircleBorder", "RoundedRectangleBorder",
]
ALL_WIDGETS = SIMPLE_WIDGETS + CONTAINER_WIDGETS


def find_matching_paren(content: str, start: int) -> int:
    """從 start（含左括號）找到對應的右括號位置。跳過字串。"""
    depth = 0
    i = start
    while i < len(content):
        c = content[i]
        if c == "(":
            depth += 1
        elif c == ")":
            depth -= 1
            if depth == 0:
                return i
        elif c == '"' or c == "'":
            quote = c
            i += 1
            while i < len(content):
                if content[i] == "\\":
                    i += 2
                    continue
                if content[i] == quote:
                    break
                i += 1
        i += 1
    return -1


def fix_file(path: Path) -> int:
    content = path.read_text()
    changes = 0
    widget_pat = re.compile(
        rf"(?<![A-Za-z0-9_])(const)\s+({'|'.join(re.escape(w) for w in ALL_WIDGETS)})\("
    )

    # 從後往前處理（避免前面的修改影響後面的 index）
    matches = list(widget_pat.finditer(content))
    matches.reverse()

    for m in matches:
        const_start = m.start()
        # m.start(1) 是 "const" 的開始
        const_word_start = m.start(1)
        const_word_len = 5  # "const"
        paren_start = m.end() - 1  # "(" 的位置
        paren_end = find_matching_paren(content, paren_start)
        if paren_end < 0:
            continue
        inner = content[paren_start + 1:paren_end]
        if "BridgeDSColors.of(context)" in inner:
            # 拿掉 const（包括前面的空格）
            # const_start 可能是 "const" 也可能是空白
            # 從 const_word_start 開始刪除 5 個字元 + 後續的空白
            new_content_start = const_word_start + const_word_len
            # 跳過 const 後面的空白
            while new_content_start < len(content) and content[new_content_start] == " ":
                new_content_start += 1
            # 但要保留原本的空白結構（通常是 "const Text" 變 "Text"，保留一個空格）
            # 簡化：刪除 "const" 這 5 字元
            content = content[:const_word_start] + content[const_word_start + const_word_len:]
            changes += 1

    if changes > 0:
        path.write_text(content)

    return changes


def main():
    for rel in FILES:
        path = PROJECT_ROOT / rel
        if not path.exists():
            continue
        print(f"=== 處理 {rel} ===")
        n = fix_file(path)
        print(f"  修掉 {n} 個 const widget")


if __name__ == "__main__":
    main()