// brain_schema_sql.dart
// 大腦容器 SQLite schema — 所有 CREATE TABLE / INDEX / vector_init 集中於此
// 建立日期: 2026-07-02
//
// sqlite_vector v1.0.0 API 注意事項：
// - 向量存在 memories 表的 BLOB 欄位（不需要 vec0 虛擬表）
// - 寫入用 vector_as_f32(?) — 參數傳 JSON 字串 '[1.0, 2.0, ...]'
// - 建索引用 vector_init('memories', 'embedding', 'type=FLOAT32,dimension=768')
// - k-NN 搜尋用 vector_full_scan('memories', 'embedding', ?, k)
// - 載入用 Dart 端 sqlite3.loadSqliteVectorExtension()，不是 SQL load_extension

/// 大腦容器 schema 版本
// [小葵 2026-09-09 Blue 分層令] v13 → v14：asset_index.audience 分層欄
// ('general' 一般使用者 / 'technical' 工程師層——預設搜尋不可見，
//  工程模式/絕對搜尋才出現)。junk 檔（Icon\r/._*）由掃描器排除＋清理。
// [小葵 2026-09-22 Blue 偷學令] v17 → v18：記憶時效三欄。
// superseded_by：矛盾消解——新事實取代舊事實（舊記憶指向新記憶，留審計不刪）。
// expires_at 已存在但零使用：本版起寫入端可標記臨時事實到期日，
// 讀取端一律過濾（temporal filtering——supermemory 借鏡）。
const String kBrainSchemaVersion = '20';

