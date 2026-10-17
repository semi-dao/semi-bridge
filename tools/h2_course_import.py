# H2 知識支線：微軟生成式AI課程 → agent_memories L4
# 冪等：title + memory_type 查重（模板抄 m4_hermes_memory_import）
import sqlite3, re, uuid
from datetime import datetime, timezone

DB = '<HOME>/Library/Application Support/farm.semiwasabi.bridgeApp/brain_container.db'
REPO = 'https://github.com/microsoft/generative-ai-for-beginners'

# ── A 級：人工執筆精華卡（zh-TW 課文消化後 3-5 條核心觀念＋橋樑視角＋實作線索）──
A_CARDS = [
 dict(no='04', title='Prompt 工程基礎', core='''核心觀念：
1. Prompt 是給模型的「任務說明書」——結構（脈絡→指令→輸出格式）比魔法咒語重要
2. 基礎技巧：明確指令、指定輸出格式、給範例（few-shot）、分解複雜任務
3. 脈絡窗口有限——重要資訊放前面，無關內容不進 prompt
4. 迭代改善：把 prompt 當程式碼，版本化、測試、逐步收斂''',
 bridge='橋樑視角：夥伴的系統 prompt（L1 鐵則＋L2 身分注入）就是這課的實戰版——M3 注入引擎的 8K 窗口紀律（只注入 L1-L3、後面靠檢索）正是「脈絡窗口有限」的工程化解法。',
 impl='實作線索：chat_controller 分層注入／AgentLoopPromptBuilder',
 url=f'{REPO}/tree/main/04-prompt-engineering-fundamentals'),
 dict(no='05', title='進階 Prompt 技巧', core='''核心觀念：
1. Few-shot prompting：給 2-5 個輸入輸出範例，模型模仿格式與風格
2. Chain-of-thought：要求「一步步想」提升推理任務正確率
3. ReAct 模式：Reason+Act 交錯——agent 的思考原型
4. Prompt chaining：複雜任務拆成串接的多個小 prompt''',
 bridge='橋樑視角：skill 系統（S20 關鍵字注入）就是「把 few-shot 範例變成可管理的資產」；agent loop 的工具呼叫循環是 ReAct 的產品化。',
 impl='實作線索：agent_scripts 157 招／AgentLoop 工具循環',
 url=f'{REPO}/tree/main/05-advanced-prompts'),
 dict(no='15', title='RAG 與向量資料庫', core='''核心觀念：
1. RAG＝檢索增強生成：先查資料再把結果塞進 prompt——解決幻覺與知識過期
2. 流程：文件切塊 → embedding → 向量庫 → 相似度檢索 → 注入生成
3. 向量庫用「語意距離」找答案，FTS 用「關鍵字」找答案——混合檢索最強
4. RAG 讓模型「帶著課本考試」，不必把知識塞進參數（微調）''',
 bridge='橋樑視角：vault 就是橋樑的 RAG 實作——asset_index embedding＋hybrid_search（FTS+語意雙軌）正是課本說的混合檢索。M 線十層記憶是「個人版 RAG」：L1-L3 常駐、L4-L10 檢索引用。',
 impl='實作線索：vault_screen／hybrid_search_service／memory_layer_service.search',
 url=f'{REPO}/tree/main/15-rag-and-vector-databases'),
 dict(no='16', title='開放原始碼模型', core='''核心觀念：
1. 「開放模型」頻譜：完全開放（資料集+權重+訓練碼，如 OLMo）→ 權重開放（Llama 類）→ 閉源 API
2. 優點：可定制化、每 token 成本低、可離線自主運行、無審查過濾
3. Hugging Face 是開放模型的GitHub——模型卡、量化版本、生態齊全
4. 開放模型夠小就能跑在本地硬體——主權的技術基礎''',
 bridge='橋樑視角：這是本地模型主權的核心課。橋樑立場「Token 自由、資料不出家門」的學理基礎全在這——@18789 本地模型分層（E4B 對話/12B 重工）就是開放模型的實踐。',
 impl='實作線索：local_model_catalog／本地模型分層',
 url=f'{REPO}/tree/main/16-open-source-models'),
 dict(no='17', title='AI Agents', core='''核心觀念：
1. Agent＝LLM 大腦 + 工具手腳 + 迴圈（感知→思考→行動→觀察）
2. 設計要素：任務分解、工具選擇、記憶（短期對話+長期知識）、終止條件
3. 單 agent 適深任務；多 agent 適可並行分解的寬任務
4. Agent 好壞看「失敗處理」：重試、降級、人類求助點''',
 bridge='橋樑視角：夥伴系統的理論框架。小葵=單 agent 深任務＋subagent 並行（delegation）；失敗處理=誠實鐵則（裝不動紅字）＋看門狗斷電。',
 impl='實作線索：companion 系統／agent_loop／delegate',
 url=f'{REPO}/tree/main/17-ai-agents'),
 dict(no='19', title='SLM 小模型', core='''核心觀念：
1. SLM（1-5B 參數）在常見任務接近大模型，成本低、延遲小、可手機/邊緣跑
2. 「夠用就好」哲學：任務決定模型大小，不是越大越好
3. 混合部署：小模型守日常、難題升級大模型——智慧路由
4. SLM 可整包下載離線用——隱私與主權場景的答案''',
 bridge='橋樑視角：本地模型分工的學理背書——E4B 顧對話、12B 出役重活，正是課本說的混合部署。橋樑未來手機版 companion 用 SLM 離線跑，主權帶著走。',
 impl='實作線索：local_hardware_profile／模型分層路由',
 url=f'{REPO}/tree/main/19-slm'),
]

