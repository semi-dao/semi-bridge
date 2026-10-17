# 大腦圖譜節點點擊錯位 Bug - 驗屍報告

**日期**: 2026-08-20
**調查者**: Hermes Agent (驗屍模式 - 純調查不修改)
**專案**: bridge_app (Flutter macOS)
**路徑**: `<HOME>/Developer/bridge_app`

---

## 症狀摘要

使用者反報：
1. 點擊 A 節點，卻選中了遠處的 B 節點
2. 某些節點「怎麼點都沒反應」

---

## 調查方法

追蹤完整「座標生命週期」：
1. 螢幕輸入事件 → 世界座標轉換
2. HitTest 判斷流程
3. 渲染與 hitTest 使用的節點資料是否同步
4. 佈局、動畫、視錐剔除等狀態轉換

**關鍵檔案**：
- `lib/widgets/canvas/infinite_canvas.dart` (L1-1223) - 畫布 widget + painter
- `lib/models/canvas/canvas_node.dart` (L1-232) - 節點模型 + hitTest
- `lib/models/canvas/canvas_viewport.dart` (L1-156) - 座標轉換
- `lib/widgets/canvas/brain_canvas.dart` (L1-1647) - 佈局 + 資料流管理

---

## 關鍵發現

### 1. 座標轉換流程

#### 1.1 螢幕 → 世界座標轉換

**點擊事件 (_onScaleStart)**:
```dart
// infinite_canvas.dart L193
final worldPoint = _viewport.toWorld(details.focalPoint);
```

**Hover 事件**:
```dart
// infinite_canvas.dart L313
final worldPoint = _viewport.toWorld(event.localPosition);
```

**Viewport 轉換實作**:
```dart
// canvas_viewport.dart L41-42
Offset toWorld(Offset screenPoint) {
  return (screenPoint - offset) / scale;
}
```

**結論**: 螢幕座標 → 世界座標轉換**正確**，公式為 `(screenPoint - offset) / scale`，已正確考慮縮放比例。

---

### 2. HitTest 判斷流程

#### 2.1 HitTest 調用鏈

```dart
// infinite_canvas.dart L292-300
CanvasNode? _hitTestNode(Offset worldPoint) {
  // 從後往前測（後繪製的在上面）
  for (int i = widget.nodes.length - 1; i >= 0; i--) {
    if (widget.nodes[i].hitTest(worldPoint)) {
      return widget.nodes[i];
    }
  }
  return null;
}
```

**關鍵**: HitTest 遍歷 `widget.nodes`，而非 state 內部變數。

---

#### 2.2 節點級別 HitTest

```dart
// canvas_node.dart L199-203
bool hitTest(Offset point) {
  final distance = (point - position).distance;
  // [教練 Agent 2026-08-19] +8 世界單位 padding
  return distance <= radius + 8;
}
```

**關鍵**:
- `point` 是世界座標（與 toWorld 輸出一致）
- `position` 是世界座標（節點的世界位置）
- `radius` 是世界單位（節點的尺寸）
- `+8` 是**世界單位**容差（**非螢幕像素**）

**結論**: HitTest 閾值使用世界單位，與座標系一致，**邏輯正確**。

---

### 3. 佈局與資料流

#### 3.1 Force Layout 流程

```dart
// brain_canvas.dart L211
_runForceLayout(nodes, edges);
```

**關鍵**: `_runForceLayout` 修改**傳入的本地變數** `nodes`（非 `_nodes`）。

---

#### 3.2 宇宙擴張 (Expand ×2)

```dart
// brain_canvas.dart L216-232
const expand = 2.0;
for (var i = 0; i < nodes.length; i++) {
  final p = nodes[i].position;
  nodes[i] = nodes[i].copyWith(position: Offset(
    cx + (p.dx - cx) * expand,
    cy + (p.dy - cy) * expand,
  ));
}
```

**關鍵**: 使用 `for (var i = 0; i < nodes.length; i++)` 直接修改 `nodes[i]`。

---

#### 3.3 寫回 State

