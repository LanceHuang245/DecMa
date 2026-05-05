# IPC 协议规范 (IPC_SPEC)

> 定义 Tauri 前端与 Rust 后端之间的所有通信协议。前端通过 `invoke` 调用命令，通过 `listen` 接收事件。

---

## 一、通信方式

```
前端 ── invoke("command", { args }) ──→ Rust Command Handler ──→ Result<T, String>
前端 ←── listen("event", callback)  ←── Rust app.emit("event", payload)
```

| 方向 | 方式 | 适用场景 |
|------|------|---------|
| 前端 → 后端 | `invoke()` | 请求-响应（获取数据、发送消息、保存配置） |
| 后端 → 前端 | `app.emit()` | 服务端推送（实时行情、流式 AI 输出、错误通知） |

---

## 二、Tauri Invoke 命令清单

### 2.1 市场数据

#### `get_klines`
获取指定币种的历史 K 线数据。

```
invoke("get_klines", {
    symbol: string,     // 交易对，如 "BTCUSDT"
    interval: string,   // K线周期 "1m"|"5m"|"15m"|"1h"|"4h"|"1d"
    limit?: u16,        // 获取数量，默认 100，最大 1000
})
→ Result<Kline[], string>
```

#### `get_order_book`
获取指定币种的订单簿深度。

```
invoke("get_order_book", {
    symbol: string,     // 交易对
    limit?: u16,        // 深度档位，默认 20
})
→ Result<OrderBook, string>
```

#### `get_ticker_24h`
获取 24 小时行情概览。

```
invoke("get_ticker_24h", {
    symbol: string,
})
→ Result<Ticker24h, string>
```

#### `subscribe_symbol`
订阅指定币种的实时市场数据推送。后端开始通过 `market-data` 事件推送数据。

```
invoke("subscribe_symbol", {
    symbol: string,             // 交易对
    intervals: string[],        // 要订阅的K线周期 ["1h","4h","1d"]
    depth_levels?: u16,         // 深度档位，默认 20
})
→ Result<void, string>
```

#### `unsubscribe_symbol`
取消订阅指定币种，停止对应的 `market-data` 事件推送。

```
invoke("unsubscribe_symbol", {
    symbol: string,
})
→ Result<void, string>
```

---

### 2.2 AI 对话

#### `chat_send`
发送用户消息，启动 Agent 循环。流式响应通过 `chat-stream` 事件返回。

```
invoke("chat_send", {
    message: string,            // 用户输入
    context: ChatContext,       // 对话上下文
})
→ Result<void, string>
```

```typescript
interface ChatContext {
    symbol: string;             // 当前选中币种
    available_sources: string[];// 已配置的数据源 ["newsapi", "twitter", "onchain"]
    conversation_id?: string;   // 如需继续之前的对话
}
```

#### `chat_cancel`
取消当前正在进行的 Agent 对话。

```
invoke("chat_cancel")
→ Result<void, string>
```

#### `chat_get_history`
获取本地存储的对话历史列表。

```
invoke("chat_get_history", {
    conversation_id?: string,   // 不传则返回所有对话摘要
})
→ Result<ConversationSummary[] | ConversationDetail, string>
```

```typescript
interface ConversationSummary {
    id: string;
    title: string;              // 自动生成或用户首句截取
    created_at: number;         // Unix ms
    updated_at: number;
    message_count: number;
}

interface ConversationDetail {
    id: string;
    messages: ChatMessage[];
    created_at: number;
    updated_at: number;
}
```

#### `chat_delete_history`
删除对话历史。

```
invoke("chat_delete_history", {
    conversation_id: string,
})
→ Result<void, string>
```

---

### 2.3 资讯流

#### `feed_fetch`
获取指定币种的资讯流（从 RAG 本地存储读取，不实时调用外部 API）。

```
invoke("feed_fetch", {
    symbol: string,             // 币种
    filter?: "all"|"news"|"tweet"|"onchain",  // 来源筛选，默认 "all"
    limit?: u16,                // 返回数量，默认 50
})
→ Result<FeedItem[], string>
```

```typescript
interface FeedItem {
    id: string;
    source_type: "news" | "tweet" | "onchain";
    source_name: string;        // "NewsAPI" | "Twitter/X" | "Whale Alert"
    title: string;
    summary: string;            // 摘要，推文则为正文截断
    content: string;            // 完整内容
    url: string;                // 原文链接
    published_at: number;       // Unix ms
    keywords: string[];
    related_symbol?: string;
}
```