# ── B/C 級：英文要點卡（之後批次 zh-TW 校稿）──
BC_CARDS = [
 dict(no='01', title='GenAI 入門', core='Core: GenAI creates new content (text/code/image) vs traditional ML predicts. Transformer architecture + scale enables emergence. Key concepts: tokens, context window, temperature.',
  bridge='橋樑視角：入門地圖——夥伴的「大腦」就是 GenAE 模型，這課給詞彙表。', impl='—'),
 dict(no='02', title='比較 LLM', core='Core: LLM landscape—proprietary (GPT/Claude) vs open (Llama/Mistral). Evaluation axes: cost, latency, quality, hosting. Choose per task.',
  bridge='橋樑視角：選模型=選樂手——橋樑的多 provider registry 就是這課的產品化。', impl='provider_registry'),
 dict(no='03', title='負責任使用', core='Core: harms taxonomy (bias/hallucination/harmful content), mitigation layers (system prompt/safety filters/human review), transparency.',
  bridge='橋樑視角：誠實鐵則（零假成功、裝不動紅字）是這課「透明」原則的工程化。', impl='—'),
 dict(no='11', title='Function Calling', core='Core: LLM outputs structured JSON to call functions—bridge from text to action. Schema-defined tools, JSON mode, the precursor of MCP.',
  bridge='橋樑視角：MCP 的直系祖先——8420 通道的 68 條 route 就是 function calling 的全面產品化。', impl='desktop_bridge_gateway'),
 dict(no='12', title='AI 應用 UX', core='Core: AI UX patterns—streaming, feedback loops, trust building, showing uncertainty, human-in-the-loop.',
  bridge='橋樑視角：共視宣言的對話素材——「共同看見」是 AI UX 的下一個模式，課本還沒寫到，我們先做了。', impl='COVISION_MANIFESTO'),
 dict(no='18', title='LLM 微調', core='Core: Fine-tuning adapts weights with domain data (vs RAG retrieves). LoRA makes it cheap. When to fine-tune vs RAG: style/format→FT, knowledge→RAG.',
  bridge='橋樑視角：微調是「改腦」、RAG 是「帶課本」——橋樑記憶系統選了 RAG 路線（資產可攜帶、可審計）。', impl='memory_layer_service'),
 dict(no='13', title='AI 應用安全', core='Core: threat model—prompt injection, data leakage, jailbreak. Defenses: input validation, least privilege, output filtering.',
  bridge='橋樑視角：DataPathGate＋金鑰匙＝least privilege 的檔案版；插槽 deny-by-default 權限就是這課的實作。', impl='DataPathGate／slot permissions'),
 dict(no='06', title='文字生成應用', core='Core: text-gen app pattern—prompt template + context + model call + streaming UI. Azure-flavored but pattern is universal.',
  bridge='橋樑視角：課本的 Azure 服務綁定這層稀釋掉，取「模板+脈絡+串流」骨架即可——夥伴對話流同構。', impl='chat pipeline'),
 dict(no='07', title='聊天應用', core='Core: chat app anatomy—history management, context window budgeting, streaming, memory design (short vs long term).',
  bridge='橋樑視角：十層記憶=這課 memory design 的深度展開（2域10層 vs 課本的 short/long 二分）。', impl='memory 2domains-10layers'),
 dict(no='08', title='搜尋應用', core='Core: AI search = semantic embeddings + keyword hybrid + reranking. Vector similarity complements not replaces keyword.',
  bridge='橋樑視角：hybrid_search 早已雙軌——課本驗證我們的選型。', impl='hybrid_search_service'),
 dict(no='09', title='影像應用', core='Core: image gen patterns—prompt engineering for images, inpainting, batch pipelines.',
  bridge='橋樑視角：IG 小編產圖流可參考；本地 Stable Diffusion 是主權版本。', impl='image pipeline'),
 dict(no='10', title='低程式碼 AI', core='Core: low-code AI app builders—trade flexibility for speed. Good for prototypes.',
  bridge='橋樑視角：橋樑反其道——給 agent 寫程式碼的能力（插槽+CLI），讓「低代碼」變「agent 全代碼」。', impl='—'),
 dict(no='14', title='GenAI 應用生命週期', core='Core: LLMOps—eval, monitoring, iteration. Data flywheel: usage→feedback→improvement.',
  bridge='橋樑視角：M5 容量儀表＋watchdog 日誌是 monitoring 的起點；教訓→skill 回流（C6×M6）是 flywheel。', impl='M5 gauge／watchdog'),
 dict(no='20', title='Mistral 課', core='Core: Mistral open models lineup—Mixtral MoE architecture, efficient inference, European sovereignty angle.',
  bridge='橋樑視角：MoE 架構概念已入第16課；主權角度與橋樑共鳴。', impl='—'),
 dict(no='21', title='Meta Llama 課', core='Core: Llama family + LlamaGuard safety layer. Weight-open ecosystem.',
  bridge='橋樑視角：權重開放模型的代表案例，對照第16課頻譜。', impl='—'),
]

