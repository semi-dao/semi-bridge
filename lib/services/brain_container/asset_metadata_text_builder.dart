// asset_metadata_text_builder.dart
// [教練 Agent 2026-08-20] 鐵三角 #2——中繼文字產生器（純規則、零 GPU）
//
// 86% 假向量的根因：22484 筆資產只嵌了檔名（IMG_2384.jpg），
// 搜「鹿角蕨照顧」永遠 miss 那張鹿角蕨照片。
//
// 解法：為「無可讀內容」的資產產生中繼文字（metadata surrogate）——
// 把 ingest 階段純規則回填的 display_title（P1-4 人話標題）、
// topic_cluster（系列名）、路徑段落、檔名、日期組合成一段描述，
// 再嵌這段文字。不燒 Vision GPU、不呼叫 LLM，冪等可重跑。
//
// 設計原則（使用者 憲章）：通用設計不 hardcode——所有欄位都是
// DB 既有欄位，零領域詞彙。

/// 為一筆資產產生中繼嵌入文字。
///
/// [row] 需含鍵：display_title, topic_cluster, file_path, folder_root,
/// file_name, file_modified（毫秒）, asset_kind, tags（JSON 字串）。
/// 任一欄位缺失都可——有什麼用什麼，絕不丟例外（backfill 要能續跑）。
String buildMetadataEmbedText(Map<String, Object?> row) {
  final parts = <String>[];

  final title = row['display_title'] as String?;
  if (title != null && title.trim().isNotEmpty) {
    parts.add(title.trim());
  }

  final cluster = row['topic_cluster'] as String?;
  if (cluster != null && cluster.trim().isNotEmpty) {
    parts.add('系列：${cluster.trim()}');
  }

  // 路徑段落：去掉 folder_root 前綴與副檔名，每段都是語義線索
  // （例：/Volumes/DATA/橋樑計劃/02-鹿角蕨/照顧筆記/IMG_2384.jpg
  //   → 「橋樑計劃 02-鹿角蕨 照顧筆記」）
  final folderRoot = (row['folder_root'] as String?) ?? '';
  final filePath = (row['file_path'] as String?) ?? '';
  final fullPath = filePath.startsWith('/') ? filePath : '$folderRoot/$filePath';
  final segs = fullPath
      .split('/')
      .where((s) => s.isNotEmpty && !s.contains('.'))
      .skip(1) // 去掉 /Volumes 或 /Users 這種無語義段
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();
  if (segs.isNotEmpty) {
    // 最多取 4 段，避免長路徑淹沒標題
    parts.add('路徑：${segs.take(4).join(' ')}');
  }

  final fileName = row['file_name'] as String?;
  if (fileName != null && fileName.trim().isNotEmpty) {
    final stem = fileName.contains('.')
        ? fileName.substring(0, fileName.lastIndexOf('.'))
        : fileName;
    if (stem.trim().isNotEmpty) parts.add(stem.trim());
  }

  // 日期：檔案修改時間的年月（「2025 年 3 月」這種粒度對語義檢索有用）
  final modified = row['file_modified'] as int?;
  if (modified != null && modified > 0) {
    final dt = DateTime.fromMillisecondsSinceEpoch(modified);
    parts.add('${dt.year}年${dt.month}月');
  }

  return parts.join('。');
}

/// 判斷一筆資產的 content_text 是否只是檔名（舊假向量的印記）。
///
/// 舊管線對「其他」類檔案直接 embed 檔名字串，content_text 欄
/// 存的也是檔名——content_text == file_name 即為假向量印記。
bool isFilenameOnlyContent(Map<String, Object?> row) {
  final content = row['content_text'] as String?;
  final fileName = row['file_name'] as String?;
  if (content == null || fileName == null) return content == null;
  return content.trim() == fileName.trim();
}