#### `feed_refresh`
手动触发资讯采集（正常情况每 5 分钟自动采集）。

```
invoke("feed_refresh")
→ Result<void, string>
```

---

### 2.4 设置

#### `settings_get_status`
获取所有 API Key 的配置状态（不返回密钥值，仅状态）。

```
invoke("settings_get_status")
→ Result<ApiKeyStatus[], string>
```

```typescript
interface ApiKeyStatus {
    provider: string;           // "openai"|"anthropic"|"ollama"|"binance"|"newsapi"|"twitter"|"etherscan"
    configured: boolean;
    label: string;              // 显示名称 "OpenAI API Key"
    required: boolean;          // 是否必填
}
```

#### `settings_set_api_key`
存储 API Key 到 OS Keychain。

```
invoke("settings_set_api_key", {
    provider: string,           // 与 ApiKeyStatus.provider 对应
    key: string,                // API Key 明文（立即加密存储）
})
→ Result<void, string>
```

#### `settings_delete_api_key`
从 Keychain 删除 API Key。

```
invoke("settings_delete_api_key", {
    provider: string,
})
→ Result<void, string>
```

#### `settings_set_llm_provider`
切换 LLM 提供商。

```
invoke("settings_set_llm_provider", {
    provider: "openai"|"anthropic"|"ollama",
})
→ Result<void, string>
```

#### `settings_set_llm_model`
切换 LLM 模型。

```
invoke("settings_set_llm_model", {
    model: string,              // "gpt-4o-mini"|"claude-3.5-sonnet"|"qwen2.5:7b" 等
})
→ Result<void, string>
```

#### `settings_set_rag_model`
切换 RAG 嵌入模型。

```
invoke("settings_set_rag_model", {
    model_name: string,         // "all-MiniLM-L6-v2"|"bge-small-zh-v1.5" 等
})
→ Result<void, string>
```

#### `settings_get_system_info`
获取应用系统信息。

```
invoke("settings_get_system_info")
→ Result<SystemInfo, string>
```

```typescript
interface SystemInfo {
    data_dir: string;           // 数据存储目录
    db_size_bytes: number;      // LanceDB 存储大小
    vector_count: number;       // 向量总数
    chat_history_count: number; // 对话历史条数
    app_version: string;
    os: string;
}
```

---

## 三、Tauri Event 清单

### 3.1 `market-data`
市场数据实时推送事件。订阅币种后开始接收。

```
frontend.listen("market-data", callback)
```

```typescript
// Payload: MarketUpdate
type MarketUpdate =
    | { type: "Kline"; symbol: string; interval: string; kline: Kline }
    | { type: "OrderBook"; symbol: string; depth: OrderBook }
    | { type: "Ticker"; symbol: string; ticker: Ticker24h };

interface Kline {
    open_time: number;          // Unix ms
    open: number;
    high: number;
    low: number;
    close: number;
    volume: number;
    close_time: number;
    quote_volume: number;
    trades: number;
    taker_buy_volume: number;
    taker_buy_quote_volume: number;
}

interface OrderBookLevel {
    price: number;
    quantity: number;
}

interface OrderBook {
    last_update_id: number;
    bids: OrderBookLevel[];     // 买盘 (价格降序)
    asks: OrderBookLevel[];     // 卖盘 (价格升序)
}

interface Ticker24h {
    symbol: string;
    price_change: number;
    price_change_percent: number;
    last_price: number;
    high_price: number;
    low_price: number;
    volume: number;
    quote_volume: number;
}
```

**推送频率**：合并 500ms 窗口，每个币种每种事件最多每秒 2 次推送。

---

### 3.2 `chat-stream`
AI 对话流式输出事件。`chat_send` 调用后开始接收。

```
frontend.listen("chat-stream", callback)
```

```typescript
// Payload: ChatEvent
type ChatEvent =
    | { type: "TextDelta"; content: string }
    | { type: "ToolStart"; tool_name: string; args: Record<string, any> }
    | { type: "ToolEnd"; tool_name: string; result: any }
    | { type: "AnalysisCard"; data: AnalysisCardData }
    | { type: "Error"; message: string }
    | { type: "Done"; conversation_id: string };

interface AnalysisCardData {
    sentiment: {
        overall: "bullish" | "bearish" | "neutral";
        confidence: number;     // 0-1
        factors: string[];
    };
    technicals: {
        signal: string;
        indicators: Record<string, any>;
    };
    news_summary: {
        key_headlines: string[];
        impact: string;
    };
    risk_warning: string;
}
```

