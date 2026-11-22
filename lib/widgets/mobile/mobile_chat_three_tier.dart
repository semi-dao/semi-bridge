// 🗨 對話頁三層——[2026-11-21 Blue B案拍板] 工作區制（取代 SPEC §8.2 三類型桶）
//
// 結構（Discord 三層混合制，11-13 拍板版 → 11-21 B案重組）：
//   L1 左欄＝工作區列：「大廳」（projectDoorId=null，收未歸屬，固定第一）
//        ＋各 ProjectDoor（從 conversations 的 projectDoorId 去重 derives，
//        零新協定——gateway conversationList payload 已帶 projectDoorId，
//        desktop_bridge_local_gateway.dart L769）
//   L2 中欄＝選中工作區下的對話清單（「頻道」）：依 companionId 夥伴分組頭
//        ＋type 標記（general/projectCanvas/proactive）＋taskBinding 任務頻道標記
//   L3＝對話視圖（_buildThread 不動）
//
// [2026-11-21 Blue B案拍板] 取代 §8.2 三類型桶（💬⏰📁）——原 _bucket 分桶
//   邏輯退役，改工作區過濾＋companionId 分組。任務卡/回收桶/⋯選單全保留。
// Tier/BridgeDSColors 鐵則適用（禁寫死顏色、禁 Material 預設字級）。

import 'dart:async';
import 'package:flutter/material.dart';

import '../../services/desktop_bridge_gateway_protocol.dart';
import '../../services/mobile_bridge_client.dart';
import '../../theme/bridge_design_system.dart';
import '../../theme/bridge_motion.dart';
import '../../theme/tier.dart';
import '../../theme/tier_style.dart';
import '../../utils/conversation_tree_map.dart';

/// [2026-11-21 Blue B案拍板] 取代 §8.2 三類型桶枚舉——原 ChatRailTab
/// （general/scheduled/project）退役，L1 改工作區（大廳＋各 ProjectDoor）。

class MobileChatThreeTierPage extends StatefulWidget {
  const MobileChatThreeTierPage({super.key});

  @override
  State<MobileChatThreeTierPage> createState() =>
      _MobileChatThreeTierPageState();
}

class _MobileChatThreeTierPageState extends State<MobileChatThreeTierPage> {
  // [2026-11-21 Blue B案拍板] 取代 §8.2 三類型桶——L1 選中的工作區：
  // null＝「大廳」（projectDoorId 為 null 的未歸屬對話），非 null＝該 ProjectDoor id。
  String? _selectedDoorId;
  List<Map<String, dynamic>> _conversations = [];
  bool _loading = true;
  Map<String, dynamic>? _openConv; // 第 3 層：選中的對話（null=中欄模式）
  List<Map<String, dynamic>> _trash = [];
  bool _showTrash = false;
  List<Map<String, dynamic>> _messages = [];
  final TextEditingController _input = TextEditingController();
  bool _sending = false;
  Timer? _loadDebounce; // [11-15] 連線補抓防抖
  bool _loadingHistory = false;
  // [小隊動態 2026-11-17] squadChanged push 接線——桌面小隊增刪改→push→重抓清單
  StreamSubscription<BridgePushEvent>? _pushSub;
  Timer? _squadRefreshDebounce; // 小隊連環事件（開隊多隻工蜂）防風暴

  @override
  void initState() {
    super.initState();
    _load();
    // client 是 ChangeNotifier——連上且清單仍空 → 重抓（離線期 attempt 由 client 管）
    MobileBridgeClient.instance.addListener(_onClientChanged);
    // [小隊動態 2026-11-17] listen pushStream：收到 squadChanged → debounce 後
    // 重抓對話清單（小隊子對話出現在/消失於清單即時反映，不用手動下拉）。
    _pushSub = MobileBridgeClient.instance.pushStream.listen((event) {
      if (event.type != DesktopBridgeGatewayMessageType.squadChanged) return;
      _squadRefreshDebounce?.cancel();
      _squadRefreshDebounce = Timer(const Duration(milliseconds: 500), () {
        if (mounted) _load();
      });
    });
  }