/// 所有 CREATE TABLE 語句。
///
/// 執行順序：先建表 → migration → 建索引。
/// vector_init 與 seed data 由 [BrainDatabase.initialize] 分別處理，
/// 不再放在此列表中（改善 5：vector_init 重複執行防護）。
///
/// [S23b 修復] 原本建表和建索引在同一批，舊 DB（schema v3）在跑到
/// migration 之前就因為建索引引用新欄位（companion_id）而失敗。
/// 現在拆成 brainCreateTableStatements 和 brainCreateIndexStatements，
/// 中間插入 _runMigrations()。
const List<String> brainCreateTableStatements = [
  // ── 1. memories 表 ──────────────────────────────────────────────
  '''
  CREATE TABLE IF NOT EXISTS memories (
    id                  TEXT PRIMARY KEY,
    content             TEXT NOT NULL,
    room                TEXT NOT NULL,
    sub_category        TEXT NOT NULL,
    agent               TEXT NOT NULL,
    companion_id        TEXT NOT NULL DEFAULT '',
    source              TEXT NOT NULL,
    source_id           TEXT,
    speaker             TEXT,
    project             TEXT NOT NULL DEFAULT '',
    tags                TEXT NOT NULL DEFAULT '[]',
    importance          INTEGER NOT NULL DEFAULT 3 CHECK (importance BETWEEN 1 AND 5),
    created_at          INTEGER NOT NULL,
    updated_at          INTEGER NOT NULL,
    expires_at          INTEGER,
    access_count        INTEGER NOT NULL DEFAULT 0,
    archived            INTEGER NOT NULL DEFAULT 0,
    superseded_by       TEXT,
    chunk_index         INTEGER NOT NULL DEFAULT 0,
    total_chunks        INTEGER NOT NULL DEFAULT 1,
    parent_memory_id    TEXT,
    integration_result  TEXT,
    embedding           BLOB,
    vector_model_version TEXT,
    FOREIGN KEY (parent_memory_id) REFERENCES memories(id) ON DELETE SET NULL,
    CHECK (total_chunks >= 1),
    CHECK (chunk_index >= 0 AND chunk_index < total_chunks),
    CHECK (parent_memory_id IS NULL OR parent_memory_id != id)
  )
  ''',

  // ── 2. connections 表 ───────────────────────────────────────────
  '''
  CREATE TABLE IF NOT EXISTS connections (
    id                  TEXT PRIMARY KEY,
    from_memory_id      TEXT NOT NULL,
    to_memory_id        TEXT NOT NULL,
    type                TEXT NOT NULL,
    similarity          REAL NOT NULL CHECK (similarity BETWEEN 0.0 AND 1.0),
    strength            REAL NOT NULL CHECK (strength BETWEEN 0.1 AND 1.0),
    reinforcement_count INTEGER NOT NULL DEFAULT 0,
    created_at          INTEGER NOT NULL,
    last_reinforced_at  INTEGER NOT NULL,
    dormant             INTEGER NOT NULL DEFAULT 0,
    rationale           TEXT,
    user_marked         INTEGER NOT NULL DEFAULT 0,
    CHECK (from_memory_id != to_memory_id),
    UNIQUE(from_memory_id, to_memory_id, type),
    FOREIGN KEY (from_memory_id) REFERENCES memories(id) ON DELETE CASCADE,
    FOREIGN KEY (to_memory_id) REFERENCES memories(id) ON DELETE CASCADE
  )
  ''',

  // ── 3. rooms 表（房間生長狀態）──────────────────────────────────
  '''
  CREATE TABLE IF NOT EXISTS rooms (
    id                  TEXT PRIMARY KEY,
    room                TEXT NOT NULL UNIQUE,
    memory_count        INTEGER NOT NULL DEFAULT 0,
    subdivision_count   INTEGER NOT NULL DEFAULT 0,
    last_subdivision_at INTEGER NOT NULL,
    created_at          INTEGER NOT NULL,
    updated_at          INTEGER NOT NULL
  )
  ''',

  // ── 3b. subdivision_events 表（細分事件紀錄）────────────────────
  '''
  CREATE TABLE IF NOT EXISTS subdivision_events (
    id                  TEXT PRIMARY KEY,
    room                TEXT NOT NULL,
    reason              TEXT NOT NULL DEFAULT '',
    memories_before     INTEGER NOT NULL DEFAULT 0,
    memories_after      INTEGER NOT NULL DEFAULT 0,
    new_sub_categories  TEXT,
    created_at          INTEGER NOT NULL
  )
  ''',

  // ── 4. projects 表 ──────────────────────────────────────────────
  '''
  CREATE TABLE IF NOT EXISTS projects (
    id          TEXT PRIMARY KEY,
    name        TEXT NOT NULL,
    description TEXT NOT NULL DEFAULT '',
    status      TEXT NOT NULL DEFAULT 'active',
    tags        TEXT NOT NULL DEFAULT '[]',
    created_at  INTEGER NOT NULL,
    updated_at  INTEGER NOT NULL,
    completed_at INTEGER
  )
  ''',

  // ── 5. intentions 表 ────────────────────────────────────────────
  '''
  CREATE TABLE IF NOT EXISTS intentions (
    id          TEXT PRIMARY KEY,
    title       TEXT NOT NULL DEFAULT '',
    description TEXT NOT NULL DEFAULT '',
    question    TEXT NOT NULL DEFAULT '',
    status      TEXT NOT NULL DEFAULT 'active',
    created_at  INTEGER NOT NULL,
    resolved_at INTEGER
  )
  ''',

  // ── 6. memory_intentions 中間表 ────────────────────────────────
  '''
  CREATE TABLE IF NOT EXISTS memory_intentions (
    memory_id    TEXT NOT NULL,
    intention_id TEXT NOT NULL,
    linked_at    INTEGER NOT NULL,
    user_marked  INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (memory_id, intention_id),
    FOREIGN KEY (memory_id) REFERENCES memories(id) ON DELETE CASCADE,
    FOREIGN KEY (intention_id) REFERENCES intentions(id) ON DELETE CASCADE
  )
  ''',

  // ── 7. brain_meta 表 ────────────────────────────────────────────
  // 改善 3: 加 updated_at 欄位供參數化寫入使用
  '''
  CREATE TABLE IF NOT EXISTS brain_meta (
    key        TEXT PRIMARY KEY,
    value      TEXT NOT NULL,
    updated_at TEXT NOT NULL DEFAULT (datetime('now'))
  )
  ''',

  // ── 8. wiki_links 表（雙向連結）─────────────────────────────────
  // [教練 Agent 2026-07-22] Phase 1 ① 向量資料庫 schema 擴展
  // 條目內容中的 [[條目名]] 自動解析為 wiki-link
  '''
  CREATE TABLE IF NOT EXISTS wiki_links (
    id              TEXT PRIMARY KEY,
    source_memory   TEXT NOT NULL,
    target_memory   TEXT NOT NULL,
    link_text       TEXT NOT NULL,
    created_at      INTEGER NOT NULL,
    FOREIGN KEY (source_memory) REFERENCES memories(id) ON DELETE CASCADE,
    FOREIGN KEY (target_memory) REFERENCES memories(id) ON DELETE CASCADE,
    UNIQUE(source_memory, target_memory)
  )
  ''',

  // [教練 Agent 2026-07-22] Phase E — Agent 本地知識庫
  /// agent_scripts: Agent 的腳本/SOP/範本庫
  '''
  CREATE TABLE IF NOT EXISTS agent_scripts (
    id                TEXT PRIMARY KEY,
    title             TEXT NOT NULL,
    description       TEXT,
    content           TEXT NOT NULL,
    content_type      TEXT DEFAULT 'dart',
    tags              TEXT,
    category          TEXT,
    trigger_keywords  TEXT,
    trigger_scenes    TEXT,
    embedding         BLOB,
    usage_count       INTEGER DEFAULT 0,
    last_used_at      TEXT,
    created_at        TEXT DEFAULT (datetime('now')),
    updated_at        TEXT DEFAULT (datetime('now')),
    is_pinned         INTEGER DEFAULT 0,
    source            TEXT DEFAULT 'system'
  )
  ''',

  /// agent_memories: Agent 的記憶點（教訓/偏好/模式/里程碑）
  '''
  CREATE TABLE IF NOT EXISTS agent_memories (
    id            TEXT PRIMARY KEY,
    title         TEXT NOT NULL,
    content       TEXT NOT NULL,
    tags          TEXT,
    memory_type   TEXT,
    embedding     BLOB,
    created_at    TEXT DEFAULT (datetime('now')),
    is_archived   INTEGER DEFAULT 0,
    layer         TEXT,
    embed_model_version TEXT  -- [小葵 2026-10-15 T6] 向量血型（D1）
  )
  ''',

  /// agent_scripts_fts: 全文搜尋
  '''
  CREATE VIRTUAL TABLE IF NOT EXISTS agent_scripts_fts USING fts5(
    title, description, content, tags, trigger_keywords,
    content='agent_scripts',
    content_rowid='rowid'
  )
  ''',

  /// agent_memories_fts: 全文搜尋
  '''
  CREATE VIRTUAL TABLE IF NOT EXISTS agent_memories_fts USING fts5(
    title, content, tags,
    content='agent_memories',
    content_rowid='rowid'
  )
  ''',

  // [教練 Agent 2026-07-25] §4.1 向量資料庫 — AssetIndex 檔案索引
  // [教練 Agent 2026-07-28] v8: 加 room / project_id / classification_confidence / source_type
  /// asset_index: 本機檔案索引（含 embedding 向量 + 六大房間分類）
  '''
  CREATE TABLE IF NOT EXISTS asset_index (
    id              TEXT PRIMARY KEY,
    file_path       TEXT NOT NULL UNIQUE,
    folder_root     TEXT NOT NULL,
    file_name       TEXT NOT NULL,
    file_ext        TEXT,
    file_size       INTEGER NOT NULL,
    file_modified   INTEGER NOT NULL,
    index_status    TEXT NOT NULL DEFAULT 'pending',
    indexed_at      INTEGER,
    title           TEXT,
    summary         TEXT,
    content_text    TEXT,
    asset_kind      TEXT,
    tags            TEXT DEFAULT '[]',
    embedding       BLOB,
    source          TEXT DEFAULT 'user',
    created_at      INTEGER NOT NULL,
    room            TEXT NOT NULL DEFAULT 'bridges',
    project_id      TEXT,
    classification_confidence REAL NOT NULL DEFAULT 0.0,
    source_type     TEXT NOT NULL DEFAULT 'imported',
    file_hash       TEXT,
    display_title   TEXT,
    origin_kind     TEXT,
    topic_cluster   TEXT,
    -- [小葵 2026-10-15 T0／D5] 向量血型：embed 模型版本一等欄位。
    -- 舊 DB 由 from_v19_to_v20 後的 PRAGMA 確保補欄（見 brain_database.dart）。
    embed_model_version TEXT
  )
  ''',

  /// memories_fts: 全文搜尋 memories 表
  '''
  CREATE VIRTUAL TABLE IF NOT EXISTS memories_fts USING fts5(
    content,
    content='memories',
    content_rowid='rowid'
  )
  ''',

  /// asset_fts: 全文搜尋（title / summary / content_text）
  '''
  CREATE VIRTUAL TABLE IF NOT EXISTS asset_fts USING fts5(
    title, summary, content_text,
    content='asset_index', content_rowid='rowid'
  )
  ''',

  /// asset_chunks: 檔案切片表（鐵三角 #1）
  /// 一檔多片——長文件 512+64 滑窗切片、每片獨立向量，
  /// 檢索時逐片比對，長文件每段都可獨立被找到。
  '''
  CREATE TABLE IF NOT EXISTS asset_chunks (
    chunk_id         TEXT PRIMARY KEY,
    asset_id         TEXT NOT NULL,
    chunk_index      INTEGER NOT NULL,
    content          TEXT NOT NULL,
    char_count       INTEGER NOT NULL DEFAULT 0,
    embedding        BLOB,
    embed_source     TEXT,
    model_version    TEXT,
    created_at       INTEGER NOT NULL,
    FOREIGN KEY (asset_id) REFERENCES asset_index(id) ON DELETE CASCADE,
    UNIQUE(asset_id, chunk_index)
  )
  ''',

  /// memory_asset_links: 記憶 ↔ 檔案交叉引用
  '''
  CREATE TABLE IF NOT EXISTS memory_asset_links (
    id              TEXT PRIMARY KEY,
    memory_id       TEXT NOT NULL,
    asset_id        TEXT NOT NULL,
    link_type       TEXT NOT NULL,
    note            TEXT,
    created_at      INTEGER NOT NULL,
    FOREIGN KEY (memory_id) REFERENCES memories(id) ON DELETE CASCADE,
    FOREIGN KEY (asset_id) REFERENCES asset_index(id) ON DELETE CASCADE,
    UNIQUE(memory_id, asset_id, link_type)
  )
  ''',

  // ── 15. canvas_nodes 表（節點持久化遷出 SharedPreferences）─────────
  // [教練 Agent 2026-08-26 使用者 搬遷令] 畫布節點本體入 DB——
  // SharedPreferences 是整包 JSON 重寫（無交易保護、節點多即卡），
  // 上線等級的儲存必須是 SQLite：逐列寫入、原子交易、可索引。
  // props_json 存 CanvasProps.toJson()（與舊格式完全相容）。
  '''
  CREATE TABLE IF NOT EXISTS canvas_nodes (
    entity_id   TEXT PRIMARY KEY,
    canvas_id   TEXT NOT NULL DEFAULT 'default',
    node_type   TEXT,
    props_json  TEXT NOT NULL,
    updated_at  TEXT NOT NULL DEFAULT (datetime('now'))
  )
  ''',
];