**Token 合并策略**：后端逐 token 发送，前端累积到 >20 字符或 >100ms 后再触发一次渲染。

---

### 3.3 `feed-update`
后端采集到新资讯时推送。

```
frontend.listen("feed-update", callback)
```

```typescript
// Payload: FeedItem[] (结构与 2.3 feed_fetch 返回相同)
```

**推送频率**：采集周期完成后（每 5 分钟）推送一次，包含该批次所有新数据。

---

### 3.4 `connection-status`
网络连接状态变化事件。

```
frontend.listen("connection-status", callback)
```

```typescript
// Payload
interface ConnectionStatus {
    connected: boolean;
    binance_ws: "connected" | "disconnected" | "reconnecting";
    last_heartbeat?: number;    // Unix ms
}
```

---

### 3.5 `error`
全局错误事件（非对话相关的错误）。

```
frontend.listen("error", callback)
```

```typescript
// Payload
interface AppError {
    module: string;             // "binance"|"rag"|"collector"|"system"
    code: string;               // 错误码，供前端映射 i18n
    message: string;            // 用户可读错误信息
    severity: "error" | "warning" | "info";
    timestamp: number;
}
```

---

## 四、公共类型定义

### 4.1 Rust 侧完整枚举

```rust
// src-tauri/src/types.rs

use serde::{Deserialize, Serialize};

/// 统一错误响应（非对话场景）
#[derive(Debug, Clone, Serialize)]
pub struct AppError {
    pub module: String,
    pub code: String,
    pub message: String,
    pub severity: ErrorSeverity,
    pub timestamp: i64,
}

#[derive(Debug, Clone, Serialize)]
pub enum ErrorSeverity {
    Error,
    Warning,
    Info,
}

/// 错误码枚举
#[derive(Debug, Clone, Serialize)]
pub enum ErrorCode {
    // Binance 相关
    BinanceWsDisconnected,
    BinanceRateLimited,
    BinanceInvalidSymbol,

    // RAG 相关
    RagInitFailed,
    RagEmbedFailed,
    RagStoreFailed,
    RagRetrieveFailed,

    // 数据源相关
    SourceNotConfigured,
    SourceRateLimited,
    SourceFetchFailed,

    // LLM 相关
    LlmNotConfigured,
    LlmRateLimited,
    LlmTimeout,
    LlmInvalidResponse,

    // 系统相关
    KeychainReadFailed,
    KeychainWriteFailed,
    DbOpenFailed,
    DbWriteFailed,

    // 通用
    InvalidArgument,
    InternalError,
    NetworkUnavailable,
}

/// 连接状态
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ConnectionStatus {
    pub connected: bool,
    pub binance_ws: WsState,
    pub last_heartbeat: Option<i64>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum WsState {
    Connected,
    Disconnected,
    Reconnecting,
}

/// 对话上下文
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ChatContext {
    pub symbol: String,
    pub available_sources: Vec<String>,
    pub conversation_id: Option<String>,
}

/// 对话消息
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ChatMessage {
    pub id: String,
    pub role: String,           // "user" | "assistant" | "tool"
    pub content: String,
    pub tool_calls: Option<Vec<ToolCallRecord>>,
    pub timestamp: i64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ToolCallRecord {
    pub id: String,
    pub name: String,
    pub args: serde_json::Value,
    pub result: Option<serde_json::Value>,
}

/// API Key 配置状态
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ApiKeyStatus {
    pub provider: String,
    pub configured: bool,
    pub label: String,
    pub required: bool,
}
```

### 4.2 TypeScript 侧完整类型

