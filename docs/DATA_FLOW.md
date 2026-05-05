# 数据流设计 (DATA_FLOW)

## 1. 整体数据流

```
                        ┌─────────────────────────┐
                        │     Binance 交易所       │
                        │  REST API  │  WebSocket  │
                        └──────┬─────┴──────┬──────┘
                               │            │
                    REST (按需) │            │ WS (实时推送)
                               │            │
                        ┌──────▼────────────▼──────┐
                        │    Rust Backend (Tauri)   │
                        │                           │
                        │  ┌─────────────────────┐  │
                        │  │  BinanceClient       │  │
                        │  │  - rest: 历史数据    │  │
                        │  │  - ws: 实时数据流    │  │
                        │  └────────┬────────────┘  │
                        │           │                │
                        │  ┌────────▼────────────┐  │
                        │  │  Event Bus (broadcast)│  │
                        │  │  Channel<MarketUpdate> │  │
                        │  └────────┬────────────┘  │
                        │           │                │
                        │  ┌────────▼────────────┐  │
                        │  │  Tauri IPC bridge    │  │
                        │  │  app.emit("market-   │  │
                        │  │           data", ..) │  │
                        │  └────────┬────────────┘  │
                        └───────────┼───────────────┘
                                    │
                            Events (push)
                                    │
                        ┌───────────▼───────────────┐
                        │    React Frontend (WebView) │
                        │                             │
                        │  ┌─────────────────────────┐│
                        │  │  useBinanceWs Hook       ││
                        │  │  listen("market-data",..) ││
                        │  └──────────┬──────────────┘│
                        │             │                │
                        │  ┌──────────▼──────────────┐│
                        │  │  useMarketStore (Zustand) ││
                        │  │  klineData / orderBook   ││
                        │  │  / ticker                ││
                        │  └──────┬──────────┬───────┘│
                        │         │          │         │
                        │  ┌──────▼──┐ ┌─────▼──────┐ │
                        │  │KLineChart│ │ OrderBook  │ │
                        │  └─────────┘ └────────────┘ │
                        └─────────────────────────────┘
```

---

## 2. 市场数据流 (详细)

### 2.1 币种切换 → 数据重新订阅

```
User clicks [ETH] in SymbolSelector
    │
    ├─→ useSymbolStore.setSymbol("ETHUSDT")
    │       │
    │       ├─→ useEffect: invoke("subscribe_symbol", { symbol: "ETHUSDT" })
    │       │       │
    │       │       └─→ Rust: BinanceClient.subscribe("ethusdt", ["1h","4h","1d"])
    │       │               │
    │       │               ├─→ REST: 拉取历史 K 线 (最近 500 根)
    │       │               │     └─→ emit("market-data", Kline { batch })
    │       │               │
    │       │               └─→ WS: 订阅实时流
    │       │                     ├─ ethusdt@kline_1h
    │       │                     ├─ ethusdt@kline_4h
    │       │                     ├─ ethusdt@kline_1d
    │       │                     ├─ ethusdt@depth20@100ms
    │       │                     └─ ethusdt@ticker
    │       │
    │       └─→ 取消之前 btcusdt 的所有 WS 订阅
    │
    └─→ useFeedStore.fetchFeed("ETH")
            │
            └─→ invoke("feed_fetch", { symbol: "ETH" })
                    │
                    └─→ Rust: RagEngine.retrieve("ETH", ..)
                            └─→ 返回 最近 50 条 ETH 相关资讯
```

### 2.2 K 线实时更新流程

```
Binance WS                      Rust Backend                  React Frontend
    │                               │                              │
    │  {stream: "ethusdt@kline_1h", │                              │
    │   data: {k: {o,h,l,c,v,...}}}│                              │
    │──────────────────────────────>│                              │
    │                               │                              │
    │                        ws.rs: parse_message()                │
    │                               │                              │
    │                        MarketUpdate::Kline {                 │
    │                          symbol, interval, kline             │
    │                        }                                     │
    │                               │                              │
    │                        event_bus.send(update)                │
    │                               │                              │
    │                        emit("market-data", update)           │
    │                               │─────────────────────────────>│
    │                               │                              │
    │                               │         useBinanceWs listens │
    │                               │         useMarketStore.set   │
    │                               │         KlineData(interval,  │
    │                               │           kline)             │
    │                               │                              │
    │                               │         KLineChart re-render │
    │                               │         (增量更新, 非全量)    │
```

