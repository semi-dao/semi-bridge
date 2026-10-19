# 橋樑 App 本地埠說明（Ports）

橋樑 App 是「本地優先」的架構：AI 推論、向量嵌入、Agent 通道全部跑在你的機器上。以下是 App 及其夥伴服務會用到的 localhost 埠。

> 全部埠只綁 `127.0.0.1`（loopback）——不對外網開放。MCP 埠（8420）需要 token 認證。

| 埠 | 服務 | 用途 | 誰啟動 |
|----|------|------|--------|
| **8420** | Bridge MCP Server | App 的感官與手——MCP 協定通道（導航、截圖、對話注入、畫布操作等 50+ 工具） | App 內建，隨 App 啟動 |
| **18789** | llama-server（LLM） | 本地對話模型推論（預設 Gemma-3 E4B） | `scripts/launchd/` 或 auto-clutch |
| **18890** | llama-server（Embedding） | 向量嵌入模型（embeddinggemma-2 300M，EG2）——記憶檢索的單一向量空間 | `scripts/launchd/` 常駐 |
| **18900** | Kokoro TTS（選配） | 本地語音合成 | 使用者自架 |

## 驗證服務是否活著

```bash
curl -s http://127.0.0.1:8420/health
curl -s http://127.0.0.1:18789/health
curl -s http://127.0.0.1:18890/health
```

注意：`/health` 回 200 只代表 HTTP 層活著，**不代表推論可用**——深度檢查請打一個小推論請求。

## MCP 認證

8420 的 MCP 呼叫需要 `X-Bridge-Token` header（token 存於 App Support 目錄的 `mcp_token` 檔）。沒有 token 的請求會被拒絕。

---

# Bridge App Local Ports

Bridge App is a local-first architecture: LLM inference, vector embedding, and the agent channel all run on your machine. These are the localhost ports used by the app and its companion services.

> All ports bind to `127.0.0.1` (loopback) only — never exposed to the network. The MCP port (8420) requires token authentication.

| Port | Service | Purpose | Started by |
|------|---------|---------|------------|
| **8420** | Bridge MCP Server | The app's senses and hands — MCP protocol channel (navigation, screenshots, chat injection, canvas ops, 50+ tools) | Built into the app |
| **18789** | llama-server (LLM) | Local chat model inference (default: Gemma-3 E4B) | `scripts/launchd/` or auto-clutch |
| **18890** | llama-server (Embedding) | Vector embedding model (embeddinggemma-2 300M, EG2) — the single vector space for memory retrieval | `scripts/launchd/` daemon |
| **18900** | Kokoro TTS (optional) | Local text-to-speech | User-installed |

## Verifying services are alive

```bash
curl -s http://127.0.0.1:8420/health
curl -s http://127.0.0.1:18789/health
curl -s http://127.0.0.1:18890/health
```

Note: a 200 from `/health` only means the HTTP layer is up — **it does not guarantee inference works**. For a deep check, send a small inference request.

## MCP authentication

MCP calls on 8420 require the `X-Bridge-Token` header (the token lives in the `mcp_token` file under the App Support directory). Requests without a token are rejected.
