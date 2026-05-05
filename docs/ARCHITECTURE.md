# 架构设计 (ARCHITECTURE)

## 总体架构

```
┌──────────────────────────────────────────────────────────────────┐
│                        Tauri 2.x Shell (Rust)                    │
│                                                                  │
│  ┌───────────────────────┐          ┌──────────────────────────┐ │
│  │   WebView (React)     │   IPC    │   Rust Backend Logic     │ │
│  │                       │◄────────►│                          │ │
│  │  LeftPanel            │  invoke  │  ┌────────────────────┐  │ │
│  │  ├─ SymbolSelector    │  events  │  │  binance/          │  │ │
│  │  ├─ KLineChart        │          │  │  ├─ ws.rs          │  │ │
│  │  ├─ OrderBook         │          │  │  ├─ rest.rs        │  │ │
│  │  ├─ PriceTicker       │          │  │  └─ types.rs       │  │ │
│  │  └─ NewsFeed          │          │  └────────────────────┘  │ │
│  │                       │          │  ┌────────────────────┐  │ │
│  │  RightPanel           │          │  │  indicators/       │  │ │
│  │  ├─ ChatHistory       │          │  │  ├─ ma.rs          │  │ │
│  │  └─ ChatInput         │          │  │  ├─ macd.rs        │  │ │
│  │                       │          │  │  ├─ rsi.rs         │  │ │
│  │  SettingsPage         │          │  │  └─ bollinger.rs   │  │ │
│  └───────────────────────┘          │  └────────────────────┘  │ │
│                                      │  ┌────────────────────┐  │ │
│                                      │  │  rag/              │  │ │
│                                      │  │  ├─ collector.rs   │  │ │
│                                      │  │  ├─ chunker.rs     │  │ │
│                                      │  │  ├─ embedder.rs    │  │ │
│                                      │  │  ├─ store.rs       │  │ │
│                                      │  │  └─ retriever.rs   │  │ │
│                                      │  └────────────────────┘  │ │
│                                      │  ┌────────────────────┐  │ │
│                                      │  │  agent/            │  │ │
│                                      │  │  ├─ loop.rs        │  │ │
│                                      │  │  ├─ tools.rs       │  │ │
│                                      │  │  └─ prompt.rs      │  │ │
│                                      │  └────────────────────┘  │ │
│                                      │  ┌────────────────────┐  │ │
│                                      │  │  data_sources/     │  │ │
│                                      │  │  ├─ news.rs        │  │ │
│                                      │  │  ├─ twitter.rs     │  │ │
│                                      │  │  └─ onchain.rs     │  │ │
│                                      │  └────────────────────┘  │ │
│                                      │  ┌────────────────────┐  │ │
│                                      │  │  commands/         │  │ │
│                                      │  │  └─ mod.rs         │  │ │
│                                      │  └────────────────────┘  │ │
│                                      └──────────────────────────┘ │
└──────────────────────────────────────────────────────────────────┘
```

## 分层架构

### 第 1 层：UI 层 (React)

**职责**：纯展示 + 用户交互，不包含业务逻辑

| 组件 | 职责 | 依赖 Store |
|------|------|-----------|
| `SymbolSelector` | 币种切换 | `useSymbolStore` |
| `KLineChart` | K 线图渲染、指标叠加显示 | `useMarketStore` |
| `OrderBook` | 订单簿买卖盘口 | `useMarketStore` |
| `PriceTicker` | 实时价格条 | `useMarketStore` |
| `NewsFeed` | 资讯流展示、来源筛选 | `useFeedStore` |
| `ChatPanel` | AI 对话容器 | `useChatStore` |
| `ChatHistory` | 消息列表渲染 | `useChatStore` |
| `ChatInput` | 用户输入 + 发送 | `useChatStore` |
| `SettingsPage` | API Key 配置 | `useSettingsStore` |

**数据获取**：
- 市场数据：通过 Tauri Event 系统接收后端推送（`listen('market-data', callback)`）
- 聊天：通过 `invoke('chat.send', { message })` 发起，通过 Events 接收流式响应
- 资讯流：通过 `invoke('feed.fetch', { symbol })` 拉取

### 第 2 层：状态管理层 (Zustand Stores)

**职责**：连接 UI 和 Tauri 后端，管理客户端状态

```
useSymbolStore   ─── 当前选中币种 ───→ 影响所有数据订阅
useMarketStore   ─── K线/深度/价格 ───→ 从后端 Events 填充
useFeedStore     ─── 资讯流列表   ───→ 从后端 invoke 拉取
useChatStore     ─── 对话历史     ───→ 管理消息列表 + 流式更新
useSettingsStore ─── API Key 配置 ───→ 读写 OS Keychain
```

### 第 3 层：Tauri IPC 桥接层 (commands/)

**职责**：将前端 `invoke` 调用路由到 Rust 后端模块

```rust
// 所有 Tauri command 在此定义
#[tauri::command]
async fn chat_send(app: AppHandle, message: String, context: ChatContext) -> Result<(), String>
#[tauri::command]
async fn feed_fetch(app: AppHandle, symbol: String) -> Result<Vec<FeedItem>, String>
#[tauri::command]
async fn get_klines(app: AppHandle, symbol: String, interval: String) -> Result<Vec<Kline>, String>
#[tauri::command]
async fn settings_set_api_key(provider: String, key: String) -> Result<(), String>
```

### 第 4 层：Rust 业务逻辑层

**职责**：所有后台计算、数据采集、AI 交互

#### 4a. Binance 模块 (`binance/`)

```
binance/
├── mod.rs          # 模块入口，BinanceClient 结构体
├── ws.rs           # WebSocket 连接管理 (多流合并)
├── rest.rs         # REST API 封装
└── types.rs        # 数据类型定义 (Kline, OrderBook, Ticker)
```

