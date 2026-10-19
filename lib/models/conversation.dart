import 'bridge_action.dart';

/// 對話類型。
enum ConversationType {
  /// 一般對話
  general,
  /// 專案畫布對話（綁定畫布，封閉不污染）
  projectCanvas,
  /// [Blue 令 2026-10-17] 主動回應頻道——羅盤/夢的主動發話住這裡，
  /// 不混入既有對話討論串。Session 獨立、可回覆、不觸發工具循環。
  proactive;

  String get label => switch (this) {
        general => 'general',
        projectCanvas => 'project_canvas',
        proactive => 'proactive',
      };

  static ConversationType fromString(String? s) => switch (s) {
        'project_canvas' => projectCanvas,
        'proactive' => proactive,
        _ => general,
      };
}

class Conversation {
  final String id;
  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<Message> messages;
  final String? companionId; // 所屬夥伴 ID，null 代表舊資料或無夥伴
  final String? projectDoorId; // 綁定的專案門 ID

  // D11: 專案畫布對話系統
  final String? canvasId; // 綁定的畫布 ID（null = 一般對話）
  final ConversationType type; // 對話類型
  final String? parentConversationId; // 匯入既有畫布時，指向原對話（串接用）
  final String? summary; // 自動摘要（跨 session 用）
  final int? lastSummaryIndex; // 上次摘要到的訊息 index

  Conversation({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    required this.messages,
    this.companionId,
    this.projectDoorId,
    this.canvasId,
    this.type = ConversationType.general,
    this.parentConversationId,
    this.summary,
    this.lastSummaryIndex,
  });

  factory Conversation.create({String? title, String? companionId}) {
    final now = DateTime.now();
    return Conversation(
      id: '${now.millisecondsSinceEpoch}',
      title: title ?? '未命名對話',
      createdAt: now,
      updatedAt: now,
      messages: [],
      companionId: companionId,
    );
  }

  /// D11: 建立專案畫布對話
  factory Conversation.createProjectCanvas({
    required String canvasId,
    required String title,
    String? companionId,
    String? parentConversationId,
  }) {
    final now = DateTime.now();
    return Conversation(
      id: '${now.millisecondsSinceEpoch}',
      title: title,
      createdAt: now,
      updatedAt: now,
      messages: [],
      companionId: companionId,
      canvasId: canvasId,
      type: ConversationType.projectCanvas,
      parentConversationId: parentConversationId,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'messages': messages.map((m) => m.toJson()).toList(),
    'companionId': companionId,
    if (projectDoorId != null) 'projectDoorId': projectDoorId,
    if (canvasId != null) 'canvasId': canvasId,
    'type': type.label,
    if (parentConversationId != null) 'parentConversationId': parentConversationId,
    if (summary != null) 'summary': summary,
    if (lastSummaryIndex != null) 'lastSummaryIndex': lastSummaryIndex,
  };

  factory Conversation.fromJson(Map<String, dynamic> json) => Conversation(
    id: json['id'] as String,
    title: json['title'] as String,
    createdAt: DateTime.parse(json['createdAt'] as String),
    updatedAt: DateTime.parse(json['updatedAt'] as String),
    messages: (json['messages'] as List)
        .map((m) => Message.fromJson(m as Map<String, dynamic>))
        .toList(),
    companionId: json['companionId'] as String?,
    projectDoorId: json['projectDoorId'] as String?,
    canvasId: json['canvasId'] as String?,
    type: ConversationType.fromString(json['type'] as String?),
    parentConversationId: json['parentConversationId'] as String?,
    summary: json['summary'] as String?,
    lastSummaryIndex: json['lastSummaryIndex'] as int?,
  );

  Conversation copyWith({
    String? title,
    DateTime? updatedAt,
    List<Message>? messages,
    String? companionId,
    String? projectDoorId,
    String? canvasId,
    ConversationType? type,
    String? parentConversationId,
    String? summary,
    int? lastSummaryIndex,
  }) => Conversation(
    id: id,
    title: title ?? this.title,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    messages: messages ?? this.messages,
    companionId: companionId ?? this.companionId,
    projectDoorId: projectDoorId ?? this.projectDoorId,
    canvasId: canvasId ?? this.canvasId,
    type: type ?? this.type,
    parentConversationId: parentConversationId ?? this.parentConversationId,
    summary: summary ?? this.summary,
    lastSummaryIndex: lastSummaryIndex ?? this.lastSummaryIndex,
  );

  /// 清除 projectDoorId（Dart nullable param 無法區分不傳 vs 傳 null）
  Conversation clearProjectDoorId() => Conversation(
    id: id,
    title: title,
    createdAt: createdAt,
    updatedAt: DateTime.now(),
    messages: messages,
    companionId: companionId,
    projectDoorId: null,
    canvasId: canvasId,
    type: type,
    parentConversationId: parentConversationId,
    summary: summary,
    lastSummaryIndex: lastSummaryIndex,
  );

  /// D11: 是否為專案畫布對話
  bool get isProjectCanvas => type == ConversationType.projectCanvas;
}

class Message {
  final String id;
  final String role;
  final String content;
  final DateTime timestamp;
  final int? tokens;
  final String? model;
  final String? imagePath;
  final String? attachmentKind;
  final String? attachmentPath;