```typescript
// src/lib/types.ts

// === 市场数据 ===
export interface Kline {
  open_time: number;
  open: number;
  high: number;
  low: number;
  close: number;
  volume: number;
  close_time: number;
  quote_volume: number;
  trades: number;
  taker_buy_volume: number;
  taker_buy_quote_volume: number;
}

export interface OrderBookLevel {
  price: number;
  quantity: number;
}

export interface OrderBook {
  last_update_id: number;
  bids: OrderBookLevel[];
  asks: OrderBookLevel[];
}

export interface Ticker24h {
  symbol: string;
  price_change: number;
  price_change_percent: number;
  last_price: number;
  high_price: number;
  low_price: number;
  volume: number;
  quote_volume: number;
}

export type MarketUpdate =
  | { type: "Kline"; symbol: string; interval: string; kline: Kline }
  | { type: "OrderBook"; symbol: string; depth: OrderBook }
  | { type: "Ticker"; symbol: string; ticker: Ticker24h };

// === 对话 ===
export interface ChatContext {
  symbol: string;
  available_sources: string[];
  conversation_id?: string;
}

export interface ChatMessage {
  id: string;
  role: "user" | "assistant" | "tool";
  content: string;
  tool_calls?: ToolCallRecord[];
  timestamp: number;
}

export interface ToolCallRecord {
  id: string;
  name: string;
  args: Record<string, unknown>;
  result?: unknown;
}

export type ChatEvent =
  | { type: "TextDelta"; content: string }
  | { type: "ToolStart"; tool_name: string; args: Record<string, unknown> }
  | { type: "ToolEnd"; tool_name: string; result: unknown }
  | { type: "AnalysisCard"; data: AnalysisCardData }
  | { type: "Error"; message: string }
  | { type: "Done"; conversation_id: string };

export interface AnalysisCardData {
  sentiment: {
    overall: "bullish" | "bearish" | "neutral";
    confidence: number;
    factors: string[];
  };
  technicals: {
    signal: string;
    indicators: Record<string, unknown>;
  };
  news_summary: {
    key_headlines: string[];
    impact: string;
  };
  risk_warning: string;
}

export interface ConversationSummary {
  id: string;
  title: string;
  created_at: number;
  updated_at: number;
  message_count: number;
}

// === 资讯流 ===
export interface FeedItem {
  id: string;
  source_type: "news" | "tweet" | "onchain";
  source_name: string;
  title: string;
  summary: string;
  content: string;
  url: string;
  published_at: number;
  keywords: string[];
  related_symbol?: string;
}

// === 设置 ===
export interface ApiKeyStatus {
  provider: string;
  configured: boolean;
  label: string;
  required: boolean;
}

export interface SystemInfo {
  data_dir: string;
  db_size_bytes: number;
  vector_count: number;
  chat_history_count: number;
  app_version: string;
  os: string;
}

// === 连接 ===
export interface ConnectionStatus {
  connected: boolean;
  binance_ws: "connected" | "disconnected" | "reconnecting";
  last_heartbeat?: number;
}

export interface AppError {
  module: string;
  code: string;
  message: string;
  severity: "error" | "warning" | "info";
  timestamp: number;
}
```

---

## 五、调用时序示例

### 5.1 应用启动 → 首次使用

```
1. invoke("settings_get_status")         → 检查是否已配置必填 API Key
2. 若未配置 → 显示设置页
3. 用户填写并 invoke("settings_set_api_key", { provider: "openai", key: "sk-..." })
4. invoke("settings_set_api_key", { provider: "binance", key: "abc..." })
5. invoke("settings_get_status")         → 确认必填项已配置
6. 跳转到看板 → invoke("subscribe_symbol", { symbol: "BTCUSDT", intervals: ["1h","4h","1d"] })
7. 开始接收 listen("market-data", ...) 事件
```

### 5.2 用户切换币种

```
1. invoke("unsubscribe_symbol", { symbol: "BTCUSDT" })
2. invoke("subscribe_symbol", { symbol: "ETHUSDT", intervals: ["1h","4h","1d"] })
3. invoke("feed_fetch", { symbol: "ETH" })
4. 前端 Store 更新 → UI 重新渲染
```

### 5.3 用户发送 AI 对话

```
1. 前端先追加 UserMessage 到 useChatStore
2. invoke("chat_send", { message: "...", context: { symbol: "ETHUSDT", ... } })
3. 开始接收 listen("chat-stream", ...) 事件:
   - ToolStart({ tool_name: "search_news", args: {...} })
   - ToolEnd({ tool_name: "search_news", result: [...] })
   - TextDelta({ content: "根据" })
   - TextDelta({ content: "最新" })
   - TextDelta({ content: "新闻..." })
   - ...
   - Done({ conversation_id: "uuid" })
```

### 5.4 后端主动推送

```
后端 ── 采集器触发 ──→ emit("feed-update", [FeedItem, ...])
后端 ── WS 断连 ──→ emit("connection-status", { connected: false, ... })
后端 ── WS 恢复 ──→ emit("connection-status", { connected: true, ... })
后端 ── 非对话错误 ──→ emit("error", { module: "binance", ... })
```