conn = sqlite3.connect(DB)
cur = conn.cursor()
now = datetime.now(timezone.utc).isoformat()

def upsert(card, tier):
    title = f'[AI課程] {card["no"]} {card["title"]}'
    tags = f'["course", "ms-genai", "L{card["no"]}"]'
    content = f'''{card["title"]}（{tier}級）

{card["core"]}

{card["bridge"] if "bridge" in card else card.get("bridge","")}
{card["impl"]}

出處：microsoft/generative-ai-for-beginners 第{card["no"]}課（MIT）
原文：{card.get("url", REPO)}'''
    row = cur.execute("SELECT id FROM agent_memories WHERE title=? AND memory_type='course_knowledge'",
                      (title,)).fetchone()
    if row:
        cur.execute("UPDATE agent_memories SET content=?, tags=? WHERE id=?",
                    (content, tags, row[0]))
        return 'updated'
    cur.execute("""INSERT INTO agent_memories
        (id, title, content, tags, memory_type, layer, created_at, is_archived, owner_companion_id)
        VALUES (?,?,?,?,?,?,?,?,?)""",
        (f'course_ms_{card["no"]}', title, content, tags, 'course_knowledge', 'L4',
         now, 0, 'shared'))
    return 'inserted'

ins = upd = 0
for c in A_CARDS:
    r = upsert(c, 'A'); ins += r=='inserted'; upd += r=='updated'
for c in BC_CARDS:
    r = upsert(c, 'B'); ins += r=='inserted'; upd += r=='updated'
conn.commit()
# FTS rebuild
cur.execute("INSERT INTO agent_memories_fts(agent_memories_fts) VALUES('rebuild')")
conn.commit()
print(f'入庫: {ins} 新增 / {upd} 更新')
# 驗收 1：bigram 搜 RAG 命中第15課
r = cur.execute("""SELECT title FROM agent_memories
    WHERE memory_type='course_knowledge' AND (content LIKE '%RAG%' OR title LIKE '%RAG%')""").fetchall()
print('搜「RAG」命中:', [x[0] for x in r])
conn.close()