/// 所有 CREATE INDEX 語句。
///
/// 在 migration 之後執行，確保 migration 新增的欄位已存在。
/// [S23b 修復] 從 brainSchemaStatements 拆出。
const List<String> brainCreateIndexStatements = [
  /// memories: 按房間查詢
  'CREATE INDEX IF NOT EXISTS idx_memories_room ON memories(room)',

  /// memories: 按專案查詢
  'CREATE INDEX IF NOT EXISTS idx_memories_project ON memories(project)',

  /// memories: 按時間排序
  'CREATE INDEX IF NOT EXISTS idx_memories_created_at ON memories(created_at)',

  /// memories: 按歸檔狀態篩選
  'CREATE INDEX IF NOT EXISTS idx_memories_archived ON memories(archived)',

  /// memories: 按父記憶查詢（分塊）
  'CREATE INDEX IF NOT EXISTS idx_memories_parent ON memories(parent_memory_id)',

  /// memories: 按夥伴 ID 查詢（跨 Agent 共享大腦）
  'CREATE INDEX IF NOT EXISTS idx_memories_companion ON memories(companion_id)',

  /// connections: 查某記憶的所有出向連結
  'CREATE INDEX IF NOT EXISTS idx_connections_from ON connections(from_memory_id)',

  /// connections: 查某記憶的所有入向連結
  'CREATE INDEX IF NOT EXISTS idx_connections_to ON connections(to_memory_id)',

  /// connections: 按類型篩選
  'CREATE INDEX IF NOT EXISTS idx_connections_type ON connections(type)',

  /// subdivision_events: 按房間查歷史
  'CREATE INDEX IF NOT EXISTS idx_subdiv_room ON subdivision_events(room)',

  /// memory_intentions: 反向查詢（從意圖找記憶）
  'CREATE INDEX IF NOT EXISTS idx_mi_intention ON memory_intentions(intention_id)',

  /// wiki_links: 從 source 查出向連結
  'CREATE INDEX IF NOT EXISTS idx_wiki_links_source ON wiki_links(source_memory)',

  /// wiki_links: 從 target 查入向連結（backlinks）
  'CREATE INDEX IF NOT EXISTS idx_wiki_links_target ON wiki_links(target_memory)',

  // [教練 Agent 2026-07-22] Phase E — Agent 本地知識庫
  /// agent_scripts: 按分類查詢
  'CREATE INDEX IF NOT EXISTS idx_agent_scripts_category ON agent_scripts(category)',
  /// agent_scripts: 按 source 查詢
  'CREATE INDEX IF NOT EXISTS idx_agent_scripts_source ON agent_scripts(source)',
  /// agent_memories: 按類型查詢
  'CREATE INDEX IF NOT EXISTS idx_agent_memories_type ON agent_memories(memory_type)',

  // [教練 Agent 2026-07-25] §4.1 向量資料庫 — AssetIndex 索引
  /// asset_index: 按檔案路徑查詢
  'CREATE INDEX IF NOT EXISTS idx_asset_index_path ON asset_index(file_path)',
  /// asset_index: 按檔案類型查詢
  'CREATE INDEX IF NOT EXISTS idx_asset_index_kind ON asset_index(asset_kind)',
  /// asset_index: 按索引狀態篩選
  'CREATE INDEX IF NOT EXISTS idx_asset_index_status ON asset_index(index_status)',
  /// asset_index: 按來源篩選
  'CREATE INDEX IF NOT EXISTS idx_asset_index_source ON asset_index(source)',
  /// memory_asset_links: 從記憶查關聯檔案
  'CREATE INDEX IF NOT EXISTS idx_memory_asset_links_memory ON memory_asset_links(memory_id)',
  /// memory_asset_links: 從檔案查關聯記憶
  'CREATE INDEX IF NOT EXISTS idx_memory_asset_links_asset ON memory_asset_links(asset_id)',

  // [教練 Agent 2026-07-28] v8: asset_index 按房間/專案查詢
  'CREATE INDEX IF NOT EXISTS idx_asset_index_room ON asset_index(room)',
  'CREATE INDEX IF NOT EXISTS idx_asset_index_project ON asset_index(project_id)',
];