### 2.3 订单簿增量更新

```
Binance WS (depth20@100ms)       Rust Backend              React Frontend
    │                               │                          │
    │  {bids: [[p,q],...],          │                          │
    │   asks: [[p,q],...],          │                          │
    │   lastUpdateId: 123456}       │                          │
    │──────────────────────────────>│                          │
    │                               │                          │
    │                        OrderBook {                       │
    │                          last_update_id,                 │
    │                          bids: [{price, qty}],           │
    │                          asks: [{price, qty}],           │
    │                        }                                 │
    │                               │                          │
    │                               │  emit("market-data")     │
    │                               │─────────────────────────>│
    │                               │                          │
    │                               │     useMarketStore       │
    │                               │     .updateOrderBook()   │
    │                               │                          │
    │                               │     OrderBook re-render  │
    │                               │     (replace, not merge) │
```

---

## 3. AI 对话数据流

### 3.1 发送消息 → 流式响应

```
User types: "分析 ETH 最近有什么大新闻，技术面如何？"
    │
    ▼
ChatInput onSubmit(message)
    │
    ├─→ useChatStore.addMessage({ role: "user", content: message })
    │
    └─→ invoke("chat_send", {
            message,
            context: { symbol: "ETHUSDT", availableSources: [...] }
        })
            │
            ▼
Rust commands::chat_send()
    │
    ├─→ 创建 Agent 实例
    ├─→ 创建 mpsc channel (event_tx / event_rx)
    │
    ├─→ tokio::spawn(async {
    │       agent.execute(message, context, event_tx)
    │   })
    │
    └─→ tokio::spawn(async {
            while let Some(event) = event_rx.recv().await {
                app.emit("chat-stream", event)  ← 逐事件推前端
            }
        })

---
Agent 内部循环:
---

System: "你是 CryptoQuant AI 助手..."
User: "分析 ETH 最近有什么大新闻，技术面如何？"

→ LLM 思考 → decision: call tool "search_news"
    │
    ├─→ emit: AgentEvent::ToolStart { tool: "search_news", args: { keyword: "ETH", days: 3 } }
    │
    ├─→ RagEngine::retrieve("ETH", Some(News), None, 20)
    │      └─→ 返回 [{"title": "ETH ETF...", "content": "...", ...}, ...]
    │
    └─→ emit: AgentEvent::ToolEnd { tool: "search_news", result: [...] }

→ LLM 思考 → decision: call tool "analyze_technicals"
    │
    ├─→ emit: ToolStart { tool: "analyze_technicals", args: { symbol: "ETHUSDT", interval: "4h" } }
    │
    ├─→ compute_indicators(klines) → { macd: {...}, rsi: {...}, ema: {...} }
    │
    └─→ emit: ToolEnd { tool: "analyze_technicals", result: {...} }

→ LLM 综合信息 → 生成最终回答
    │
    ├─→ emit: TextDelta { content: "根据" }
    ├─→ emit: TextDelta { content: "最新" }
    ├─→ emit: TextDelta { content: "资讯" }
    ├─→ ... (逐 token)
    │
    └─→ emit: Done

---

前端接收 chat-stream events:
---

listen("chat-stream", (event: AgentEvent) => {
    switch (event.type) {
        case "TextDelta":
            useChatStore.appendToLastMessage(event.content)
            break
        case "ToolStart":
            useChatStore.addToolCall({ name: event.tool_name, status: "running" })
            break
        case "ToolEnd":
            useChatStore.completeToolCall(event.tool_name, event.result)
            break
        case "Done":
            useChatStore.setStreaming(false)
            break
    }
})
```

---

## 4. RAG 数据流

### 4.1 采集管道