  void _onClientChanged() {
    // [11-15 Blue 報案] 舊邏輯「清單空才重抓」——之後連線恢復不會自動刷新。
    // 改：連線恢復一律補抓（debounce 防抖）。
    if (MobileBridgeClient.instance.isConnected) {
      _loadDebounce?.cancel();
      _loadDebounce = Timer(const Duration(milliseconds: 800), _load);
    }
  }

  @override
  void dispose() {
    _loadDebounce?.cancel();
    _squadRefreshDebounce?.cancel();
    _pushSub?.cancel();
    _input.dispose();
    MobileBridgeClient.instance.removeListener(_onClientChanged);
    super.dispose();
  }

  Future<void> _openConversation(Map<String, dynamic> conv) async {
    setState(() {
      _openConv = conv;
      _loadingHistory = true;
      _messages = [];
    });
    final res = await MobileBridgeClient.instance
        .sendConversationHistory(conv['id'] as String? ?? '');
    if (!mounted) return;
    if (res != null && res['ok'] == true) {
      final payload = res['payload'] as Map<String, dynamic>;
      setState(() {
        _messages = (payload['messages'] as List? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _loadingHistory = false;
      });
    } else {
      setState(() => _loadingHistory = false);
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final res = await MobileBridgeClient.instance.sendConversationList();
    if (!mounted) return;
    if (res != null && res['ok'] == true) {
      final payload = res['payload'] as Map<String, dynamic>;
      final list = (payload['conversations'] as List? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      setState(() {
        _conversations = list;
        _trash = (payload['trash'] as List? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _loading = false;
      });
    } else {
      setState(() => _loading = false);
    }
  }

  // ── [2026-11-21 Blue B案拍板] 工作區制過濾（取代 §8.2 三類型桶 _bucket）
  //
  // L1 工作區清單 derives：conversationList 全量拉回後，從各對話的
  //   projectDoorId 去重得「有對話的門」清單（零新協定——gateway payload
  //   已帶 projectDoorId）。⚠️ 升級點：門的正式名稱需 ProjectDoorStore
  //   （桌面端本地檔案 store，手機拿不到），故暫以 id 前 8 碼顯示（_Rail 內）。
  //   桌端新建立、但尚無對話綁定的門，手機看不到（derives 限制，註明殘項）。
  List<String> get _doorIds {
    final ids = _conversations
        .map((c) => c['projectDoorId'] as String?)
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList()
      ..sort(); // 穩定排序（id 字典序），避免清單閃動
    return ids;
  }

  /// 選中工作區下的對話（L2「頻道」清單）：大廳＝projectDoorId null；
  /// 門＝projectDoorId 相符。taskBinding（排程/專案任務頻道）不排除——
  /// 改由卡片副標＋type 標記呈現（拍板：type 標記 general/projectCanvas/
  /// proactive＋taskBinding 任務頻道，不再是分桶依據）。
  ///
  /// [2026-11-21 章魚光呼吸樹] 輸出前套 Map 版樹排序（DFS 前序，母子相隨、
  /// 孤兒頂層、循環防護——契約同 ConversationTree，仿因 payload 是 Map 非物件）。
  List<Map<String, dynamic>> get _workspaceConversations {
    final filtered = _conversations.where((c) {
      final doorId = c['projectDoorId'] as String?;
      final belongs = (doorId == null || doorId.isEmpty)
          ? _selectedDoorId == null
          : doorId == _selectedDoorId;
      return belongs;
    }).toList();
    // 樹排序優先於 companionId 分組（Blue 拍板殘項i：母帶子一起走，
    // 子隊 companionId=null 不拆散）——先依全量推深度，工作區內再 DFS。
    return ConversationTreeMap.orderWithDepths(filtered).$1;
  }

  /// 對話深度（全量 parent 鏈推導，防環上限 8）。
  int _depthOf(Map<String, dynamic> conv) =>
      ConversationTreeMap.depthOf(conv, _conversations);

  /// 依 companionId 分組（清單已樹排序＝母在前、子緊跟）。
  /// [2026-11-21 章魚光呼吸樹] 殘項i：有母在列的子對話繼承母的組（母帶子
  /// 一起走，子隊 companionId=null 不拆散到「未指派」頭）。null 歸「未指派」。
  List<(String?, List<Map<String, dynamic>>)> get _companionGroups {
    final idToConv = <String, Map<String, dynamic>>{
      for (final c in _conversations)
        if (c['id'] is String) c['id'] as String: c,
    };
    String? effectiveCid(Map<String, dynamic> c) {
      // 防環：parent 鏈上限 8（同 depthOf 契約），循環即停回 null
      var cur = c;
      for (var i = 0; i < 8; i++) {
        final own = cur['companionId'] as String?;
        if (own != null && own.isNotEmpty) return own;
        final pid = cur['parentConversationId'];
        final parent = (pid is String) ? idToConv[pid] : null;
        if (parent == null || identical(parent, cur)) return null;
        cur = parent;
      }
      return null;
    }

    final groups = <String?, List<Map<String, dynamic>>>{};
    for (final c in _workspaceConversations) {
      groups.putIfAbsent(effectiveCid(c), () => []).add(c);
    }
    return groups.entries.map((e) => (e.key, e.value)).toList();
  }

  /// 工作區顯示名：大廳固定；暫無門名 store——升級點（註解見 _doorIds）。
  String _workspaceLabel(BuildContext context) =>
      _selectedDoorId == null ? '大廳' : '工作區 ${_shortDoorId(_selectedDoorId!)}';

  static String _shortDoorId(String id) =>
      id.length <= 8 ? id : id.substring(0, 8);

  /// L2 夥伴分組頭 label。⚠️ 升級點：companionId→夥伴名稱需夥伴清單
  /// （gateway 目前無 companionList request，payload 僅帶 id），
  /// 暫以 id 前 6 碼顯示；null 歸「未指派」。
  String _companionGroupLabel(String? companionId) {
    if (companionId == null || companionId.isEmpty) return '未指派';
    return companionId.length <= 6
        ? companionId
        : companionId.substring(0, 6);
  }

  @override
  Widget build(BuildContext context) {
    final colors = BridgeDSColors.of(context);
    return Scaffold(
      backgroundColor: colors.canvas,
      body: SafeArea(
        bottom: false,
        child: Row(
          children: [
            // ── 第 1 層（L1）：工作區列（[2026-11-21 Blue B案拍板] 大廳固定
            //    第一＋各 ProjectDoor；取代 §8.2 三類型桶圓標）
            _Rail(
              doorIds: _doorIds,
              selectedDoorId: _selectedDoorId,
              onSelect: (doorId) {
                setState(() {
                  _selectedDoorId = doorId;
                  _openConv = null; // 換工作區＝回中欄
                });
              },
            ),
            // ── 第 2/3 層：中欄列表 ↔ 對話視圖
            Expanded(
                child: _openConv != null ? _buildThread(context) : _buildList(context)),
          ],
        ),
      ),
    );
  }

  Widget _buildList(BuildContext context) {
    final colors = BridgeDSColors.of(context);
    // [2026-11-21 Blue B案拍板] 取代 §8.2 三類型桶——中欄標題＝選中工作區名，
    // 內容＝該工作區對話依 companionId 分組（夥伴分組頭＝「頻道」分節）。
    final convs = _workspaceConversations;
    final groups = _companionGroups;
    final label = _workspaceLabel(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: Row(
            children: [
              Text(
                label,
                style: TierStyle.of(context, Tier.cardTitle)
                    .toTextStyle()
                    .copyWith(color: colors.textPrimary),
              ),
              const Spacer(),
              Text(
                _loading ? '載入中' : '${convs.length} 個',
                style: TierStyle.of(context, Tier.cardCaption)
                    .toTextStyle()
                    .copyWith(color: colors.textTertiary),
              ),
            ],
          ),
        ),
        Expanded(
          child: _loading
              ? Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: colors.textTertiary),
                  ),
                )
              : convs.isEmpty
                  ? RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(children: [
                        const SizedBox(height: 120),
                        Center(
                          child: Text(
                            MobileBridgeClient.instance.isConnected
                                ? '$label尚無對話'
                                : '離線中——連線後載入',
                            style: TierStyle.of(context, Tier.cardBody)
                                .toTextStyle()
                                .copyWith(color: colors.textSecondary),
                          ),
                        ),
                      ]),
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(
                        padding: const EdgeInsets.only(bottom: 16),
                        children: [
                          // [2026-11-21 B案] L2 頻道清單：companionId 分組頭＋卡片
                          for (final (cid, items) in groups) ...[
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                              child: Text(
                                _companionGroupLabel(cid),
                                style: TierStyle.of(context, Tier.cardCaptionBold)
                                    .toTextStyle()
                                    .copyWith(color: colors.textTertiary),
                              ),
                            ),
                            for (final item in items)
                              _ConversationCard(
                                item: item,
                                onTap: _openConversation,
                                // [2026-11-21 章魚光呼吸樹] 深度→縮排＋↳＋呼吸脊線
                                depth: _depthOf(item),
                              ),
                          ],
                          // [Blue 11-14 報案] 回收桶入口（列表尾部）——保留不動
                          Padding(
                            padding: const EdgeInsets.fromLTRB(12, 14, 12, 0),
                            child: GestureDetector(
                              onTap: () =>
                                  setState(() => _showTrash = !_showTrash),
                              child: Row(
                                children: [
                                  Icon(Icons.delete_outline,
                                      size: 16, color: colors.textTertiary),
                                  const SizedBox(width: 6),
                                  Text(
                                    '回收桶（${_trash.length}）',
                                    style: TierStyle.of(context, Tier.cardCaption)
                                        .toTextStyle()
                                        .copyWith(color: colors.textTertiary),
                                  ),
                                  const Spacer(),
                                  Icon(
                                      _showTrash
                                          ? Icons.expand_less
                                          : Icons.expand_more,
                                      size: 16,
                                      color: colors.textTertiary),
                                ],
                              ),
                            ),
                          ),
                          if (_showTrash)
                            for (final t in _trash)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
                                child: Row(
                                  children: [
                                    Icon(Icons.history,
                                        size: 14, color: colors.textTertiary),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        '${t['title'] ?? '未命名'}（${t['messageCount'] ?? 0} 則）',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TierStyle.of(context,
                                                Tier.cardCaption)
                                            .toTextStyle()
                                            .copyWith(
                                                color: colors.textSecondary),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                        ],
                      ),
                    ),
        ),
      ],
    );
  }


  // ── 第 3 層：對話視圖（氣泡流＋輸入框——復用舊 _ChatPage 氣泡樣式）
  Widget _buildThread(BuildContext context) {
    final colors = BridgeDSColors.of(context);
    final conv = _openConv!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 返回列
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 10, 16, 6),
          child: Row(
            children: [
              IconButton(
                icon: Icon(Icons.arrow_back_ios_new,
                    size: 18, color: colors.textSecondary),
                onPressed: () => setState(() => _openConv = null),
              ),
              Expanded(
                child: Text(
                  conv['title'] ?? '對話',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TierStyle.of(context, Tier.cardTitle)
                      .toTextStyle()
                      .copyWith(color: colors.textPrimary),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _loadingHistory
              ? Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: colors.textTertiary),
                  ),
                )
              : _messages.isEmpty
                  ? Center(
                      child: Text(
                        '尚無訊息',
                        style: TierStyle.of(context, Tier.cardBody)
                            .toTextStyle()
                            .copyWith(color: colors.textSecondary),
                      ),
                    )
                  : ListView.builder(
                      reverse: true,
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                      itemCount: _messages.length,
                      itemBuilder: (context, i) {
                        final m = _messages[_messages.length - 1 - i];
                        final isAssistant = m['role'] == 'assistant';
                        return Align(
                          alignment: isAssistant
                              ? Alignment.centerLeft
                              : Alignment.centerRight,
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 10),
                            constraints:
                                const BoxConstraints(maxWidth: 280),
                            decoration: BoxDecoration(
                              color: isAssistant
                                  ? colors.surface
                                  : colors.surfaceElevated,
                              borderRadius: BorderRadius.only(
                                topLeft: const Radius.circular(14),
                                topRight: const Radius.circular(14),
                                bottomLeft: Radius.circular(
                                    isAssistant ? 4 : 14),
                                bottomRight: Radius.circular(
                                    isAssistant ? 14 : 4),
                              ),
                            ),
                            child: Text(
                              m['content'] ?? '',
                              style: TierStyle.of(context, Tier.cardBody)
                                  .toTextStyle()
                                  .copyWith(color: colors.textPrimary),
                            ),
                          ),
                        );
                      },
                    ),
        ),
        // [發送鏈 2026-11-14] 輸入框接線——sendConversationAppend（樂觀更新＋寧紅字）
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _input,
                  enabled: !_sending,
                  onSubmitted: (_) => _sendMessage(),
                  decoration: InputDecoration(
                    hintText: _sending ? '送出中…' : '輸入訊息…',
                    filled: true,
                    fillColor: colors.surface,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: BorderSide(color: colors.borderSubtle),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: _sending ? null : _sendMessage,
                child: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: colors.accentPurple,
                    shape: BoxShape.circle,
                  ),
                  child: _sending
                      ? SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: colors.canvas),
                        )
                      : Icon(Icons.arrow_upward,
                          size: 18, color: colors.canvas),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// [發送鏈] 送出：樂觀 append → gateway 確認；失敗紅字復原（寧紅字不假成功）
  Future<void> _sendMessage() async {
    final text = _input.text.trim();
    if (text.isEmpty || _openConv == null || _sending) return;
    final conv = _openConv!;
    final convId = conv['id'] as String? ?? '';
    // 樂觀更新：先上牆
    setState(() {
      _sending = true;
      _messages.add({'role': 'user', 'content': text, '_pending': true});
    });
    _input.clear();
    final res = await MobileBridgeClient.instance
        .sendConversationAppend(
          conversationId: convId, role: 'user', content: text);
    if (!mounted) return;
    if (res != null && res['ok'] == true) {
      setState(() {
        _sending = false;
        // 標記已確認
        if (_messages.isNotEmpty) _messages.last.remove('_pending');
      });
    } else {
      // 失敗：復原（紅字提示）
      setState(() {
        _sending = false;
        _messages.removeWhere((m) => m['_pending'] == true);
      });
      _input.text = text;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('送出失敗（桌面未回應）——訊息已復原')),
        );
      }
    }
  }
}