/// vector_init SQL 語句。
///
/// 由 [BrainDatabase.initialize] 在確認尚未初始化後單獨執行（改善 5）。
/// [S23b 修復] vector_init 是 SQL 函數，需用 SELECT 而非直接 execute。
const String kVectorInitSql =
    "SELECT vector_init('memories', 'embedding', 'type=FLOAT32,dimension=768')";

/// [教練 Agent 2026-08-20] 鐵三角 #3——asset_index 向量索引初始化。
///
/// 死因：kVectorInitSql 只 init 了 memories，asset_index（26022 筆資產）
/// 從未被 vector_init → vector_full_scan('asset_index',...) 每次炸掉 →
/// autoLinkByVector / 圖書館語意搜尋被 catch 靜默吞 → memory_asset_links
/// 永遠 0 行 → 資產地圖沒有半條邊。
const String kAssetVectorInitSql =
    "SELECT vector_init('asset_index', 'embedding', 'type=FLOAT32,dimension=768')";

/// [教練 Agent 2026-08-20] 鐵三角 #1——asset_chunks 向量索引初始化。
/// 比照 asset_index：vector_init 是 per-connection 記憶體態，
/// 每次開連線都要重跑（與 kAssetVectorInitSql 同一個教訓）。
const String kChunkVectorInitSql =
    "SELECT vector_init('asset_chunks', 'embedding', 'type=FLOAT32,dimension=768')";

/// [小葵 2026-09-21] agent_memories 向量索引初始化。
/// 死因與鐵三角 #3 同款：kVectorInitSql 只 init 了 memories，
/// agent_memories（Hermes 搬家 67 條行囊＋persona_card 等）從未被
/// vector_init → vector_full_scan('agent_memories',...) 每次炸掉 →
/// HybridSearchService 的 agent 記憶語意層被 catch 靜默吞 →
/// 搬家記憶向量永遠不可達。per-connection，每次開連線都要重跑。
const String kAgentVectorInitSql =
    "SELECT vector_init('agent_memories', 'embedding', 'type=FLOAT32,dimension=768')";

/// 預設 6 大房間 seed data（改善 2）。
///
/// 使用 INSERT OR IGNORE 避免重複插入。
/// 由 [BrainDatabase.initialize] 在建表後執行。
const List<String> brainSeedStatements = [
  "INSERT OR IGNORE INTO rooms (id, room, memory_count, subdivision_count, last_subdivision_at, created_at, updated_at) VALUES ('room_stream',     'stream',     0, 0, 0, 0, 0)",
  "INSERT OR IGNORE INTO rooms (id, room, memory_count, subdivision_count, last_subdivision_at, created_at, updated_at) VALUES ('room_doors',      'doors',      0, 0, 0, 0, 0)",
  "INSERT OR IGNORE INTO rooms (id, room, memory_count, subdivision_count, last_subdivision_at, created_at, updated_at) VALUES ('room_pendulums',  'pendulums',  0, 0, 0, 0, 0)",
  "INSERT OR IGNORE INTO rooms (id, room, memory_count, subdivision_count, last_subdivision_at, created_at, updated_at) VALUES ('room_heartMind',  'heartMind',  0, 0, 0, 0, 0)",
  "INSERT OR IGNORE INTO rooms (id, room, memory_count, subdivision_count, last_subdivision_at, created_at, updated_at) VALUES ('room_fraile',     'fraile',     0, 0, 0, 0, 0)",
  "INSERT OR IGNORE INTO rooms (id, room, memory_count, subdivision_count, last_subdivision_at, created_at, updated_at) VALUES ('room_bridges',    'bridges',    0, 0, 0, 0, 0)",
];