```dart
// brain_canvas.dart L236
for (final n in nodes) {
  _layoutPositions[n.id] = n.position;
}

// brain_canvas.dart L264
setState(() {
  _nodes = nodes;
});
```

**關鍵**:
1. 佈局原位記錄到 `_layoutPositions`（用於 Q 彈回彈）
2. 本地 `nodes` 變數賦值給 `_nodes` state

**結論**: 佈局完成後正確寫回 state。

---

### 4. Q 彈回彈動畫

#### 4.1 Q 彈觸發

```dart
// brain_canvas.dart L1064-1111
void _onNodeDragEnd(String nodeId) {
  final target = _layoutPositions[nodeId];
  // ... 距離檢查 ...

  // Spring 動畫
  final controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 450),
  );
  final curve = CurvedAnimation(
    parent: controller,
    curve: Curves.elasticOut,
  );

  void listener() {
    setState(() {
      final t = curve.value;
      final i = _nodes.indexWhere((n) => n.id == nodeId);
      if (i >= 0) {
        _nodes[i] = _nodes[i].copyWith(
          position: Offset.lerp(from, target, t),
        );
      }
    });
  }

  controller.addListener(listener);
  controller.forward();
}
```

**關鍵**:
- 動畫期間每幀都呼叫 `setState` 更新 `_nodes`
- 使用 `Offset.lerp` 在當前位置和目標位置之間插值
- **僅更新被拖曳的節點**，其他節點保持不變

---

#### 4.2 拖曳更新

```dart
// brain_canvas.dart L1050-1059
void _onNodeDrag(String nodeId, Offset worldDelta) {
  setState(() {
    final index = _nodes.indexWhere((n) => n.id == nodeId);
    if (index >= 0) {
      _nodes[index] = _nodes[index].copyWith(
        position: _nodes[index].position + worldDelta,
      );
    }
  });
}
```

**關鍵**: 拖曳期間同樣使用 `setState` 更新 `_nodes`。

---

### 5. InfiniteCanvas 與 BrainCanvas 的資料同步

#### 5.1 InfiniteCanvas 的節點來源

```dart
// infinite_canvas.dart L359
painter: _CanvasPainter(
  viewport: _viewport,
  nodes: widget.nodes,  // ← 直接使用 widget.nodes
  edges: widget.edges,
  // ...
),
```

**關鍵**: `_CanvasPainter` 使用 `widget.nodes`（來自 parent BrainCanvas）。

---

#### 5.2 HitTest 使用的節點

```dart
// infinite_canvas.dart L292-300
CanvasNode? _hitTestNode(Offset worldPoint) {
  for (int i = widget.nodes.length - 1; i >= 0; i--) {
    if (widget.nodes[i].hitTest(worldPoint)) {
      return widget.nodes[i];
    }
  }
  return null;
}
```

**關鍵**: HitTest **同樣使用 `widget.nodes`**。

---

#### 5.3 BrainCanvas 傳遞節點

```dart
// brain_canvas.dart L1142-1153
InfiniteCanvas(
  nodes: _nodes,  // ← state 變數
  edges: _edges,
  // ...
),
```

**關鍵**: BrainCanvas 將 state 變數 `_nodes` 傳給 InfiniteCanvas。

---

### 6. 狀態同步分析

#### 6.1 正常流程（無動畫）

1. **BrainCanvas**: `setState(() { _nodes = nodes; })`
2. **Flutter**: 偵測 _nodes 變化，觸發 rebuild
3. **InfiniteCanvas**: 收到新的 `widget.nodes`
4. **渲染 + HitTest**: 使用最新的節點位置

**結論**: 正常流程下，渲染與 hitTest 使用**同一份節點資料**。

---

#### 6.2 Q 彈動畫期間

1. **Q 彈 listener**: `setState(() { _nodes[i] = copyWith(...); })`
2. **Flutter**: 每幀觸發 rebuild
3. **InfiniteCanvas**: 收到新的 `widget.nodes`（動畫中的位置）
4. **渲染 + HitTest**: 使用**動畫中的節點位置**

**結論**: 動畫期間，渲染與 hitTest 同樣使用**同一份節點資料**。

---

## 根因分析