/// [2026-11-21 Blue B案拍板] L1 工作區列（取代 §8.2 三類型桶圓標）：
/// 「大廳」固定第一＋各 ProjectDoor（清單由 conversations.projectDoorId
/// 去重 derives，見 _doorIds——零新協定）。
/// ⚠️ 殘項：門正式名稱需 ProjectDoorStore（桌面端檔案 store，手機拿不到），
///   暫以 id 前 8 碼顯示。升級點＝gateway 增 projectDoorList request 帶名稱。
class _Rail extends StatelessWidget {
  final List<String> doorIds;
  final String? selectedDoorId;
  final ValueChanged<String?> onSelect;

  const _Rail(
      {required this.doorIds,
      required this.selectedDoorId,
      required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final colors = BridgeDSColors.of(context);

    // 單一工作區圓標：選中＝白底反色（沿用 mockup 視覺）；未選＝surface 圓
    Widget doorDot(String? id, IconData icon, String tooltip) {
      final selected = selectedDoorId == id;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: GestureDetector(
          onTap: () => onSelect(id),
          child: Tooltip(
            message: tooltip,
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                // mockup：選中＝白底（淺色實心）＋深色 icon；未選＝surface 圓
                color: selected ? colors.textPrimary : colors.surface,
                border: Border.all(
                    color:
                        selected ? colors.textPrimary : colors.borderSubtle),
              ),
              child: Icon(
                icon,
                size: 18,
                color: selected ? colors.canvas : colors.textSecondary,
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      width: 60,
      color: colors.surface,
      child: Column(
        children: [
          const SizedBox(height: 14),
          // 大廳固定第一（projectDoorId=null 未歸屬收口）
          doorDot(null, Icons.home_outlined, '大廳'),
          // 各工作區（ProjectDoor）：可滾動，門多不撐爆
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              shrinkWrap: true,
              children: [
                for (final id in doorIds)
                  doorDot(id, Icons.folder_outlined,
                      '工作區 ${_MobileChatThreeTierPageState._shortDoorId(id)}'),
              ],
            ),
          ),
          const Spacer(),
          // 分隔線＋頭像（mockup 第 5 圓標）——保留不動
          Container(
              width: 26, height: 1, color: colors.borderSubtle),
          const SizedBox(height: 8),
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: colors.surfaceElevated,
              border: Border.all(color: colors.borderSubtle),
            ),
            child: Icon(Icons.person_outline,
                size: 16, color: colors.textTertiary),
          ),
          const SizedBox(height: 14),
        ],
      ),
    );
  }
}