**设计要点**：
- 使用 `binance-sdk` 的 REST 模块获取历史数据
- WebSocket 层自实现（因 `binance-sdk` WS 有已知稳定性问题）
- 多流合并：`btcusdt@kline_1h/ethusdt@kline_1h/...` → 单连接
- 断线自动重连 + 数据补全

#### 4b. 技术指标模块 (`indicators/`)

```
indicators/
├── mod.rs          # 统一接口 trait
├── ma.rs           # SMA/EMA (使用 kand)
├── macd.rs         # MACD (使用 kand)
├── rsi.rs          # RSI (使用 kand)
└── bollinger.rs    # 布林带 (使用 kand)
```

**设计要点**：
- 使用 `kand` crate 的 O(1) 增量计算
- 计算结果通过 Tauri Events 推送给前端
- 支持多周期：1m/5m/15m/1h/4h/1d

#### 4c. RAG 模块 (`rag/`)

```
rag/
├── mod.rs          # 模块入口，RagEngine 结构体
├── collector.rs    # 定时数据采集 (新闻/推文/链上)
├── chunker.rs      # 文本分块
├── embedder.rs     # 向量嵌入 (fastembed)
├── store.rs        # 向量存储 (lancedb)
└── retriever.rs    # 语义检索
```

**设计要点**：
- `collector`: 每 5 分钟从 NewsAPI/Twitter/链上拉取新数据
- `chunker`: 递归字符分割，chunk_size=512, overlap=50
- `embedder`: fastembed 本地 ONNX 模型，无需 GPU
- `store`: LanceDB 嵌入式存储，数据存于 `$APP_DATA/lancedb/`
- `retriever`: 向量搜索 + 全文搜索混合，top_k=20

#### 4d. Agent 模块 (`agent/`)

```
agent/
├── mod.rs          # Agent 结构体 + execute 入口
├── loop.rs         # ReAct Agent 循环逻辑
├── tools.rs        # 工具注册与执行
└── prompt.rs       # System Prompt 构建
```

**设计要点**：
- ReAct 模式：Thought → Action → Observation → ... → Final Answer
- 使用 `genai` crate 的多提供商统一接口
- 流式输出通过 Tauri Events 逐 token 推向前端
- 工具调用可视化：前端显示工具名称 + 参数 + 结果摘要

#### 4e. 数据源模块 (`data_sources/`)

```
data_sources/
├── mod.rs          # 统一 DataSource trait
├── news.rs         # NewsAPI / GNews 封装
├── twitter.rs      # Twitter API v2 封装
└── onchain.rs      # Whale Alert / Etherscan 封装
```

**设计要点**：
- 统一 `DataSource` trait：`async fn fetch(query) -> Vec<RawNewsItem>`
- 各实现独立，可单独启用/禁用
- 用户在每个源的设置页配置 API Key

### 第 5 层：外部服务

```
┌─────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐
│ Binance │  │ NewsAPI  │  │ Twitter  │  │ Onchain  │  │ LLM API  │
│  REST+WS│  │ REST     │  │ REST     │  │ REST     │  │ REST+SSE │
└────┬────┘  └────┬─────┘  └────┬─────┘  └────┬─────┘  └────┬─────┘
     │            │             │             │             │
     └────────────┴─────────────┴─────────────┴─────────────┘
                         ▲
                         │
                  Rust Backend
```

## 线程模型

```
┌─────────────────────────────────────────────────────┐
│                 tokio Runtime (multi-thread)         │
│                                                     │
│  task: binance_ws     ← Binance WebSocket 长连接     │
│  task: collector      ← 定时数据采集 (5min tick)      │
│  task: chat_agent     ← Agent 循环 (每个对话一个)     │
│  task: embedder       ← 嵌入计算 (CPU密集, spawn_blocking) │
│  task: indicator_calc ← 指标计算 (按需)              │
│                                                     │
│  Tauri Main Thread    ← handle IPC, UI events        │
└─────────────────────────────────────────────────────┘
```

- `binance_ws` 和 `collector` 是常驻任务，应用启动即运行
- `chat_agent` 每次对话创建一个新 task（支持多对话并发）
- `embedder` 使用 `spawn_blocking` 避免阻塞异步线程
- 所有 Tauri IPC 在主线程处理，不阻塞 UI

## 状态管理

### 全局状态 (Tauri State)

```rust
// 应用级别的共享状态，通过 Tauri 的 manage() 注入
pub struct AppState {
    pub binance: Arc<BinanceClient>,      // Binance 客户端
    pub rag: Arc<RagEngine>,              // RAG 引擎
    pub data_sources: Arc<DataSourceHub>, // 数据源集合
    pub keychain: Arc<KeychainManager>,   // 密钥管理
    pub event_bus: Arc<EventBus>,         // 内部事件总线
}
```

### 前端状态 (Zustand)

```typescript
// 见 DATA_FLOW.md 中的完整定义
```

## 通信协议

### Tauri IPC Commands (invoke)

前端调用后端的请求-响应模式：
```
invoke('command_name', { args }) → Result<T, String>
```

### Tauri Events (listen)

后端推向前端的流式数据：
```
listen('event_name', callback) → 实时数据流
```

| Event | Payload | 触发时机 |
|-------|---------|---------|
| `market-data` | `MarketUpdate { symbol, data }` | Binance WS 新数据 |
| `chat-stream` | `ChatEvent { type, content }` | Agent 流式输出 |
| `feed-update` | `Vec<FeedItem>` | 采集器新数据 |
| `error` | `AppError { module, message }` | 任何后端错误 |