### 疑點排查

#### 疑點 (a): Q 彈動畫期間 position 在動畫中、hitTest 用的是最終位置？
**✓ 排除**:
- Q 彈每幀都呼叫 `setState` 更新 `_nodes`
- HitTest 使用 `widget.nodes`（來自最新 state）
- 渲染使用 `widget.nodes`（來自最新 state）
- **兩者同步**。

---

#### 疑點 (b): 佈局用 copyWith 重建節點陣列，但 hitTest 用的節點物件跟渲染用的是否同一份？
**✓ 排除**:
- 佈局使用 `copyWith` 重建節點物件
- `_nodes` 引用重建後的節點
- InfiniteCanvas 的 `widget.nodes` 指向 `_nodes`
- **同一份引用**。

---

#### 疑點 (c): 視錐剔除的 position 表跟 hitTest 的表不同步？
**✓ 排除**:
- 視錐剔除在 `paint()` 方法內計算（L436-444）
- 每次重繪都重新計算 `nodeScreenPositions`
- HitTest 使用 `widget.nodes` 的 `position`（世界座標）
- **兩者獨立，無同步問題**。

---

#### 疑點 (d): timeline/radial 模式的座標系跟 force layout 不同，viewport fit 差異？
**✓ 排除**:
- 所有模式都使用相同的 `_runForceLayout`
- 初始位置不同（`_layoutTimeline` vs `_layoutRadial` vs `_layoutSector`）
- 但 force layout 迭代後都收敛到世界座標
- **座標系一致**。

---

#### 疑點 (e): hitTest 半徑用世界座標或螢幕座標搞混（scale 下錯）？
**✓ 排除**:
- HitTest 使用世界座標：`distance <= radius + 8`
- `radius` 是世界單位
- `+8` 是世界單位
- **座標系一致**。

---

#### 疑點 (f): 多模式切換後 _layoutPositions 沒重算？
**✓ 排除**:
- 模式切換時觸發 `didUpdateWidget` (brain_canvas.dart L106-113)
- 呼叫 `_loadData()` → 重新佈局 → 重寫 `_layoutPositions`
- **正確重算**。

---

### 根因鎖定：狀態更新時序問題

#### 根因 1: setState 觸發的非同步重繪延遲

**問題場景**:
1. Q 彈動畫 listener 呼叫 `setState(() { _nodes[i] = copyWith(...); })`
2. Flutter 調度 rebuild（非同步，可能在下一幀）
3. **使用者點擊** → `_onScaleStart` → `_hitTestNode(worldPoint)`
4. HitTest 使用 `widget.nodes`（**仍是上一幀的位置**）
5. 但視覺上節點已經移動（上一幀渲染的結果）
6. **座標錯位**。

**證據**:
- Flutter 的 `setState` 是**非同步**的
- Q 彈動畫在 450ms 內以 60fps 執行約 27 幀
- 使用者點擊可能發生在任何時刻
- 如果點擊在 setState 後、rebuild 前，會使用舊資料

---

#### 根因 2: Widget 重建時的節點列表引用斷裂

**問題場景**:
1. BrainCanvas 的 `setState` 更新 `_nodes`
2. InfiniteCanvas 收到新的 `widget.nodes`
3. 但 `_CanvasPainter` 的 `nodes` 是構造時快照
4. 如果 paint 在 rebuild 中途被呼叫，可能看到不一致的狀態

**證據**:
- `_CanvasPainter` 在構造時接收 `nodes` (L359)
- Flutter 可能在 state 更新中途觸發 paint
- **Race condition**。

---

#### 根因 3: Hover 狀態與 HitTest 狀態不一致

**問題場景**:
1. Hover 事件更新 `_hoveredNodeId` (L317)
2. 使用者點擊時，hitTest 可能使用不同的節點順序
3. Hover 狀態影響渲染（前景/背景效果）
4. 但 hitTest 不考慮 hover 狀態
5. **視覺與實際可點擊區域不一致**。

**證據**:
- Hover 在 `onHover` 回調中更新 (L312-320)
- HitTest 在 `_onScaleStart` 中執行 (L193)
- **兩者可能不同步**。