/// 中欄卡片（mockup：標題＋時間/狀態副標＋⋯選單）。
/// [2026-11-21 章魚光呼吸樹] depth>0：縮排（每層14px、上限3）＋標題 ↳ 前綴
/// ＋左緣呼吸脊線 BridgeBreathLine（2px、accentBlue、2800ms 章魚光呼吸）。
class _ConversationCard extends StatelessWidget {
  final Map<String, dynamic> item;
  final ValueChanged<Map<String, dynamic>>? onTap;
  final int depth;

  const _ConversationCard(
      {required this.item, this.onTap, this.depth = 0});

  bool get _isProactive => item['type'] == 'proactive';

  String get _subtitle {
    if (_isProactive) return '主動回應';
    final task = item['taskBinding'] as Map<String, dynamic>?;
    if (task != null) {
      final next = task['nextRun'] ?? task['schedule'] ?? '';
      final last = task['lastRunOk'] == null ? '' : (task['lastRunOk'] == true ? '✓ 成功' : '✗ 失敗');
      return [if (next.toString().isNotEmpty) '下次 $next', if (last.isNotEmpty) '前次 $last']
          .join('・');
    }
    final count = item['messageCount'] ?? 0;
    final preview = item['lastPreview'] ?? '';
    return count > 0 ? '$count 則・$preview' : '空對話';
  }

