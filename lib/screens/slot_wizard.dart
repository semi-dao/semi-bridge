// 插槽引導精靈（練夥伴模式）——固定步驟、無 LLM 主持
//
// [Blue 決策 2026-10-06] onboarding 棄對話式（LLM 不穩定：不回覆/不照
// 劇本/先登記後理解導致未分類堆垃圾）。改「練夥伴」式固定流程：
//
//   步驟1 貼連結 → 步驟2 認識專案（GitHub API 真實資料）
//   → 步驟3 你想拿它做什麼（grill-me 的精華濃縮成自選題）
//   → 步驟4 權限燈號（🟢🟡🔴）→ 完成（此刻才建立 SlotRecord）
//
// 任何一步放棄（關窗/上一步回頭/取消）＝不建立任何東西，無需卸載。
// 所有文字層級走 Tier、顏色走 BridgeDSColors（AlertDialog 鐵則）。

import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dio/dio.dart'; // [A線 1022] plugin 輕量偵測
import '../../services/slots/github_repo_info.dart';
import '../../services/slots/slot_registry.dart';
import '../../services/slots/slot_installer.dart';
import '../../services/slots/slot_redteam_scanner.dart';
import '../../theme/bridge_design_system.dart';
import '../../theme/tier.dart';
import '../../theme/tier_style.dart';

/// 引導結果：completed＝建立成功（帶 record）；dismissed＝使用者放棄。
class SlotWizardResult {
  final SlotRecord? record;
  final bool completed;
  const SlotWizardResult.completed(SlotRecord r)
      : record = r,
        completed = true;
  const SlotWizardResult.dismissed()
      : record = null,
        completed = false;
}

/// 開啟引導精靈（全屏對話框）。回傳結果供呼叫端 toast。
Future<SlotWizardResult> showSlotWizard(
    BuildContext context, String initialUrl) {
  return showDialog<SlotWizardResult>(
    context: context,
    barrierDismissible: false, // 只能走按鈕離開（放棄也要明確按）
    builder: (_) => _SlotWizardDialog(initialUrl: initialUrl),
  ).then((r) => r ?? const SlotWizardResult.dismissed());
}

class _SlotWizardDialog extends StatefulWidget {
  final String initialUrl;
  const _SlotWizardDialog({required this.initialUrl});
  @override
  State<_SlotWizardDialog> createState() => _SlotWizardDialogState();
}

class _SlotWizardDialogState extends State<_SlotWizardDialog> {
  int _step = 0; // 0=貼連結 1=認識專案 2=用途 3=燈號
  final _urlCtrl = TextEditingController();
  GithubRepoInfo? _info;
  // [A線 1022] plugin 識別（預掃描帶回）——步驟2 顯示「這是 plugin」
  String? _pluginName;
  String? _pluginVersion;
  int _pluginSkillsCount = 0;
  String? _fetchError;
  bool _fetching = false;

  // 步驟3 的用途自選題（grill-me 精華：一次問一件事、給選項不給問卷）
  int? _purposeChoice;
  static const _purposes = [
    ('🛠️', '常駐工具', '天天會用的小工具（轉檔、看資料、查東西）'),
    ('📂', '專案素材', '某個專案要用它，用完可能就放著'),
    ('🧪', '先試試看', '還不確定，先裝起來玩玩再說'),
  ];

  int _lightChoice = 1; // 燈號預設 🟡（最保守可用水準）
  String? _customLabel;

  // [C3] 安裝段狀態
  bool _installing = false;
  String? _installError;

  // [Blue 抓包 2026-10-06] 真實燈號建議——掃描前置：進入步驟4前先靜默
  // 下載+掃描，建議來自紅隊實析，不是固定文案。
  bool _preScanning = false;
  SlotRedTeamReport? _preScan;

  @override
  void initState() {
    super.initState();
    _urlCtrl.text = widget.initialUrl;
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    super.dispose();
  }

  void _abandon() => Navigator.of(context).pop(const SlotWizardResult.dismissed());