```
定时器 (每 5 分钟)
    │
    ├─→ DataSourceHub::fetch_all(["BTC", "ETH", "BNB", "SOL", "XRP", "DOGE"])
    │       │
    │       ├─→ NewsApiSource::fetch("BTC cryptocurrency", 20)
    │       ├─→ NewsApiSource::fetch("ETH cryptocurrency", 20)
    │       ├─→ TwitterSource::fetch("BTC OR ETH OR SOL", 20)
    │       ├─→ OnchainSource::fetch_whale_transfers("BTC", 10)
    │       └─→ OnchainSource::fetch_exchange_flow("ETH", 10)
    │
    └─→ 每批数据:
            │
            ├─→ 去重 (URL level, 本地 LRU cache)
            ├─→ 按语言/相关度 过滤噪音
            │
            ├─→ Chunker: 递归字符分割 (512 chars, 50 overlap)
            ├─→ Embedder: fastembed 向量化 (384 dims)
            └─→ LanceDB: 批量写入 (news_table / tweets_table / onchain_table)
```

### 4.2 检索管道

```
用户查询: "ETH ETF 进展如何？"
    │
    ├─→ Embedder: 查询向量化 (1 个向量)
    │
    ├─→ LanceDB 并行搜索:
    │       ├─ news_table:    vector_search(limit=10) + fulltext_search("ETH ETF", limit=10)
    │       ├─ tweets_table:  vector_search(limit=5)  + fulltext_search("ETH ETF", limit=5)
    │       └─ onchain_table: vector_search(limit=5)
    │
    ├─→ 合并结果 → 去重 → 按相似度排序 → 截断 top_k=20
    │
    └─→ 返回 RagDocument[] → 注入 LLM Context
```

---

## 5. 前端状态流

### 5.1 Zustand Store 依赖关系

```
useSettingsStore (API Keys)
        │
        ├──→ useSymbolStore (当前币种)
        │       │
        │       ├──→ useMarketStore (K线/深度/价格)
        │       │       ├──→ KLineChart
        │       │       └──→ OrderBook
        │       │
        │       ├──→ useFeedStore (资讯流)
        │       │       └──→ NewsFeed
        │       │
        │       └──→ useChatStore (对话)
        │               ├──→ ChatHistory
        │               └──→ ChatInput
        │
        └──→ (控制哪些数据源/LLM 可用)
```

### 5.2 Store 接口定义

```typescript
// useSymbolStore
interface SymbolState {
  selectedSymbol: string        // 'BTCUSDT'
  availableSymbols: string[]
  setSymbol: (s: string) => void
}

// useMarketStore
interface MarketState {
  klineData: Record<string, Candle[]>  // key: "1h", "4h", "1d"
  orderBook: { bids: Level[]; asks: Level[] }
  ticker: Ticker24h | null
  setKlineData: (interval: string, kline: Candle) => void
  setKlineBatch: (interval: string, klines: Candle[]) => void
  updateOrderBook: (depth: OrderBook) => void
  updateTicker: (ticker: Ticker24h) => void
}

// useFeedStore
interface FeedState {
  items: FeedItem[]
  loading: boolean
  filter: 'all' | 'news' | 'tweet' | 'onchain'
  fetchFeed: (symbol: string) => Promise<void>
  setFilter: (f: string) => void
}

// useChatStore
interface ChatState {
  messages: ChatMessage[]
  isStreaming: boolean
  currentToolCalls: Map<string, ToolCallStatus>
  sendMessage: (text: string) => Promise<void>
  appendToLastMessage: (text: string) => void
  addToolCall: (call: ToolCallStatus) => void
  completeToolCall: (name: string, result: any) => void
  clearHistory: () => void
}

// useSettingsStore
interface SettingsState {
  providers: Record<string, ApiKeyStatus>
  llmProvider: 'openai' | 'anthropic' | 'ollama'
  llmModel: string
  setApiKey: (provider: string, key: string) => Promise<void>
  deleteApiKey: (provider: string) => Promise<void>
  setLlmProvider: (p: string) => void
  setLlmModel: (m: string) => void
}
```