/// Schema migration steps（修正 3）。
///
/// key 格式：'from_v{N}_to_v{N+1}'
/// value：該次升級需執行的 SQL 語句列表。
///
/// 目前只有 v1→v2（加 CHECK 約束 + brain_meta updated_at 欄位）。
/// 注意：SQLite 不支援直接 ALTER TABLE ADD CHECK，
/// v1→v2 的 CHECK 約束僅對新建資料庫生效；既有庫需重建表才能套用。
// [教練 Agent 2026-08-20] v10：ingest 治本三欄位——「為圖譜服務×為 agent 服務」
// 雙服務 schema（使用者 憲章）。display_title 人話標題、origin_kind
// 資料來源性質（farm/agent/human/import…）、topic_cluster 主題集群 id
// （合集/聚類依據）。全部 NULL 可——舊資料 fallback、新資料直達。
const Map<String, List<String>> brainMigrations = {
  // [小葵 2026-09-09 Blue v2 檢索令] v14 → v15：身份嵌入兩張表。
  // folder_origin：資料夾的分類身份（人類分類/主題/來源/任務血緣）
  // topic_terms：主題詞表（屬性聯動——搜鹿角蕨帶出植物/農業相關）
  'from_v14_to_v15': [
    '''
    CREATE TABLE IF NOT EXISTS folder_origin (
      folder_path TEXT PRIMARY KEY,
      root        TEXT NOT NULL,
      category    TEXT,
      summary     TEXT,
      origin_kind TEXT,
      task_id     TEXT,
      updated_at  INTEGER NOT NULL
    )
    ''',
    '''
    CREATE TABLE IF NOT EXISTS topic_terms (
      term       TEXT PRIMARY KEY,
      related    TEXT,
      updated_at INTEGER NOT NULL
    )
    ''',
  ],
  // [小葵 2026-09-13 Blue B 決策] v15 → v16：agent 知識歸屬欄。
  // 記憶預設私有、招式預設共享（「人格是私有的、能力是公共的」）。
  // owner='shared' = 共享；owner=<companion_id> = 該夥伴私有。
  // 遷移時 hermes_migration 記憶掛小葵私有、招式掛 shared（由
  // tools/backfill_owner.py 補值，SQL 端只建欄位不動舊值）。
  'from_v15_to_v16': [
    "ALTER TABLE agent_memories ADD COLUMN owner_companion_id TEXT NOT NULL DEFAULT 'shared'",
    "ALTER TABLE agent_scripts ADD COLUMN owner_companion_id TEXT NOT NULL DEFAULT 'shared'",
    'CREATE INDEX IF NOT EXISTS idx_agent_memories_owner ON agent_memories(owner_companion_id)',
    'CREATE INDEX IF NOT EXISTS idx_agent_scripts_owner ON agent_scripts(owner_companion_id)',
  ],
  // [小葵 2026-09-15 Blue 拍板：出處戳 provenance（spike 001 VALIDATED）]
  // v16 → v17：memories.speaker——記憶的「誰說的」第一級事實。
  // user=使用者親口 / agent=夥伴生產 / external=第三方文件 / NULL=出處不明。
  // 時間感提案抓包案 #7（AI 把自己寫的農場文誤歸為使用者話語）的結構性防線。
  // 既有 349 筆不回填——誠實標記 unknown，不猜測。
  // 純文字隨行欄位：不參與向量計算、不改變檢索排序——零記憶負擔。
  'from_v16_to_v17': [
    "ALTER TABLE memories ADD COLUMN speaker TEXT",
  ],
  // [小葵 2026-10-07 Blue 贈禮拍板] v18 → v19：記憶 2域10層（H2）。
  // agent_memories.layer——記憶的溫度座標：
  //   L1 鐵則/L2 身分/L3 專案熱（工作域，注入）
  //   L4 環境/L5 決策/L6 教訓/L7 專案冷/L8 對話精華/L9 原始/L10 反思（長期域，檢索）
  // 既有 1,931 條自動歸屬（零丟失——記憶鐵律）：
  //   hermes_conversation → L8；hermes_migration → 按內容特徵；
  //   persona_card/identity → L2；lesson → L6；milestone → L5；
  //   pattern → L6；skill → L6；import_marker → L4
  // [小葵 2026-10-15 T0／Fable V3 斷鏈④] v19 → v20：向量血型欄位。
  // asset_index.embed_model_version——embed 模型版本是一等公民（D5）：
  // 換模型 = migration + 重嵌 + 頭重訓三件套，缺一不上線。
  // 注意：live DB 曾手動 ALTER 過此欄（2026-10-15），migration 對已存在欄位會炸——
  // 改用 PRAGMA 檢查式確保（見 brain_database.dart _ensureEmbedModelVersionColumn）。
  'from_v19_to_v20': [
    // [小葵 2026-10-15 T3] correction_events 建表入正典 migration——
    // 原本在 CorrectionCatcher._ensureTable（用到才建）；BeliefGate 的
    // fail-open 依賴此表查證據，表晚建＝gate 白白放行。IF NOT EXISTS 冪等。
    '''
    CREATE TABLE IF NOT EXISTS correction_events (
      id                 TEXT PRIMARY KEY,
      conversation_id    TEXT NOT NULL,
      message_id         TEXT NOT NULL,
      kind               TEXT NOT NULL,
      hit_pattern        TEXT NOT NULL,
      user_text          TEXT NOT NULL,
      assistant_context  TEXT NOT NULL DEFAULT '',
      created_at         INTEGER NOT NULL,
      ref_turn_id        TEXT
    )
    ''',
    'CREATE INDEX IF NOT EXISTS idx_correction_conv ON correction_events(conversation_id)',
    'CREATE INDEX IF NOT EXISTS idx_correction_kind ON correction_events(kind)',
  ],
  'from_v18_to_v19': [
    "ALTER TABLE agent_memories ADD COLUMN layer TEXT",
    "CREATE INDEX IF NOT EXISTS idx_agent_memories_layer ON agent_memories(layer)",
    // 既有資料歸屬（冪等——layer 為 NULL 才寫）
    "UPDATE agent_memories SET layer='L8' WHERE layer IS NULL AND memory_type='hermes_conversation'",
    "UPDATE agent_memories SET layer='L2' WHERE layer IS NULL AND memory_type IN ('persona_card','identity')",
    "UPDATE agent_memories SET layer='L6' WHERE layer IS NULL AND memory_type IN ('lesson','pattern','skill')",
    "UPDATE agent_memories SET layer='L5' WHERE layer IS NULL AND memory_type='milestone'",
    "UPDATE agent_memories SET layer='L4' WHERE layer IS NULL AND memory_type='import_marker'",
    // hermes_migration：帶鐵則/決策/環境關鍵字的進對應層，其餘 L8
    "UPDATE agent_memories SET layer='L1' WHERE layer IS NULL AND memory_type='hermes_migration' AND (content LIKE '%鐵則%' OR content LIKE '%禁%' OR tags LIKE '%鐵則%')",
    "UPDATE agent_memories SET layer='L5' WHERE layer IS NULL AND memory_type='hermes_migration' AND (content LIKE '%拍板%' OR content LIKE '%決策%' OR tags LIKE '%拍板%')",
    "UPDATE agent_memories SET layer='L4' WHERE layer IS NULL AND memory_type='hermes_migration' AND (content LIKE '%路徑%' OR content LIKE '%埠%' OR tags LIKE '%環境%')",
    "UPDATE agent_memories SET layer='L8' WHERE layer IS NULL",  // 兜底：其餘全進 L8
  ],
  // [小葵 2026-09-22 Blue 偷學令] v17 → v18：矛盾消解 superseded_by。
  // 「我搬去台北了」寫入時，語意相近且字面衝突的舊記憶標 superseded（留審計不刪）。
  // 讀取端一律過濾 superseded_by IS NOT NULL——檢索永遠走在現行事實上。
  'from_v17_to_v18': [
    "ALTER TABLE memories ADD COLUMN superseded_by TEXT",
    "CREATE INDEX IF NOT EXISTS idx_memories_superseded ON memories(superseded_by)",
  ],
  // [小葵 2026-09-09 Blue 分層令] v13 → v14：audience 分層欄。
  // general=一般使用者（預設搜尋可見）；technical=工程師層（vendored
  // 依賴庫/開發工具設定/建置產物——保留但預設搜尋不可見）。
  // 既有資料回填：按路徑特徵分類（AssetSandbox.isTechnicalPath 同款邏輯
  // 的 SQL 版），無法判定者維持 general（寧可多見不可漏掉使用者的檔案）。
  'from_v13_to_v14': [
    "ALTER TABLE asset_index ADD COLUMN audience TEXT NOT NULL DEFAULT 'general'",
    "CREATE INDEX IF NOT EXISTS idx_asset_audience ON asset_index(audience)",
    // 回填：vendored 依賴庫 + 開發工具隱藏目錄 + 建置產物 → technical
    "UPDATE asset_index SET audience = 'technical' WHERE file_path LIKE '%/lib/openzeppelin-contracts/%' OR file_path LIKE '%/lib/forge-std/%' OR file_path LIKE '%node_modules/%'",
    "UPDATE asset_index SET audience = 'technical' WHERE file_path LIKE '%/.github/%' OR file_path LIKE '%/.claude/%' OR file_path LIKE '%/.dart_tool/%' OR file_path LIKE '%/.husky/%' OR file_path LIKE '%/.changeset/%' OR file_path LIKE '%/.obsidian/%'",
    "UPDATE asset_index SET audience = 'technical' WHERE (file_path LIKE '%/build/%' AND (file_path LIKE '%.saver%' OR file_path LIKE '%.app/%')) OR file_path LIKE '%.app/Contents/%'",
    // 清除 junk（Icon\r / AppleDouble ._*）——四層全清：asset_chunks →
    // asset_index（embedding 隨列刪）。manifest 端由 App 內 fullScan 重寫。
    "DELETE FROM asset_chunks WHERE asset_id IN (SELECT id FROM asset_index WHERE file_name = 'Icon' OR file_path LIKE '%/._%')",
    "DELETE FROM asset_index WHERE file_name = 'Icon' OR file_path LIKE '%/._%'",
  ],

  // [教練 Agent 2026-08-20] v11：鐵三角 #1——asset_chunks 切片表 +
  // asset_index.embed_source 冪等標記（'filename' 舊假向量 /
  // 'metadata' 中繼文字 / 'content' 真內容 / 'vision' Vision 描述）
  'from_v10_to_v11': [
    '''
    CREATE TABLE IF NOT EXISTS asset_chunks (
      chunk_id         TEXT PRIMARY KEY,
      asset_id         TEXT NOT NULL,
      chunk_index      INTEGER NOT NULL,
      content          TEXT NOT NULL,
      char_count       INTEGER NOT NULL DEFAULT 0,
      embedding        BLOB,
      embed_source     TEXT,
      model_version    TEXT NOT NULL,
      created_at       INTEGER NOT NULL,
      FOREIGN KEY (asset_id) REFERENCES asset_index(id) ON DELETE CASCADE,
      UNIQUE(asset_id, chunk_index)
    )
    ''',
    'CREATE INDEX IF NOT EXISTS idx_asset_chunks_asset ON asset_chunks(asset_id)',
    'ALTER TABLE asset_index ADD COLUMN embed_source TEXT',
  ],

  'from_v9_to_v10': [
    'ALTER TABLE asset_index ADD COLUMN display_title TEXT',
    'ALTER TABLE asset_index ADD COLUMN origin_kind TEXT',
    'ALTER TABLE asset_index ADD COLUMN topic_cluster TEXT',
    'CREATE INDEX IF NOT EXISTS idx_asset_topic_cluster ON asset_index(topic_cluster)',
  ],

  // [小葵 2026-08-28 Blue 開工令] v12 → v13：排程任務血緣鏈 + 檔案因果鏈。
  // scheduled_tasks：排程任務實體（名稱/cron/prompt/所屬專案/畫布）
  // task_asset_links：任務↔產出檔案（provenance 生產線）
  // asset_causal_links：檔案↔檔案因果（cause→effect + relation 種類 + 強度）
  'from_v12_to_v13': [
    '''
    CREATE TABLE IF NOT EXISTS scheduled_tasks (
      id            TEXT PRIMARY KEY,
      name          TEXT NOT NULL,
      schedule_expr TEXT NOT NULL,
      prompt        TEXT,
      status        TEXT NOT NULL DEFAULT 'active',
      project_id    TEXT,
      canvas_id     TEXT,
      last_run_at   INTEGER,
      created_at    INTEGER NOT NULL
    )
    ''',
    '''
    CREATE TABLE IF NOT EXISTS task_asset_links (
      id         INTEGER PRIMARY KEY AUTOINCREMENT,
      task_id    TEXT NOT NULL,
      asset_id   TEXT NOT NULL,
      link_type  TEXT NOT NULL DEFAULT 'produced',
      created_at INTEGER NOT NULL,
      FOREIGN KEY (asset_id) REFERENCES asset_index(id) ON DELETE CASCADE,
      UNIQUE(task_id, asset_id)
    )
    ''',
    'CREATE INDEX IF NOT EXISTS idx_task_links_asset ON task_asset_links(asset_id)',
    '''
    CREATE TABLE IF NOT EXISTS asset_causal_links (
      id         INTEGER PRIMARY KEY AUTOINCREMENT,
      cause_id   TEXT NOT NULL,
      effect_id  TEXT NOT NULL,
      relation   TEXT NOT NULL DEFAULT 'causes',
      strength   REAL NOT NULL DEFAULT 1.0,
      source     TEXT NOT NULL DEFAULT 'manual',
      note       TEXT,
      created_at INTEGER NOT NULL,
      FOREIGN KEY (cause_id) REFERENCES asset_index(id) ON DELETE CASCADE,
      FOREIGN KEY (effect_id) REFERENCES asset_index(id) ON DELETE CASCADE,
      UNIQUE(cause_id, effect_id, relation)
    )
    ''',
    'CREATE INDEX IF NOT EXISTS idx_causal_cause ON asset_causal_links(cause_id)',
    'CREATE INDEX IF NOT EXISTS idx_causal_effect ON asset_causal_links(effect_id)',
  ],

  // [教練 Agent 2026-08-26 使用者 搬遷令] v11 → v12：canvas_nodes
  // 畫布節點從 SharedPreferences（整包 JSON）搬進 SQLite（逐列、可交易）。
  // 資料搬遷由 SqliteCanvasStateStore 首次啟動時自動執行（plist → DB）。
  'from_v11_to_v12': [
    '''
    CREATE TABLE IF NOT EXISTS canvas_nodes (
      entity_id   TEXT PRIMARY KEY,
      canvas_id   TEXT NOT NULL DEFAULT 'default',
      node_type   TEXT,
      props_json  TEXT NOT NULL,
      updated_at  TEXT NOT NULL DEFAULT (datetime('now'))
    )
    ''',
    'CREATE INDEX IF NOT EXISTS idx_canvas_nodes_canvas ON canvas_nodes(canvas_id)',
  ],
  'from_v1_to_v2': [
    // brain_meta 加 updated_at 欄位（SQLite ALTER TABLE 僅支援 ADD COLUMN）
    "ALTER TABLE brain_meta ADD COLUMN updated_at TEXT NOT NULL DEFAULT (datetime('now'))",
  ],
  'from_v2_to_v3': [
    // memories 表加 vector_model_version 欄位
    'ALTER TABLE memories ADD COLUMN vector_model_version TEXT',
  ],
  'from_v3_to_v4': [
    // memories 表加 companion_id 欄位（跨 Agent 共享大腦）
    "ALTER TABLE memories ADD COLUMN companion_id TEXT NOT NULL DEFAULT ''",
    // 建索引（IF NOT EXISTS 確保安全）
    'CREATE INDEX IF NOT EXISTS idx_memories_companion ON memories(companion_id)',
  ],
  'from_v4_to_v5': [
    // [教練 Agent 2026-07-22] Phase 1 ① wiki_links 表 + 索引
    '''
    CREATE TABLE IF NOT EXISTS wiki_links (
      id              TEXT PRIMARY KEY,
      source_memory   TEXT NOT NULL,
      target_memory   TEXT NOT NULL,
      link_text       TEXT NOT NULL,
      created_at      INTEGER NOT NULL,
      FOREIGN KEY (source_memory) REFERENCES memories(id) ON DELETE CASCADE,
      FOREIGN KEY (target_memory) REFERENCES memories(id) ON DELETE CASCADE,
      UNIQUE(source_memory, target_memory)
    )
    ''',
    'CREATE INDEX IF NOT EXISTS idx_wiki_links_source ON wiki_links(source_memory)',
    'CREATE INDEX IF NOT EXISTS idx_wiki_links_target ON wiki_links(target_memory)',
  ],
  // [教練 Agent 2026-07-22] Phase E — Agent 本地知識庫
  'from_v5_to_v6': [
    '''
    CREATE TABLE IF NOT EXISTS agent_scripts (
      id                TEXT PRIMARY KEY,
      title             TEXT NOT NULL,
      description       TEXT,
      content           TEXT NOT NULL,
      content_type      TEXT DEFAULT 'dart',
      tags              TEXT,
      category          TEXT,
      trigger_keywords  TEXT,
      trigger_scenes    TEXT,
      embedding         BLOB,
      usage_count       INTEGER DEFAULT 0,
      last_used_at      TEXT,
      created_at        TEXT DEFAULT (datetime('now')),
      updated_at        TEXT DEFAULT (datetime('now')),
      is_pinned         INTEGER DEFAULT 0,
      source            TEXT DEFAULT 'system'
    )
    ''',
    '''
    CREATE TABLE IF NOT EXISTS agent_memories (
      id            TEXT PRIMARY KEY,
      title         TEXT NOT NULL,
      content       TEXT NOT NULL,
      tags          TEXT,
      memory_type   TEXT,
      embedding     BLOB,
      created_at    TEXT DEFAULT (datetime('now')),
      is_archived   INTEGER DEFAULT 0,
      layer         TEXT
    )
    ''',
    '''
    CREATE VIRTUAL TABLE IF NOT EXISTS agent_scripts_fts USING fts5(
      title, description, content, tags, trigger_keywords,
      content='agent_scripts',
      content_rowid='rowid'
    )
    ''',
    '''
    CREATE VIRTUAL TABLE IF NOT EXISTS agent_memories_fts USING fts5(
      title, content, tags,
      content='agent_memories',
      content_rowid='rowid'
    )
    ''',
  ],
  // [教練 Agent 2026-07-25] §4.1 向量資料庫 — AssetIndex schema 擴展
  'from_v6_to_v7': [
    // asset_index: 本機檔案索引
    '''
    CREATE TABLE IF NOT EXISTS asset_index (
      id              TEXT PRIMARY KEY,
      file_path       TEXT NOT NULL UNIQUE,
      folder_root     TEXT NOT NULL,
      file_name       TEXT NOT NULL,
      file_ext        TEXT,
      file_size       INTEGER NOT NULL,
      file_modified   INTEGER NOT NULL,
      index_status    TEXT NOT NULL DEFAULT 'pending',
      indexed_at      INTEGER,
      title           TEXT,
      summary         TEXT,
      content_text    TEXT,
      asset_kind      TEXT,
      tags            TEXT DEFAULT '[]',
      embedding       BLOB,
      source          TEXT DEFAULT 'user',
      created_at      INTEGER NOT NULL
    )
    ''',
    // asset_fts: 全文搜尋
    '''
    CREATE VIRTUAL TABLE IF NOT EXISTS asset_fts USING fts5(
      title, summary, content_text,
      content='asset_index', content_rowid='rowid'
    )
    ''',
    // memory_asset_links: 記憶 ↔ 檔案交叉引用
    '''
    CREATE TABLE IF NOT EXISTS memory_asset_links (
      id              TEXT PRIMARY KEY,
      memory_id       TEXT NOT NULL,
      asset_id        TEXT NOT NULL,
      link_type       TEXT NOT NULL,
      note            TEXT,
      created_at      INTEGER NOT NULL,
      FOREIGN KEY (memory_id) REFERENCES memories(id) ON DELETE CASCADE,
      FOREIGN KEY (asset_id) REFERENCES asset_index(id) ON DELETE CASCADE,
      UNIQUE(memory_id, asset_id, link_type)
    )
    ''',
    // 索引
    'CREATE INDEX IF NOT EXISTS idx_asset_index_path ON asset_index(file_path)',
    'CREATE INDEX IF NOT EXISTS idx_asset_index_kind ON asset_index(asset_kind)',
    'CREATE INDEX IF NOT EXISTS idx_asset_index_status ON asset_index(index_status)',
    'CREATE INDEX IF NOT EXISTS idx_asset_index_source ON asset_index(source)',
    'CREATE INDEX IF NOT EXISTS idx_memory_asset_links_memory ON memory_asset_links(memory_id)',
    'CREATE INDEX IF NOT EXISTS idx_memory_asset_links_asset ON memory_asset_links(asset_id)',
  ],
  // [教練 Agent 2026-07-28] 向量資料庫 × 大腦圖譜融合 — asset_index 加欄位
  'from_v7_to_v8': [
    "ALTER TABLE asset_index ADD COLUMN room TEXT NOT NULL DEFAULT 'bridges'",
    'ALTER TABLE asset_index ADD COLUMN project_id TEXT',
    'ALTER TABLE asset_index ADD COLUMN classification_confidence REAL NOT NULL DEFAULT 0.0',
    "ALTER TABLE asset_index ADD COLUMN source_type TEXT NOT NULL DEFAULT 'imported'",
    // 新索引：按房間查詢 + 按專案查詢
    'CREATE INDEX IF NOT EXISTS idx_asset_index_room ON asset_index(room)',
    'CREATE INDEX IF NOT EXISTS idx_asset_index_project ON asset_index(project_id)',
    // [小葵 2026-10-14 Blue 報案 vault 開頁 10-20s] covering index——
    // embedding blob（每行 3KB）把 room/title 擠到分散頁面，vault 查詢
    // 回表隨機讀 67k 次=6.5-7.8s。覆蓋索引後 0.03s（260 倍）。
    'CREATE INDEX IF NOT EXISTS idx_asset_vault_cover ON asset_index(file_path, room, title, classification_confidence, id, audience)',
  ],
  // [教練 Agent 2026-07-31] v9: memories_fts 全文搜尋 + asset_index file_hash
  'from_v8_to_v9': [
    // memories_fts: 全文搜尋 memories 表
    "CREATE VIRTUAL TABLE IF NOT EXISTS memories_fts USING fts5(content, content='memories', content_rowid='rowid')",
    // 填入現有 memories 資料到 FTS
    "INSERT INTO memories_fts(rowid, content) SELECT rowid, content FROM memories WHERE content IS NOT NULL",
    // asset_index 加 file_hash 欄位
    "ALTER TABLE asset_index ADD COLUMN file_hash TEXT",
  ],
};

/// 取得完整 schema SQL（建表 + 索引，按順序執行）。
///
/// 注意：此 getter 僅供外部參考用。BrainDatabase.initialize() 內部
/// 會將建表和建索引分開執行，中間插入 migration（S23b 修復）。
String get brainSchemaSql =>
    '${[...brainCreateTableStatements, ...brainCreateIndexStatements].join(";\n\n")};';