  // [SPEC §8.6] 檢查是否有 schedule（可顯示暫停⇄啟動）
  bool get _hasSchedule =>
      (item['taskBinding'] as Map<String, dynamic>?)?.containsKey('schedule') == true;

  // [SPEC §8.6] 目前狀態：有 schedule 且最後成功＝已啟動；反之＝已暫停
  bool get _isPaused {
    final task = item['taskBinding'] as Map<String, dynamic>?;
    if (task == null) return false;
    final lastOk = task['lastRunOk'] as bool?;
    // 無記錄或失敗＝視為已暫停
    return lastOk != true;
  }

  // 顯示底部選單
  Future<void> _showMenu(BuildContext context) async {
    final colors = BridgeDSColors.of(context);

    showModalBottomSheet(
      context: context,
      backgroundColor: colors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 刪除分隔線
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              decoration: BoxDecoration(
                color: colors.borderSubtle,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // [SPEC §8.6] 三選項：暫停⇄啟動 / 複製成新任務 / 刪除
            // 1. 暫停⇄啟動（動態：有 schedule 才顯示）
            // [2026-11-21 對話tab速勝 刀2] 查證無手機鏈、誠實 disabled：
            // 桌面暫停/續跑走 _toggleSchedulePause（bridge_desktop_screen
            // .dart L2461，程序內 setCanvasProps 改節點 params.paused）——
            // gateway 協議列舉（desktop_bridge_gateway_protocol.dart L7-69）
            // 無 taskPause/taskResume；taskRun 白名單 defaultForMobile
            // （mobile_task_whitelist.dart L83-92）亦無對應 taskType。
            // 寧紅字不假成功→disabled＋桌面版限定（勿硬接不存在的鏈）。
            if (_hasSchedule)
              ListTile(
                enabled: false,
                leading: Icon(
                  _isPaused ? Icons.play_arrow : Icons.pause,
                  color: colors.textTertiary,
                ),
                title: Text(
                  _isPaused ? '啟動' : '暫停',
                  style: TierStyle.of(context, Tier.listItemTitle).toTextStyle(),
                ),
                subtitle: Text(
                  '桌面版限定',
                  style: TierStyle.of(context, Tier.listItemTitle).toTextStyle(),
                ),
              ),
            // 2. 複製成新任務
            // [2026-11-21 對話tab速勝 刀2] 同上查證無鏈：協議無
            // conversationCreate/Duplicate、ConversationStore 無 fork API
            // → disabled＋桌面版限定。
            ListTile(
              enabled: false,
              leading: Icon(Icons.copy, color: colors.textTertiary),
              title: Text(
                '複製成新任務',
                style: TierStyle.of(context, Tier.listItemTitle).toTextStyle(),
              ),
              subtitle: Text(
                '桌面版限定',
                style: TierStyle.of(context, Tier.listItemTitle).toTextStyle(),
              ),
            ),
            // 3. 刪除（軟刪除進回收桶）
            ListTile(
              leading: Icon(Icons.delete_outline, color: colors.accentRed),
              title: Text(
                '刪除',
                style: TierStyle.of(context, Tier.listItemTitle).toTextStyle(),
              ),
              onTap: () async {
                Navigator.pop(context);
                // 確認對話
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    backgroundColor: colors.surface,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    title: Text(
                      '刪除對話',
                      style: TierStyle.of(context, Tier.cardTitle).toTextStyle(),
                    ),
                    content: Text(
                      '對話將移至回收桶，可隨時還原。',
                      style: TierStyle.of(context, Tier.cardBody).toTextStyle(),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: Text(
                          '取消',
                          style: TierStyle.of(context, Tier.cardBody).toTextStyle(),
                        ),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(context, true),
                        style: TextButton.styleFrom(
                          foregroundColor: colors.accentRed,
                        ),
                        child: Text(
                          '刪除',
                          style: TierStyle.of(context, Tier.cardBody).toTextStyle(),
                        ),
                      ),
                    ],
                  ),
                );

                if (confirmed == true) {
                  final success = await MobileBridgeClient.instance
                      .sendConversationDelete(item['id'] as String);
                  if (success && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('已移至回收桶'),
                        backgroundColor: colors.accentGreen,
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                    // 刷新列表
                    if (context.mounted) {
                      final state = context.findAncestorStateOfType<_MobileChatThreeTierPageState>();
                      state?._load();
                    }
                  } else if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('刪除失敗，請重試'),
                        backgroundColor: colors.accentRed,
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                }
              },
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = BridgeDSColors.of(context);
    // [2026-11-21 章魚光呼吸樹] 縮排（每層14px、上限3）＋↳ 前綴＋呼吸脊線
    final indent = (depth.clamp(0, 3) * 14).toDouble();
    final rawTitle = item['title'] ?? '未命名';
    final title = depth > 0 ? '↳ $rawTitle' : '$rawTitle';
    Widget card = Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.borderSubtle),
      ),
      child: Row(
        children: [
          // [mockup 圖 B] 狀態燈：綠=前次成功；紅=前次失敗；灰=無紀錄
          Builder(builder: (context) {
            final colors = BridgeDSColors.of(context);
            final task = item['taskBinding'] as Map<String, dynamic>?;
            final lastOk = task?['lastRunOk'];
            final dotColor = lastOk == null
                ? colors.textTertiary
                : (lastOk == true ? colors.accentGreen : colors.accentRed);
            return Padding(
              padding: const EdgeInsets.only(right: 10),
              child: Container(
                width: 7,
                height: 7,
                decoration:
                    BoxDecoration(shape: BoxShape.circle, color: dotColor),
              ),
            );
          }),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TierStyle.of(context, Tier.listItemTitle)
                      .toTextStyle()
                      .copyWith(color: colors.textPrimary),
                ),
                const SizedBox(height: 3),
                Text(
                  _subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TierStyle.of(context, Tier.cardCaption)
                      .toTextStyle()
                      .copyWith(color: colors.textSecondary),
                ),
              ],
            ),
          ),
          // [SPEC §8.6] 三點下拉選單
          IconButton(
            icon: Icon(Icons.more_vert, size: 18, color: colors.textTertiary),
            onPressed: () => _showMenu(context),
          ),
        ],
      ),
    );
    if (depth > 0) {
      // 章魚光呼吸：子卡左緣脊線（2px accentBlue，元件內建 reduced-motion 常亮降級）
      card = IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const BridgeBreathLine(width: 2),
            const SizedBox(width: 6),
            Expanded(child: card),
          ],
        ),
      );
    }
    return GestureDetector(
      onTap: () => onTap?.call(item),
      child: Padding(
        padding: EdgeInsets.only(left: indent),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
          child: card,
        ),
      ),
    );
  }
}