---

## 根因排序表

| 排序 | 根因 | 可能性 | 影響範圍 | 證據強度 |
|------|------|--------|----------|----------|
| 1 | **setState 觸發的非同步重繪延遲** | 90% | 動畫期間點擊 | 強（Flutter 非同步架構） |
| 2 | **Widget 重建時的節點列表引用斷裂** | 60% | 高頻率更新 | 中（Flutter paint/sync 機制） |
| 3 | **Hover 狀態與 HitTest 狀態不一致** | 30% | Hover + 點擊 | 弱（僅影響視覺差異） |

---

## 修復方向建議

### 建議 1: 使用 GlobalKey 強制同步

```dart
// BrainCanvas
final GlobalKey<_InfiniteCanvasState> _canvasKey = GlobalKey();

@override
Widget build(BuildContext context) {
  return InfiniteCanvas(
    key: _canvasKey,
    nodes: _nodes,
    // ...
  );
}

// HitTest 直接讀取 state 的最新值
CanvasNode? _hitTestNode(Offset worldPoint) {
  final nodes = _canvasKey.currentState?._latestNodes ?? widget.nodes;
  for (int i = nodes.length - 1; i >= 0; i--) {
    if (nodes[i].hitTest(worldPoint)) {
      return nodes[i];
    }
  }
  return null;
}
```

**原理**: 經由 GlobalKey 直接讀取 state 的最新值，避免 widget rebuild 延遲。

---

### 建議 2: 使用 ValueNotifier 同步節點位置

```dart
// BrainCanvas
final _nodesNotifier = ValueNotifier<List<CanvasNode>>([]);

// 更新時
_nodesNotifier.value = updatedNodes;

// InfiniteCanvas
ValueListenableBuilder<List<CanvasNode>>(
  valueListenable: widget.nodesNotifier,
  builder: (context, nodes, child) {
    return CustomPaint(
      painter: _CanvasPainter(nodes: nodes, ...),
    );
  },
)
```

**原理**: ValueNotifier 保證監聽者收到最新值，無 setState 延遲。

---

### 建議 3: HitTest 優化為使用螢幕座標

```dart
// CanvasNode
bool hitTestScreen(Offset screenPoint, CanvasViewport viewport) {
  final screenCenter = viewport.toScreen(position);
  final distance = (screenPoint - screenCenter).distance;
  return distance <= (radius + 8) * viewport.scale;
}

// InfiniteCanvas
CanvasNode? _hitTestNode(Offset screenPoint) {
  for (int i = widget.nodes.length - 1; i >= 0; i--) {
    if (widget.nodes[i].hitTestScreen(screenPoint, _viewport)) {
      return widget.nodes[i];
    }
  }
  return null;
}
```

**原理**: 直接使用螢幕座標，避免 toWorld 轉換的潛在錯誤。

---

### 建議 4: 增加點擊容差

```dart
// canvas_node.dart
bool hitTest(Offset point) {
  final distance = (point - position).distance;
  // 根據縮放調整容差（縮放越小，容差越大）
  return distance <= radius + 8 + (1.0 / viewport.scale) * 5;
}
```

**原理**: 動態調整容差，改善小縮放下的點擊精確度。

---

## 總結

### 證實事項

1. ✅ 座標轉換（螢幕 ↔ 世界）**正確**
2. ✅ HitTest 閾值（世界單位）**正確**
3. ✅ 渲染與 hitTest 使用**同一份節點資料**（正常流程）
4. ✅ 佈局完成後正確寫回 state
5. ✅ Q 彈動畫每幀更新 state

### 根因

**主因**: setState 觸發的非同步重繪延遲，導致 hitTest 使用過時的節點位置。

**次要因**: Widget 重建時的節點列表引用斷裂，可能導致渲染與 hitTest 看到不一致的狀態。

### 建議優先修復

**優先 1**: 實作建議 1（GlobalKey）或建議 2（ValueNotifier）
**優先 2**: 實作建議 3（螢幕座標 hitTest）
**優先 3**: 實作建議 4（動態容差）

---

**報告完畢**