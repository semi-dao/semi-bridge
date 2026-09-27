# 設計審計結果 — bridge_desktop_screen.dart

## Critical

### 1. Hardcoded Colors.white (行 3303)
- `color: Colors.white,` → 應改為 `BridgeDS.textPrimary`

### 2. Hardcoded Color(0x00000000) (行 4253)
- `iconColor = const Color(0x00000000)` → 應改為 `BridgeDS.iconDefault` 或 `Colors.transparent`

## Major

### 字體階層破壞 — .copyWith(fontSize:) 
所有用 .copyWith 修改 fontSize 的地方都破壞了 BridgeDS 字體階層系統：

| 行號 | 目前 | 應改為 |
|------|------|--------|
| 652 | headingM.copyWith(fontSize: 18) | headingM（不覆寫） |
| 820 | headingM.copyWith(fontSize: 18) | headingM |
| 943 | headingM.copyWith(fontSize: 18) | headingM |
| 1060 | headingM.copyWith(fontSize: 18) | headingM |
| 1109 | headingM.copyWith(fontSize: 18) | headingM |
| 1673 | headingM.copyWith(fontSize: 22) | headingL |
| 1962 | headingM.copyWith(fontSize: 18) | headingM |
| 1967 | caption.copyWith(fontSize: 13) | caption（不覆寫） |
| 2053 | labelMono.copyWith(fontSize: 12) | labelMono |
| 2059 | caption.copyWith(fontSize: 11) | caption |
| 2483 | headingM.copyWith(fontSize: 18) | headingM |
| 2504 | labelMono.copyWith(fontSize: 14) | labelMono |
| 2644 | headingM.copyWith(fontSize: 22) | headingL |
| 2863 | headingM.copyWith(fontSize: 22) | headingL |
| 2893 | headingM.copyWith(fontSize: 22) | headingL |
| 2942 | headingM.copyWith(fontSize: 22) | headingL |
| 2954 | caption.copyWith(fontSize: 15) | bodyS |
| 3079 | headingM.copyWith(fontSize: 22) | headingL |
| 3103 | headingM.copyWith(fontSize: 22) | headingL |
| 3155 | headingM.copyWith(fontSize: 22) | headingL |

### 字體階層破壞 — TextStyle 直接指定 fontSize
| 行號 | 目前 fontSize | 問題 |
|------|--------------|------|
| 656 | 14 | 應用 BridgeDS token |
| 702 | 16 | 應用 BridgeDS token |
| 704 | 14 | 應用 BridgeDS token |
| 879 | 14 | 應用 BridgeDS token |
| 881 | 12 | 應用 BridgeDS token |
| 953 | 14 | 應用 BridgeDS token |
| 955 | 12 | 應用 BridgeDS token |
| 1079 | 14 | 應用 BridgeDS token |
| 1114 | 14 | 應用 BridgeDS token |
| 1978 | 11 | 應用 BridgeDS token |
| 2951 | 20 | 應用 BridgeDS token |
| 3831 | 14 | 應用 BridgeDS token |

## Minor

### 非 8pt 網格間距 — SizedBox
| 行號 | 目前值 | 建議 |
|------|--------|------|
| 874 | width: 10 | 8 |
| 880 | height: 2 | 0（移除）或保留（行高微調可接受） |
| 1571 | width: 10 | 8 |
| 1578 | width: 6 | 8 |
| 1625 | width: 12 | 8 或 16 |
| 1675 | width: 12 | 8 或 16 |
| 1836 | height: 4 | 8 |
| 1882 | width: 12 | 8 或 16 |
| 1960 | height: 12 | 8 或 16 |
| 1963 | height: 4 | 8 |
| 2450 | width: 4 | 8 |
| 2456 | height: 4 | 8 |
| 2478 | width: 12 | 8 或 16 |

### 非 8pt 網格間距 — EdgeInsets
| 行號 | 目前值 | 建議 |
|------|--------|------|
| 670 | vertical: 14 | 16 |
| 865 | horizontal: 12, vertical: 10 | 16, 8 |
| 1077 | vertical: 14 | 16 |
| 1128 | vertical: 14 | 16 |
| 1973 | vertical: 2 | 0 或 8 |
| 2167 | horizontal: 5, vertical: 1 | 8, 0 |
| 2180 | left: 4 | 8 |
| 2188 | left: 4 | 8 |
| 2196 | left: 6 | 8 |
| 2243 | left: 4 | 8 |
| 2251 | left: 6 | 8 |
| 2288 | horizontal: 5, vertical: 1 | 8, 0 |
| 2301 | left: 4 | 8 |
| 2309 | left: 4 | 8 |
| 2317 | left: 6 | 8 |
| 2352 | horizontal: 5, vertical: 1 | 8, 0 |
| 2364 | left: 4 | 8 |
| 2372 | left: 4 | 8 |
| 2380 | left: 6 | 8 |
| 2517 | bottom: 2 | 0 或 8 |

## Colors.transparent（可接受）
行 647, 815, 938, 1055, 1102 — surfaceTintColor: Colors.transparent（Material widget 標準用法，可接受）
行 2519, 2528, 3007, 3011 — 條件式透明（可接受）