  /// [A線 1022] 輕量 plugin 偵測——GitHub raw 抓 .cursor-plugin/plugin.json。
  /// 子路徑 URL（/tree/main/pstack）直接組 raw URL；根 URL 先試根目錄再試
  /// 常見 marketplaces？不猜——根 URL 沒有就是沒有（深度搜尋在安裝時做）。
  Future<void> _detectPlugin() async {
    final url = _urlCtrl.text.trim();
    try {
      final m = RegExp(
        r'github\.com/([A-Za-z0-9_.-]+)/([A-Za-z0-9_.-]+)(?:/(?:tree|blob)/[^/]+/(.+))?'
      ).firstMatch(url);
      if (m == null) return;
      final owner = m.group(1)!, repo = m.group(2)!, sub = m.group(3);
      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 15),
        responseType: ResponseType.json,
      ));
      // 候選路徑：指名子目錄優先，否則根目錄
      final candidates = <String>[
        if (sub != null && sub.isNotEmpty) '$sub/.cursor-plugin/plugin.json',
        '.cursor-plugin/plugin.json',
      ];
      for (final c in candidates) {
        try {
          final res = await dio.get(
              'https://raw.githubusercontent.com/$owner/$repo/main/$c');
          // raw.githubusercontent 回 text/plain——dio 不自動 parse，手動 jsonDecode
          final data = res.data is String
              ? jsonDecode(res.data as String) as Map<String, dynamic>
              : res.data as Map<String, dynamic>;
          final name = (data['displayName'] ?? data['name']) as String? ;
          if (name == null || name.isEmpty) continue;
          final ver = data['version'] as String?;
          if (mounted) {
            setState(() {
              _pluginName = name;
              _pluginVersion = ver;
            });
          }
          return;
        } catch (e) {
          debugPrint('[SlotWizard] 候選 $c 沒抓到: $e'); // [A線 1022] 偵錯暫留
          continue; // 這條路徑沒有——試下一條
        }
      }
    } catch (e) {
      debugPrint('[SlotWizard] _detectPlugin 失敗: $e'); // [A線 1022] 偵錯暫留
    }
  }

  Future<void> _fetchInfo() async {
    setState(() { _fetching = true; _fetchError = null; });
    try {
      final info = await GithubRepoInfo.fetch(_urlCtrl.text.trim());
      setState(() { _info = info; _step = 1; });
      // [A線 1022] 步驟2 進入即背景預偵測 plugin（輕量：只抓 plugin.json 判斷，
      // 不下載整包 tarball——深度掃描留給步驟4 預掃描）
      _detectPlugin();
    } catch (e) {
      setState(() {
        _fetchError = '抓不到這個專案的資料（$e）。\n'
            '確認連結是公開 GitHub repo，或按「先跳過」用手動模式。';
      });
    } finally {
      setState(() => _fetching = false);
    }
  }

  Future<void> _finish() async {
    final info = _info!;
    // [A線 1022 通用機制] plugin repo：精靈不預建卡——installer plugin 分支
    // 會建 skill://<pluginName> 卡（帶正確 version/origin/category）。
    // 精靈若也建（htmlUrl 對位）= 重複雙卡（pstack 案實證）。
    if (_pluginName == null) {
      final record = await SlotRegistry.instance.addFromRepo(
        info.htmlUrl,
        label: _customLabel?.isNotEmpty == true ? _customLabel : null,
      );
      return _finishInstallFor(record);
    }
    // plugin 路徑：先 install（分支內建卡）→ 找回卡回傳
    setState(() => _installing = true);
    final slotDir = Directory(
        '${SlotRegistry.instance.slotsDir.path}/${_pluginName}');
    final install = await SlotInstaller.instance.install(
      repoUrl: _urlCtrl.text.trim().isNotEmpty
          ? _urlCtrl.text.trim()
          : info.htmlUrl,
      slotDir: slotDir,
    );
    if (!install.ok) {
      if (mounted) {
        setState(() {
          _installing = false;
          _installError = install.error ?? '未知錯誤';
        });
      }
      return;
    }
    // 找回 installer 建的卡（skill://<name> 對位）
    await SlotRegistry.instance.ensureLoaded();
    final repoKey = 'skill://$_pluginName';
    final existing = SlotRegistry.instance.all
        .firstWhere((s) => s.sourceRepo == repoKey);
    if (!mounted) return;
    Navigator.of(context).pop(SlotWizardResult.completed(existing));
  }

  /// 非 plugin（HTML 工具）路徑：精靈自建卡＋安裝（原 _finish 邏輯）
  Future<void> _finishInstallFor(SlotRecord record) async {
    final info = _info!;
    const permsByChoice = <List<String>>[
      [],                  // 🟢 純本地
      ['network'],         // 🟡 網路唯讀
      ['network', 'file'], // 🔴 完整
    ];

    // [C3] 點頭即安裝：真下載、真解壓、真掃描——不等安裝完成不回報。
    setState(() => _installing = true);
    final slotDir = Directory(
        '${SlotRegistry.instance.slotsDir.path}/${record.id}');
    final install = await SlotInstaller.instance.install(
      // [A線 1022 通用機制] 帶使用者貼的原始 URL（含 /tree/main/<sub> 子路徑）——
      // htmlUrl 會剝成 owner/repo，monorepo 指名安裝（pstack）就失效，
      // 深度搜尋會抓到第一個碰到的 plugin（advisor 案實證）。
      repoUrl: _urlCtrl.text.trim().isNotEmpty
          ? _urlCtrl.text.trim()
          : info.htmlUrl,
      slotDir: slotDir,
    );
    if (!install.ok) {
      // 誠實鐵則：裝不動＝紅字回報原因，插槽標 failed 不假成功
      if (mounted) {
        setState(() {
          _installing = false;
          _installError = install.error ?? '未知錯誤';
        });
      }
      return;
    }
    await SlotRegistry.instance.update(record.copyWith(
      entryHtmlPath: install.entryHtmlPath,
      version: install.version,
    ));
    await SlotRegistry.instance.enableWithPermissions(
        record.id, permsByChoice[_lightChoice]);
    if (!mounted) return;
    Navigator.of(context).pop(SlotWizardResult.completed(record));
  }

  @override
  Widget build(BuildContext context) {
    final ds = BridgeDSColors.of(context);
    return AlertDialog(
      backgroundColor: ds.surfaceElevated,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(BridgeDS.roundWide)),
      title: Row(
        children: [
          Icon(Icons.extension_outlined, size: 20, color: ds.accentBlue),
          const SizedBox(width: 8),
          Text(
            '讓開源程式住進來',
            style: TierStyle.of(context, Tier.dialogTitle)
                .toTextStyle()
                .copyWith(color: ds.textPrimary),
          ),
          const Spacer(),
          // 任何時候放棄＝什麼都不建立（Blue 決策：不用事後卸載）
          InkWell(
            onTap: _abandon,
            child: Text(
              '放棄',
              style: TierStyle.of(context, Tier.buttonSecondary)
                  .toTextStyle()
                  .copyWith(color: ds.textTertiary),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _stepIndicator(ds),
            const SizedBox(height: BridgeDS.spaceLG),
            if (_step == 0) _stepUrl(ds),
            if (_step == 1) _stepInfo(ds),
            if (_step == 2) _stepPurpose(ds),
            if (_step == 3) _stepLight(ds),
          ],
        ),
      ),
      actions: _actions(ds),
    );
  }

  Widget _stepIndicator(BridgeDSColors ds) {
    const labels = ['貼連結', '認識它', '用途', '燈號'];
    return Row(
      children: [
        for (var i = 0; i < labels.length; i++) ...[
          if (i > 0)
            Expanded(
                child: Divider(
                    color: i <= _step ? ds.accentMiro : ds.borderSubtle)),
          Container(
            width: 24, height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: i < _step
                  ? ds.accentMiro
                  : (i == _step ? ds.accentMiro.withValues(alpha: 0.25) : ds.canvas),
              border: Border.all(color: i <= _step ? ds.accentMiro : ds.borderSubtle),
            ),
            child: i < _step
                ? Icon(Icons.check, size: 14, color: ds.textPrimary)
                : Text('${i + 1}',
                    style: TierStyle.of(context, Tier.listItemMeta)
                        .toTextStyle()
                        .copyWith(
                            color: i <= _step ? ds.textPrimary : ds.textMuted)),
          ),
          const SizedBox(width: 6),
          Text(labels[i],
              style: TierStyle.of(context, Tier.listItemMeta).toTextStyle().copyWith(
                  color: i <= _step ? ds.textPrimary : ds.textMuted)),
          const SizedBox(width: 6),
        ],
      ],
    );
  }

  // ── 步驟 1：貼連結 ──────────────────────────────────
  Widget _stepUrl(BridgeDSColors ds) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('貼上你想用的開源程式 GitHub 連結',
            style: TierStyle.of(context, Tier.listItemTitle)
                .toTextStyle()
                .copyWith(color: ds.textPrimary)),
        const SizedBox(height: BridgeDS.spaceMD),
        TextField(
          controller: _urlCtrl,
          autofocus: true,
          style: TierStyle.of(context, Tier.bodyPrimary)
              .toTextStyle()
              .copyWith(color: ds.textPrimary),
          decoration: InputDecoration(
            // [Blue 驗收抓包 2026-10-06] ⌘V 在 dialog 內失效——貼上鈕保底
            // （讀剪貼簿不經鍵盤事件；手機版使用者同樣受益）
            suffixIcon: IconButton(
              icon: const Icon(Icons.content_paste),
              tooltip: '貼上',
              onPressed: () async {
                final data = await Clipboard.getData('text/plain');
                final text = data?.text?.trim() ?? '';
                if (text.isNotEmpty) {
                  _urlCtrl.text = text;
                  _urlCtrl.selection = TextSelection.collapsed(
                      offset: text.length);
                }
              },
            ),
            hintText: 'https://github.com/owner/repo',
            hintStyle: TierStyle.of(context, Tier.listItemMeta)
                .toTextStyle()
                .copyWith(color: ds.textMuted),
            filled: true,
            fillColor: ds.canvas,
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(BridgeDS.roundSubtle),
                borderSide: BorderSide.none),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(BridgeDS.roundSubtle),
                borderSide: BorderSide(color: ds.accentMiro)),
          ),
          onSubmitted: (_) => _tryNext(),
        ),
        if (_fetchError != null) ...[
          const SizedBox(height: BridgeDS.spaceMD),
          Text(_fetchError!,
              style: TierStyle.of(context, Tier.listItemMeta)
                  .toTextStyle()
                  .copyWith(color: ds.accentRed)),
        ],
      ],
    );
  }

  // ── 步驟 2：認識專案（GitHub API 真實資料，非 LLM 猜測）─────
  Widget _stepInfo(BridgeDSColors ds) {
    final info = _info!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // [A線 1022] plugin 識別卡——agent-plugins.org repo（如 pstack）：
        // 讓使用者在「認識它」這步就看見「這是 plugin、版本、帶多少 skills」
        if (_pluginName != null) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: ds.canvas,
              borderRadius: BorderRadius.circular(BridgeDS.roundSubtle),
              border: Border.all(color: ds.borderSubtle),
            ),
            child: Text(
              '🧩 偵測到 plugin：$_pluginName'
              '${_pluginVersion != null ? ' v$_pluginVersion' : ''}'
              '${_pluginSkillsCount > 0 ? '（$_pluginSkillsCount 個 skills）' : ''}',
              style: TierStyle.of(context, Tier.listItemMeta)
                  .toTextStyle()
                  .copyWith(color: ds.textSecondary),
            ),
          ),
          const SizedBox(height: BridgeDS.spaceSM),
        ],
        Text(info.fullName,
            style: TierStyle.of(context, Tier.listItemTitle)
                .toTextStyle()
                .copyWith(
                    color: ds.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w800)),
        const SizedBox(height: BridgeDS.spaceSM),
        Text(
          info.description ?? '（這個 repo 沒有寫描述——作者沒填，不是我們抓不到）',
          style: TierStyle.of(context, Tier.bodyPrimary)
              .toTextStyle()
              .copyWith(color: ds.textSecondary),
        ),
        const SizedBox(height: BridgeDS.spaceMD),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            if (info.language != null) _chip(ds, '💻 ${info.language}'),
            _chip(ds, '⭐ ${info.stars}'),
            if (info.license != null && info.license != 'NOASSERTION')
              _chip(ds, '📜 ${info.license}'),
            for (final t in info.topics) _chip(ds, '#$t'),
          ],
        ),
      ],
    );
  }

  Widget _chip(BridgeDSColors ds, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: ds.canvas,
        borderRadius: BorderRadius.circular(BridgeDS.roundSubtle),
        border: Border.all(color: ds.borderSubtle),
      ),
      child: Text(text,
          style: TierStyle.of(context, Tier.listItemMeta)
              .toTextStyle()
              .copyWith(color: ds.textSecondary)),
    );
  }

  // ── 步驟 3：用途（grill-me 精華：自選題，不開放問卷）─────────
  Widget _stepPurpose(BridgeDSColors ds) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('你想拿它做什麼？（影響我們怎麼幫你安排）',
            style: TierStyle.of(context, Tier.listItemTitle)
                .toTextStyle()
                .copyWith(color: ds.textPrimary)),
        const SizedBox(height: BridgeDS.spaceMD),
        for (var i = 0; i < _purposes.length; i++)
          _choiceTile(
            ds,
            selected: _purposeChoice == i,
            emoji: _purposes[i].$1,
            title: _purposes[i].$2,
            desc: _purposes[i].$3,
            onTap: () => setState(() => _purposeChoice = i),
          ),
        const SizedBox(height: BridgeDS.spaceMD),
        Text('給它一個你記得住的名字（可略）',
            style: TierStyle.of(context, Tier.listItemMeta)
                .toTextStyle()
                .copyWith(color: ds.textMuted)),
        const SizedBox(height: BridgeDS.spaceSM),
        TextField(
          controller: TextEditingController(text: _customLabel ?? ''),
          onChanged: (v) => _customLabel = v,
          style: TierStyle.of(context, Tier.bodyPrimary)
              .toTextStyle()
              .copyWith(color: ds.textPrimary),
          decoration: InputDecoration(
            hintText: _info?.fullName.split('/').last ?? 'my-tool',
            hintStyle: TierStyle.of(context, Tier.listItemMeta)
                .toTextStyle()
                .copyWith(color: ds.textMuted),
            filled: true,
            fillColor: ds.canvas,
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(BridgeDS.roundSubtle),
                borderSide: BorderSide.none),
          ),
        ),
      ],
    );
  }


  /// [Blue 抓包 2026-10-06] 真實建議卡：掃描結果 → 人話。
  Widget _buildScanAdvice(BridgeDSColors ds) {
    if (_preScan == null) {
      // 掃描失敗（網路斷/私有repo）——誠實說，不假裝分析過
      return Container(
        margin: const EdgeInsets.only(bottom: BridgeDS.spaceMD),
        padding: const EdgeInsets.all(BridgeDS.spaceMD),
        decoration: BoxDecoration(
          color: ds.accentYellow.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(BridgeDS.roundSubtle),
          border: Border.all(color: ds.accentYellow.withValues(alpha: 0.3)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline, size: 16, color: ds.accentYellow),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '預掃描沒成功（網路或 repo 存取限制）。預設從 🟡 保守開始——'
                '你可以自己判斷調整。',
                style: TierStyle.of(context, Tier.listItemMeta)
                    .toTextStyle()
                    .copyWith(color: ds.textSecondary, height: 1.5),
              ),
            ),
          ],
        ),
      );
    }
    final r = _preScan!;
    final hasBlock = r.blockers.isNotEmpty;
    final hasWarn = r.warnings.isNotEmpty;
    final c = hasBlock ? ds.accentRed : (hasWarn ? ds.accentYellow : ds.accentGreen);
    final icon = hasBlock ? Icons.gpp_bad : (hasWarn ? Icons.gpp_maybe : Icons.verified);
    final headline = hasBlock
        ? '掃描發現：這工具引用外部腳本，離線跑不動——需要 🔴 網路權限'
        : hasWarn
            ? '掃描發現：它會對外抓資料（${r.warnings.length} 處）——建議 🟡 網路唯讀'
            : '掃描乾淨：零外部引用、零對外請求（${r.scannedFiles} 檔全查）——建議 🟢 純本地';
    return Container(
      margin: const EdgeInsets.only(bottom: BridgeDS.spaceMD),
      padding: const EdgeInsets.all(BridgeDS.spaceMD),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(BridgeDS.roundSubtle),
        border: Border.all(color: c.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: c),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              headline,
              style: TierStyle.of(context, Tier.listItemMeta)
                  .toTextStyle()
                  .copyWith(color: ds.textSecondary, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }

  // ── 步驟 4：權限燈號（最後一步，點頭才建立）──────────────
  // [Blue 抓包 2026-10-06] 建議＝真實分析：進入本步前已靜默下載掃描，
  // BLOCK→🔴、WARN→🟡、乾淨→🟢；掃不動→🟡 保守＋誠實標註。
  Widget _stepLight(BridgeDSColors ds) {
    if (_preScanning) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('正在掃描這個工具…（下載 → 紅隊分析）',
              style: TierStyle.of(context, Tier.listItemTitle)
                  .toTextStyle()
                  .copyWith(color: ds.textPrimary)),
          const SizedBox(height: BridgeDS.spaceMD),
          Text('掃描完會依實際結果建議燈號，不是固定答案。',
              style: TierStyle.of(context, Tier.listItemMeta)
                  .toTextStyle()
                  .copyWith(color: ds.textTertiary)),
          const SizedBox(height: BridgeDS.spaceLG),
          const Center(child: CircularProgressIndicator()),
        ],
      );
    }
    if (_installing) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('正在安裝…（下載 → 解壓 → 紅隊掃描）',
              style: TierStyle.of(context, Tier.listItemTitle)
                  .toTextStyle()
                  .copyWith(color: ds.textPrimary)),
          const SizedBox(height: BridgeDS.spaceLG),
          const Center(
              child: CircularProgressIndicator()),
        ],
      );
    }
    if (_installError != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('裝不動——誠實回報：',
              style: TierStyle.of(context, Tier.listItemTitle)
                  .toTextStyle()
                  .copyWith(color: ds.accentRed)),
          const SizedBox(height: BridgeDS.spaceMD),
          Text(_installError!,
              style: TierStyle.of(context, Tier.bodyPrimary)
                  .toTextStyle()
                  .copyWith(color: ds.accentRed, height: 1.6)),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildScanAdvice(ds),
        Text('要給它什麼權限？這是它住進來的最後一步。',
            style: TierStyle.of(context, Tier.listItemTitle)
                .toTextStyle()
                .copyWith(color: ds.textPrimary)),
        const SizedBox(height: BridgeDS.spaceMD),
        _choiceTile(ds,
            selected: _lightChoice == 0,
            emoji: '🟢',
            title: '純本地——不碰網路、不寫檔案',
            desc: '最安全。只在自己的插槽資料夾內運算。',
            onTap: () => setState(() => _lightChoice = 0)),
        _choiceTile(ds,
            selected: _lightChoice == 1,
            emoji: '🟡',
            title: '網路唯讀——可抓資料、不下載執行檔',
            desc: '適合讀資料/查 API 的工具。',
            onTap: () => setState(() => _lightChoice = 1)),
        _choiceTile(ds,
            selected: _lightChoice == 2,
            emoji: '🔴',
            title: '網路＋檔案寫入——完整能力',
            desc: '高風險：可下載與改寫檔案。僅在信任來源時選。',
            onTap: () => setState(() => _lightChoice = 2)),
      ],
    );
  }

  Widget _choiceTile(
    BridgeDSColors ds, {
    required bool selected,
    required String emoji,
    required String title,
    required String desc,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(BridgeDS.roundSubtle),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: selected ? ds.accentMiro.withValues(alpha: 0.10) : ds.canvas,
          borderRadius: BorderRadius.circular(BridgeDS.roundSubtle),
          border: Border.all(
            color: selected
                ? ds.accentMiro.withValues(alpha: 0.6)
                : ds.borderSubtle,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 18)),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TierStyle.of(context, Tier.listItemTitle)
                          .toTextStyle()
                          .copyWith(
                              color: ds.textPrimary,
                              fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(desc,
                      style: TierStyle.of(context, Tier.listItemMeta)
                          .toTextStyle()
                          .copyWith(color: ds.textTertiary)),
                ],
              ),
            ),
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              size: 18,
              color: selected ? ds.accentMiro : ds.textMuted,
            ),
          ],
        ),
      ),
    );
  }

  // ── 按鈕列 ─────────────────────────────────────────
  List<Widget> _actions(BridgeDSColors ds) {
    final canNext = _step == 0
        ? _urlCtrl.text.contains('github.com')
        : _step == 2
            ? _purposeChoice != null
            : true;
    return [
      if (_step > 0)
        TextButton(
          onPressed: () => setState(() => _step--),
          child: Text('上一步',
              style: TierStyle.of(context, Tier.buttonSecondary)
                  .toTextStyle()
                  .copyWith(color: ds.textSecondary)),
        ),
      if (_step == 0)
        FilledButton(
          onPressed: _fetching ? null : _tryNext,
          style: FilledButton.styleFrom(backgroundColor: ds.accentMiro),
          child: _fetching
              ? SizedBox(
                  width: 16, height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation(ds.textPrimary)))
              : Text('認識它 →',
                  style: TierStyle.of(context, Tier.buttonPrimary)
                      .toTextStyle()
                      .copyWith(color: ds.textPrimary)),
        ),
      if (_step == 1)
        FilledButton(
          onPressed: () => setState(() => _step = 2),
          style: FilledButton.styleFrom(backgroundColor: ds.accentMiro),
          child: Text('我要用它 →',
              style: TierStyle.of(context, Tier.buttonPrimary)
                  .toTextStyle()
                  .copyWith(color: ds.textPrimary)),
        ),
      if (_step == 2 && canNext)
        FilledButton(
          onPressed: _enterLightStep,
          style: FilledButton.styleFrom(backgroundColor: ds.accentMiro),
          child: Text('選燈號 →',
              style: TierStyle.of(context, Tier.buttonPrimary)
                  .toTextStyle()
                  .copyWith(color: ds.textPrimary)),
        ),
      if (_step == 3)
        FilledButton(
          onPressed: _finish,
          style: FilledButton.styleFrom(backgroundColor: ds.accentMiro),
          child: Text('點頭，住進來 ✦',
              style: TierStyle.of(context, Tier.buttonPrimary)
                  .toTextStyle()
                  .copyWith(color: ds.textPrimary)),
        ),
    ];
  }

  // 進入燈號步驟前：靜默預掃描（臨時夾，不落地到插槽區——放棄零殘留）
  Future<void> _enterLightStep() async {
    setState(() {
      _step = 3;
      _preScanning = true;
      _preScan = null;
    });
    try {
      final tmpDir = await Directory.systemTemp.createTemp('slot_prescan_');
      // [A線 2026-10-22] plugin repo（.cursor-plugin/plugin.json）預掃描：
      // runPluginIntake=false——純偵測＋紅隊掃描，不建卡不入庫
      // （預掃臨時夾的紀錄要是真卡，使用者放棄就留幽靈卡）。
      final result = await SlotInstaller.instance.install(
        repoUrl: _urlCtrl.text.trim(),
        slotDir: tmpDir,
        runPluginIntake: false,
      );
      // 掃完即刪——臨時夾不留痕（放棄零殘留鐵則）
      await tmpDir.delete(recursive: true);
      if (!mounted) return;
      if (result.ok && result.redTeam != null) {
        setState(() {
          _preScan = result.redTeam;
          _preScanning = false;
          // [A線 1022] plugin 識別（agent-plugins.org repo）
          _pluginName = result.pluginName;
          _pluginVersion = result.version;
          _pluginSkillsCount = result.pluginSkillsCount;
          // 真實建議：BLOCK→🔴 需網路/WARN→🟡/乾淨→🟢
          _lightChoice = result.redTeam!.blockers.isNotEmpty
              ? 2
              : result.redTeam!.warnings.isNotEmpty
                  ? 1
                  : 0;
        });
      } else {
        // 掃描失敗（私有repo/網路斷）——不擋流程，黃燈保守起步＋誠實標註
        if (mounted) {
          setState(() {
            _preScanning = false;
            _lightChoice = 1;
          });
        }
      }
    } catch (e) {
      if (mounted) setState(() => _preScanning = false);
    }
  }

  void _tryNext() {
    final t = _urlCtrl.text.trim();
    if (GithubRepoInfo.parseUrl(t) == null) {
      setState(() => _fetchError = '這不是 GitHub 連結——請貼 github.com/owner/repo 格式');
      return;
    }
    _fetchInfo();
  }
}