  /// [教練 Agent 2026-08-21] Agent 自律死命令——所有生成的數位資產必須讓使用者看見。
  /// 批量生成時全部媒体附件都列出（不只第一張）。
  final List<String> mediaAssets;
  final List<BridgeAction>? bridgeActions; // 橋樑動作
  final Map<String, dynamic>? metadata;
  final String? speakerId; // companion.id，user 訊息填 null
  final List<String> quickReplies; // [教練 Agent 2026-06-29] AI 提問時附帶的快速選項
  final String? replyToId; // [教練 Agent 2026-07-22] Phase H 回覆指定訊息的 ID
  final String? replyToSnippet; // [教練 Agent 2026-07-22] Phase H 回覆目標的摘要文字（避免 UI 要反查）

  Message({
    required this.id,
    required this.role,
    required this.content,
    required this.timestamp,
    this.tokens,
    this.mediaAssets = const [],
    this.model,
    this.imagePath,
    this.attachmentKind,
    this.attachmentPath,
    this.bridgeActions,
    this.metadata,
    this.speakerId,
    this.quickReplies = const [],
    this.replyToId,
    this.replyToSnippet,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'role': role,
    'content': content,
    'timestamp': timestamp.toIso8601String(),
    'tokens': tokens,
    'model': model,
    'imagePath': imagePath,
    'attachmentKind': attachmentKind,
    'attachmentPath': attachmentPath,
    'bridgeActions': bridgeActions?.map((a) => a.toJson()).toList(),
    'metadata': metadata,
    if (speakerId != null) 'speakerId': speakerId,
    if (quickReplies.isNotEmpty) 'quickReplies': quickReplies,
    if (replyToId != null) 'replyToId': replyToId,
    if (replyToSnippet != null) 'replyToSnippet': replyToSnippet,
  };

  factory Message.fromJson(Map<String, dynamic> json) => Message(
    id: json['id'] as String,
    role: json['role'] as String,
    content: json['content'] as String,
    timestamp: DateTime.parse(json['timestamp'] as String),
    tokens: json['tokens'] as int?,
    model: json['model'] as String?,
    imagePath: json['imagePath'] as String?,
    attachmentKind: json['attachmentKind'] as String?,
    attachmentPath: json['attachmentPath'] as String?,
    bridgeActions: (json['bridgeActions'] as List<dynamic>?)
        ?.map((e) => BridgeAction.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList(),
    metadata: json['metadata'] == null
        ? null
        : Map<String, dynamic>.from(json['metadata'] as Map),
    speakerId: json['speakerId'] as String?,
    quickReplies: (json['quickReplies'] as List<dynamic>?)
        ?.map((e) => e.toString())
        .toList() ??
        const [],
    replyToId: json['replyToId'] as String?,
    replyToSnippet: json['replyToSnippet'] as String?,
  );

  Message copyWith({
    String? content,
    int? tokens,
    String? model,
    String? imagePath,
    String? attachmentKind,
    String? attachmentPath,
    List<BridgeAction>? bridgeActions,
    Map<String, dynamic>? metadata,
    String? speakerId,
    List<String>? quickReplies,
    String? replyToId,
    String? replyToSnippet,
    List<String>? mediaAssets,
  }) {
    return Message(
      id: id,
      role: role,
      content: content ?? this.content,
      timestamp: timestamp,
      tokens: tokens ?? this.tokens,
      model: model ?? this.model,
      imagePath: imagePath ?? this.imagePath,
      attachmentKind: attachmentKind ?? this.attachmentKind,
      attachmentPath: attachmentPath ?? this.attachmentPath,
      bridgeActions: bridgeActions ?? this.bridgeActions,
      metadata: metadata ?? this.metadata,
      speakerId: speakerId ?? this.speakerId,
      quickReplies: quickReplies ?? this.quickReplies,
      replyToId: replyToId ?? this.replyToId,
      replyToSnippet: replyToSnippet ?? this.replyToSnippet,
      mediaAssets: mediaAssets ?? this.mediaAssets,
    );
  }
}
