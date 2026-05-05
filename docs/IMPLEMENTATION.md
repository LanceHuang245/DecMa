# 模块实现细节 (IMPLEMENTATION)

## 1. Tauri 入口与状态初始化

### main.rs

```rust
// src-tauri/src/main.rs
mod binance;
mod indicators;
mod rag;
mod agent;
mod data_sources;
mod commands;

use std::sync::Arc;
use binance::BinanceClient;
use rag::RagEngine;
use data_sources::DataSourceHub;

#[derive(Clone)]
pub struct AppState {
    pub binance: Arc<BinanceClient>,
    pub rag: Arc<RagEngine>,
    pub data_sources: Arc<DataSourceHub>,
}

#[tokio::main]
async fn main() {
    // 初始化日志
    tracing_subscriber::fmt::init();

    // 初始化应用状态
    let state = AppState {
        binance: Arc::new(BinanceClient::new()),
        rag: Arc::new(RagEngine::new().await.expect("Failed to init RAG")),
        data_sources: Arc::new(DataSourceHub::new()),
    };

    // 启动后台任务
    let binance_handle = tokio::spawn(state.binance.clone().run_ws_loop());
    let collector_handle = tokio::spawn(state.rag.clone().run_collector());

    tauri::Builder::default()
        .manage(state)
        .manage(binance_handle)
        .manage(collector_handle)
        .invoke_handler(tauri::generate_handler![
            commands::get_klines,
            commands::get_order_book,
            commands::chat_send,
            commands::chat_cancel,
            commands::feed_fetch,
            commands::feed_filter,
            commands::settings_get_api_keys,
            commands::settings_set_api_key,
            commands::settings_delete_api_key,
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
```

### 应用生命周期

```
app.start()
  ├── RagEngine::new()          ← 初始化 embedding 模型 + lancedb
  ├── BinanceClient::new()      ← 初始化 REST 客户端
  ├── DataSourceHub::new()      ← 初始化数据源 (按配置延迟初始化)
  ├── spawn binance_ws_loop()   ← 后台 WebSocket 长连接
  ├── spawn rag_collector()     ← 后台定时采集
  └── tauri::Builder::run()     ← 启动 Tauri 窗口

app.close()
  ├── binance_ws.close()        ← 优雅关闭 WS
  ├── collector.stop()          ← 停止定时任务
  ├── lancedb.flush()           ← 持久化向量数据
  └── process.exit()
```

---

## 2. Binance 模块

### 2.1 数据结构 (types.rs)

```rust
// src-tauri/src/binance/types.rs
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Kline {
    pub open_time: i64,         // 开盘时间 (Unix ms)
    pub open: f64,
    pub high: f64,
    pub low: f64,
    pub close: f64,
    pub volume: f64,            // 成交量
    pub close_time: i64,        // 收盘时间
    pub quote_volume: f64,      // 成交额
    pub trades: i64,            // 成交笔数
    pub taker_buy_volume: f64,  // 主动买入成交量
    pub taker_buy_quote_volume: f64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct OrderBookLevel {
    pub price: f64,
    pub quantity: f64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct OrderBook {
    pub last_update_id: i64,
    pub bids: Vec<OrderBookLevel>,   // 买盘 (降序)
    pub asks: Vec<OrderBookLevel>,   // 卖盘 (升序)
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Ticker24h {
    pub symbol: String,
    pub price_change: f64,       // 24h 价格变化
    pub price_change_percent: f64, // 24h 涨跌幅 %
    pub last_price: f64,         // 最新价
    pub high_price: f64,         // 24h 最高价
    pub low_price: f64,          // 24h 最低价
    pub volume: f64,             // 24h 成交量
    pub quote_volume: f64,       // 24h 成交额
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type")]
pub enum MarketUpdate {
    Kline { symbol: String, interval: String, kline: Kline },
    OrderBook { symbol: String, depth: OrderBook },
    Ticker { symbol: String, ticker: Ticker24h },
}
```

### 2.2 REST 客户端 (rest.rs)

```rust
// src-tauri/src/binance/rest.rs
use binance_sdk::spot::market::Market;
use super::types::*;

pub struct BinanceRestClient {
    market: Market,
}

impl BinanceRestClient {
    pub fn new() -> Self {
        Self {
            market: Market::new(),
        }
    }

    /// 获取 K 线历史数据
    pub async fn get_klines(
        &self,
        symbol: &str,
        interval: &str,
        limit: u16,
    ) -> Result<Vec<Kline>, anyhow::Error> {
        let response = self.market
            .get_klines(symbol, interval)
            .limit(limit)
            .send()
            .await?;

        Ok(response.into_iter().map(Kline::from).collect())
    }

    /// 获取订单簿深度 (默认 20 档)
    pub async fn get_order_book(
        &self,
        symbol: &str,
    ) -> Result<OrderBook, anyhow::Error> {
        let depth = self.market
            .get_depth(symbol)
            .limit(20)
            .send()
            .await?;

        Ok(OrderBook::from(depth))
    }

    /// 获取 24h 行情
    pub async fn get_ticker_24h(
        &self,
        symbol: &str,
    ) -> Result<Ticker24h, anyhow::Error> {
        let ticker = self.market
            .get_24hr_ticker(symbol)
            .send()
            .await?;

        Ok(Ticker24h::from(ticker))
    }
}
```

### 2.3 WebSocket 流管理 (ws.rs)

```rust
// src-tauri/src/binance/ws.rs
use tokio_tungstenite::connect_async;
use futures_util::StreamExt;
use tokio::sync::broadcast;

const BINANCE_WS_URL: &str = "wss://stream.binance.com:9443/stream";

pub struct BinanceWsClient {
    subscriptions: Arc<DashMap<String, Subscription>>,
    tx: broadcast::Sender<MarketUpdate>,
    reconnect_delay: Duration,
}

#[derive(Clone)]
struct Subscription {
    symbol: String,
    streams: Vec<String>,  // e.g., ["btcusdt@kline_1h", "btcusdt@depth20@100ms"]
}

impl BinanceWsClient {
    pub fn new(tx: broadcast::Sender<MarketUpdate>) -> Self {
        Self {
            subscriptions: Arc::new(DashMap::new()),
            tx,
            reconnect_delay: Duration::from_secs(1),
        }
    }

    /// 订阅币种的市场数据
    pub async fn subscribe(&self, symbol: &str, intervals: &[&str]) {
        let mut streams = vec![
            format!("{}@depth20@100ms", symbol.to_lowercase()),
            format!("{}@ticker", symbol.to_lowercase()),
        ];
        for interval in intervals {
            streams.push(format!("{}@kline_{}", symbol.to_lowercase(), interval));
        }

        self.subscriptions.insert(symbol.to_string(), Subscription {
            symbol: symbol.to_string(),
            streams: streams.clone(),
        });

        // 如果当前连接存在，发送新的订阅请求
        // 实际实现需要管理连接生命周期
    }

    /// 解析 WebSocket 消息并分发
    fn parse_message(&self, raw: &str) -> Option<MarketUpdate> {
        // 根据 stream 字段路由到对应解析器
        let value: serde_json::Value = serde_json::from_str(raw).ok()?;
        let stream = value["stream"].as_str()?;

        if stream.contains("@kline_") {
            // 解析 K 线更新
            let interval = extract_interval(stream);
            let kline = parse_kline_data(&value["data"]["k"])?;
            Some(MarketUpdate::Kline {
                symbol: extract_symbol(stream),
                interval,
                kline,
            })
        } else if stream.contains("@depth") {
            // 解析深度更新
            Some(MarketUpdate::OrderBook {
                symbol: extract_symbol(stream),
                depth: parse_depth_data(&value["data"])?,
            })
        } else if stream.contains("@ticker") {
            // 解析行情更新
            Some(MarketUpdate::Ticker {
                symbol: extract_symbol(stream),
                ticker: parse_ticker_data(&value["data"])?,
            })
        } else {
            None
        }
    }

    /// 重连循环（指数退避）
    async fn run_ws_loop(&self) {
        loop {
            match self.connect_and_listen().await {
                Ok(()) => {
                    tracing::info!("WebSocket connection closed normally");
                }
                Err(e) => {
                    tracing::error!("WebSocket error: {}, reconnecting in {:?}", e, self.reconnect_delay);
                    tokio::time::sleep(self.reconnect_delay).await;
                    // 指数退避，最大 60 秒
                    // self.reconnect_delay = min(self.reconnect_delay * 2, Duration::from_secs(60));
                }
            }
        }
    }
}
```

---

## 3. 技术指标模块

### 3.1 统一接口 (mod.rs)

```rust
// src-tauri/src/indicators/mod.rs
use serde::Serialize;

#[derive(Debug, Clone, Serialize)]
pub struct IndicatorResult {
    pub name: String,
    pub values: Vec<IndicatorPoint>,
}

#[derive(Debug, Clone, Serialize)]
pub struct IndicatorPoint {
    pub time: i64,       // Unix ms
    pub value: f64,      // 主线值
    pub signal: Option<f64>, // 信号线 (MACD)
    pub histogram: Option<f64>, // 柱状图 (MACD)
    pub upper: Option<f64>, // 上轨 (Bollinger)
    pub lower: Option<f64>, // 下轨 (Bollinger)
}

/// 指标计算器统一 trait
pub trait Indicator {
    fn name(&self) -> &str;
    fn compute(&self, klines: &[Kline]) -> IndicatorResult;
}
```

### 3.2 使用 kand 实现 EMA

```rust
// src-tauri/src/indicators/ma.rs
use kand::ohlcv::ema;
use super::*;

pub struct EmaIndicator {
    period: usize,
}

impl Indicator for EmaIndicator {
    fn name(&self) -> &str {
        "EMA"
    }

    fn compute(&self, klines: &[Kline]) -> IndicatorResult {
        let close_prices: Vec<f64> = klines.iter().map(|k| k.close).collect();
        let mut output = vec![0.0; klines.len()];

        // kand 的 O(1) 增量 EMA 计算
        let mut prev = close_prices[0];
        for (i, &price) in close_prices.iter().enumerate() {
            output[i] = ema::ema(price, prev, self.period);
            prev = output[i];
        }

        IndicatorResult {
            name: format!("EMA{}", self.period),
            values: klines.iter().enumerate().map(|(i, k)| IndicatorPoint {
                time: k.open_time,
                value: output[i],
                signal: None,
                histogram: None,
                upper: None,
                lower: None,
            }).collect(),
        }
    }
}
```

### 3.3 指标计算管线

```rust
// 批量计算多指标，并发执行
pub async fn compute_indicators(klines: &[Kline]) -> Vec<IndicatorResult> {
    let klines = Arc::new(klines.to_vec());
    let indicators: Vec<Box<dyn Indicator + Send + Sync>> = vec![
        Box::new(EmaIndicator::new(7)),
        Box::new(EmaIndicator::new(25)),
        Box::new(EmaIndicator::new(99)),
        Box::new(MacdIndicator::new(12, 26, 9)),
        Box::new(RsiIndicator::new(14)),
        Box::new(BollingerIndicator::new(20, 2.0)),
    ];

    let mut handles = vec![];
    for indicator in indicators {
        let k = klines.clone();
        handles.push(tokio::task::spawn_blocking(move || {
            indicator.compute(&k)
        }));
    }

    let mut results = vec![];
    for handle in handles {
        if let Ok(result) = handle.await {
            results.push(result);
        }
    }
    results
}
```

---

## 4. RAG 模块

### 4.1 引擎结构 (mod.rs)

```rust
// src-tauri/src/rag/mod.rs
use lancedb::{Connection, Table};
use fastembed::TextEmbedding;
use std::path::PathBuf;

pub struct RagEngine {
    embedder: TextEmbedding,
    db: Connection,
    news_table: Table,
    tweets_table: Table,
    onchain_table: Table,
    config: RagConfig,
}

#[derive(Clone)]
pub struct RagConfig {
    pub data_dir: PathBuf,
    pub chunk_size: usize,        // 512
    pub chunk_overlap: usize,     // 50
    pub top_k: usize,             // 20
    pub collection_interval_secs: u64,  // 300 (= 5min)
    pub max_items_per_source: usize,    // 1000
}

impl RagEngine {
    pub async fn new() -> Result<Self, anyhow::Error> {
        let config = RagConfig::default();

        // 初始化本地嵌入模型
        let embedder = TextEmbedding::try_new(
            fastembed::InitOptions::new()
                .with_model_name("all-MiniLM-L6-v2")
                .with_cache_dir(config.data_dir.join("models"))
        )?;

        // 初始化 LanceDB (嵌入式)
        let db = lancedb::connect(config.data_dir.join("lancedb")).await?;

        // 创建/打开表
        let news_table = Self::ensure_table(&db, "news", 384).await?;
        let tweets_table = Self::ensure_table(&db, "tweets", 384).await?;
        let onchain_table = Self::ensure_table(&db, "onchain", 384).await?;

        Ok(Self { embedder, db, news_table, tweets_table, onchain_table, config })
    }

    /// 检索相关文档
    pub async fn retrieve(
        &self,
        query: &str,
        source: Option<SourceType>,
        keyword: Option<&str>,
        limit: usize,
    ) -> Result<Vec<RagDocument>, anyhow::Error> {
        // 1. 生成查询向量
        let query_embedding = self.embedder.embed(vec![query])?
            .into_iter().next()
            .ok_or(anyhow::anyhow!("Failed to generate embedding"))?;

        // 2. 向量搜索
        let mut docs = Vec::new();

        if source.is_none() || source == Some(SourceType::News) {
            docs.extend(self.retrieve_from_table(&self.news_table, &query_embedding, keyword, limit).await?);
        }
        if source.is_none() || source == Some(SourceType::Tweet) {
            docs.extend(self.retrieve_from_table(&self.tweets_table, &query_embedding, keyword, limit).await?);
        }
        if source.is_none() || source == Some(SourceType::Onchain) {
            docs.extend(self.retrieve_from_table(&self.onchain_table, &query_embedding, keyword, limit).await?);
        }

        // 3. 按相似度排序 & 去重
        docs.sort_by(|a, b| b.score.partial_cmp(&a.score).unwrap());
        docs.dedup_by_key(|d| d.content.clone());
        docs.truncate(limit);

        Ok(docs)
    }
}
```

### 4.2 采集器 (collector.rs)

```rust
// src-tauri/src/rag/collector.rs
impl RagEngine {
    pub async fn run_collector(self: Arc<Self>) {
        let mut interval = tokio::time::interval(
            Duration::from_secs(self.config.collection_interval_secs)
        );

        loop {
            interval.tick().await;
            tracing::debug!("Running RAG collection cycle");

            // 并发采集各数据源
            let (news, tweets, onchain) = tokio::join!(
                self.collect_news(),
                self.collect_tweets(),
                self.collect_onchain(),
            );

            // 处理并存入向量库
            if let Ok(items) = news {
                if !items.is_empty() {
                    let _ = self.ingest_news(items).await;
                }
            }
            if let Ok(items) = tweets {
                if !items.is_empty() {
                    let _ = self.ingest_tweets(items).await;
                }
            }
            if let Ok(items) = onchain {
                if !items.is_empty() {
                    let _ = self.ingest_onchain(items).await;
                }
            }
        }
    }

    async fn ingest_news(&self, items: Vec<RawNewsItem>) -> Result<(), anyhow::Error> {
        for item in items {
            // 1. 文本分块
            let chunks = self.chunker.split(&item.content);

            // 2. 向量嵌入
            let texts: Vec<&str> = chunks.iter().map(|c| c.as_str()).collect();
            let embeddings = self.embedder.embed(texts)?;

            // 3. 存入 LanceDB
            for (chunk, embedding) in chunks.into_iter().zip(embeddings) {
                self.news_table.add(vec![NewsRecord {
                    id: uuid::Uuid::new_v4().to_string(),
                    source_url: item.url.clone(),
                    title: item.title.clone(),
                    content: chunk,
                    embedding,
                    published_at: item.published_at,
                    keywords: item.keywords.clone(),
                    symbol: item.related_symbol.clone(),
                }]).await?;
            }
        }
        Ok(())
    }
}
```

### 4.3 检索器 (retriever.rs)

```rust
impl RagEngine {
    async fn retrieve_from_table(
        &self,
        table: &Table,
        query_embedding: &[f32],
        keyword: Option<&str>,
        limit: usize,
    ) -> Result<Vec<RagDocument>, anyhow::Error> {
        // 构建 LanceDB 查询
        let mut query = table
            .query()
            .nearest_to(query_embedding)?
            .limit(limit as u32);

        // 如果有关键词过滤，添加全文搜索条件
        if let Some(kw) = keyword {
            query = query.where_contains("content", kw)?;
        }

        let results = query.execute().await?;

        Ok(results.into_iter().map(|r| RagDocument {
            id: r.id,
            source_type: r.source_type,
            title: r.title,
            content: r.content,
            source_url: r.source_url,
            published_at: r.published_at,
            score: r._distance.unwrap_or(0.0),
        }).collect())
    }
}
```

---

## 5. Agent 模块

### 5.1 工具注册 (tools.rs)

```rust
// src-tauri/src/agent/tools.rs
use genai::chat::{Tool, ToolCall, ToolCallResult};

pub fn register_tools() -> Vec<Tool> {
    vec![
        Tool {
            name: "search_news".into(),
            description: "搜索最近 N 天的加密货币相关新闻。返回标题、摘要、时间、URL。".into(),
            parameters: serde_json::json!({
                "type": "object",
                "properties": {
                    "keyword": {"type": "string", "description": "搜索关键词"},
                    "days": {"type": "integer", "default": 3},
                    "lang": {"type": "string", "enum": ["zh", "en"], "default": "zh"}
                },
                "required": ["keyword"]
            }),
        },
        Tool {
            name: "get_klines".into(),
            description: "获取 K 线数据用于技术分析".into(),
            parameters: serde_json::json!({
                "type": "object",
                "properties": {
                    "symbol": {"type": "string", "description": "交易对, 如 BTCUSDT"},
                    "interval": {"type": "string", "enum": ["1m","5m","15m","1h","4h","1d"]},
                    "limit": {"type": "integer", "default": 100}
                },
                "required": ["symbol", "interval"]
            }),
        },
        Tool {
            name: "get_tweets".into(),
            description: "搜索 Twitter/X 上关于指定加密货币的最新推文".into(),
            parameters: serde_json::json!({
                "type": "object",
                "properties": {
                    "query": {"type": "string"},
                    "max_results": {"type": "integer", "default": 10}
                },
                "required": ["query"]
            }),
        },
        Tool {
            name: "get_onchain_activity".into(),
            description: "获取链上活动（大额转账、交易所流入流出、活跃地址数）".into(),
            parameters: serde_json::json!({
                "type": "object",
                "properties": {
                    "symbol": {"type": "string", "enum": ["BTC", "ETH", "SOL"]},
                    "metric": {"type": "string", "enum": ["whale_transfers", "exchange_flow", "active_addresses"]}
                },
                "required": ["symbol"]
            }),
        },
        Tool {
            name: "analyze_technicals".into(),
            description: "执行技术指标分析（MA, MACD, RSI, Bollinger Bands），返回信号与解读".into(),
            parameters: serde_json::json!({
                "type": "object",
                "properties": {
                    "symbol": {"type": "string"},
                    "interval": {"type": "string"}
                },
                "required": ["symbol", "interval"]
            }),
        },
        Tool {
            name: "get_market_overview".into(),
            description: "获取当前市场概览：恐惧贪婪指数、总市值、BTC 占比等".into(),
            parameters: serde_json::json!({
                "type": "object",
                "properties": {}
            }),
        },
    ]
}
```

### 5.2 Agent 循环 (loop.rs)

```rust
// src-tauri/src/agent/loop.rs
use genai::chat::{ChatMessage, ChatRequest, ChatResponse, ToolCall};
use tokio::sync::mpsc;

#[derive(Debug, Clone, Serialize)]
#[serde(tag = "type")]
pub enum AgentEvent {
    TextDelta { content: String },
    ToolStart { tool_name: String, args: serde_json::Value },
    ToolEnd { tool_name: String, result: serde_json::Value },
    AnalysisCard { data: serde_json::Value },
    Error { message: String },
    Done,
}

pub struct Agent {
    llm_client: genai::Client,
    model_name: String,
    tools: Vec<Tool>,
    max_iterations: usize,  // 最大工具调用轮数
}

impl Agent {
    /// 执行 Agent 循环，返回流式事件
    pub async fn execute(
        &self,
        user_message: &str,
        context: &AgentContext,
        event_tx: mpsc::UnboundedSender<AgentEvent>,
    ) -> Result<(), anyhow::Error> {
        let system_prompt = self.build_system_prompt(context);
        let mut messages = vec![
            ChatMessage::system(system_prompt),
            ChatMessage::user(user_message),
        ];

        for iteration in 0..self.max_iterations {
            // 调用 LLM
            let request = ChatRequest::new(messages.clone())
                .with_tools(self.tools.clone())
                .with_stream(true);

            let mut chat_stream = self.llm_client
                .exec_chat_stream(&self.model_name, request, None)
                .await?;

            // 收集流式输出
            let mut full_text = String::new();
            let mut tool_calls: Vec<ToolCall> = vec![];

            while let Some(chunk) = chat_stream.next().await {
                match chunk {
                    ChatStreamEvent::TextDelta(text) => {
                        full_text.push_str(&text);
                        let _ = event_tx.send(AgentEvent::TextDelta { content: text });
                    }
                    ChatStreamEvent::ToolCall(tc) => {
                        tool_calls.push(tc);
                    }
                    ChatStreamEvent::End(_) => break,
                }
            }

            // 如果没有工具调用，返回最终文本
            if tool_calls.is_empty() {
                let _ = event_tx.send(AgentEvent::Done);
                return Ok(());
            }

            // 执行工具调用
            messages.push(ChatMessage::assistant_with_tools(full_text, tool_calls.clone()));

            for tc in &tool_calls {
                let _ = event_tx.send(AgentEvent::ToolStart {
                    tool_name: tc.name.clone(),
                    args: tc.arguments.clone(),
                });

                let result = self.execute_tool(tc).await?;

                let _ = event_tx.send(AgentEvent::ToolEnd {
                    tool_name: tc.name.clone(),
                    result: result.clone(),
                });

                messages.push(ChatMessage::tool(tc.id.clone(), result));
            }
        }

        // 达到最大迭代次数，强制 LLM 总结
        messages.push(ChatMessage::user("请基于以上所有信息给出最终分析总结。"));
        // ... 再调一次 LLM 获取最终回复

        let _ = event_tx.send(AgentEvent::Done);
        Ok(())
    }

    /// 执行单个工具
    async fn execute_tool(&self, tc: &ToolCall) -> Result<serde_json::Value, anyhow::Error> {
        match tc.name.as_str() {
            "search_news" => self.tool_search_news(&tc.arguments).await,
            "get_klines" => self.tool_get_klines(&tc.arguments).await,
            "get_tweets" => self.tool_get_tweets(&tc.arguments).await,
            "get_onchain_activity" => self.tool_get_onchain(&tc.arguments).await,
            "analyze_technicals" => self.tool_analyze_technicals(&tc.arguments).await,
            "get_market_overview" => self.tool_market_overview().await,
            _ => Ok(serde_json::json!({"error": format!("Unknown tool: {}", tc.name)})),
        }
    }
}
```

### 5.3 System Prompt 构建 (prompt.rs)

```rust
// src-tauri/src/agent/prompt.rs
impl Agent {
    fn build_system_prompt(&self, context: &AgentContext) -> String {
        format!(
            r#"你是 CryptoQuant AI 助手，一个专业的加密货币市场分析师。

## 当前上下文
- 选中币种: {symbol}
- 当前时间: {current_time}
- 用户已配置数据源: {available_sources}

## 分析原则
1. 每次分析前务必先调用 search_news 获取最新资讯，不要依赖过时信息
2. 需要价格/走势数据时调用 get_klines
3. 链上数据用 get_onchain_activity 获取
4. 技术面分析用 analyze_technicals
5. 每条结论必须注明数据来源和时间
6. 给出分析观点但必须附带风险提示
7. 绝不生成具体的买入价/卖出价/止盈止损位
8. 若信息不足，明确告知用户，而非编造

## 输出规范
- 消息来源标注: [来源: NewsAPI, 时间: 2026-05-04 14:30]
- 不确定性标注: 若某信息的可信度 < 80%，需说明"该信息可能存在偏差"
- 风险提示: 每条分析末尾加 "⚠️ 以上为 AI 分析，不构成投资建议"

## 禁止行为
- 禁止预测具体价格
- 禁止建议杠杆倍数
- 禁止给出"必涨/必跌"等确定性断言
- 禁止处理与加密货币分析无关的请求
"#,
            symbol = context.symbol,
            current_time = chrono::Utc::now().format("%Y-%m-%d %H:%M:%S UTC"),
            available_sources = context.available_sources.join(", "),
        )
    }
}
```

---

## 6. 数据源模块

### 6.1 统一接口 (mod.rs)

```rust
// src-tauri/src/data_sources/mod.rs
use async_trait::async_trait;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RawNewsItem {
    pub id: String,
    pub title: String,
    pub content: String,
    pub summary: String,
    pub url: String,
    pub source_name: String,
    pub source_type: SourceType,
    pub published_at: i64,
    pub keywords: Vec<String>,
    pub related_symbol: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub enum SourceType {
    News,
    Tweet,
    Onchain,
}

#[async_trait]
pub trait DataSource: Send + Sync {
    fn name(&self) -> &str;
    fn source_type(&self) -> SourceType;
    async fn is_configured(&self) -> bool;
    async fn fetch(&self, query: &str, limit: usize) -> Result<Vec<RawNewsItem>, anyhow::Error>;
}

pub struct DataSourceHub {
    sources: Vec<Box<dyn DataSource>>,
}
```

### 6.2 NewsAPI 实现 (news.rs)

```rust
// src-tauri/src/data_sources/news.rs
pub struct NewsApiSource {
    api_key: Option<String>,
    client: reqwest::Client,
}

#[async_trait]
impl DataSource for NewsApiSource {
    fn name(&self) -> &str { "NewsAPI" }
    fn source_type(&self) -> SourceType { SourceType::News }

    async fn is_configured(&self) -> bool {
        self.api_key.is_some()
    }

    async fn fetch(&self, query: &str, limit: usize) -> Result<Vec<RawNewsItem>, anyhow::Error> {
        let api_key = self.api_key.as_ref()
            .ok_or(anyhow::anyhow!("NewsAPI key not configured"))?;

        let response = self.client
            .get("https://newsapi.org/v2/everything")
            .query(&[
                ("q", format!("{} cryptocurrency", query)),
                ("sortBy", "publishedAt".to_string()),
                ("language", "en".to_string()),
                ("pageSize", limit.to_string()),
                ("apiKey", api_key.clone()),
            ])
            .send()
            .await?;

        let body: serde_json::Value = response.json().await?;
        let articles = body["articles"].as_array()
            .ok_or(anyhow::anyhow!("Invalid response"))?;

        Ok(articles.iter().map(|a| RawNewsItem {
            id: a["url"].as_str().unwrap_or("").to_string(),
            title: a["title"].as_str().unwrap_or("").to_string(),
            content: a["content"].as_str().unwrap_or("").to_string(),
            summary: a["description"].as_str().unwrap_or("").to_string(),
            url: a["url"].as_str().unwrap_or("").to_string(),
            source_name: a["source"]["name"].as_str().unwrap_or("NewsAPI").to_string(),
            source_type: SourceType::News,
            published_at: chrono::DateTime::parse_from_rfc3339(
                a["publishedAt"].as_str().unwrap_or("")
            ).map(|d| d.timestamp_millis()).unwrap_or(0),
            keywords: vec![],
            related_symbol: None,
        }).collect())
    }
}
```

### 6.3 Twitter API 实现 (twitter.rs)

```rust
// src-tauri/src/data_sources/twitter.rs
pub struct TwitterSource {
    bearer_token: Option<String>,
    client: reqwest::Client,
}

#[async_trait]
impl DataSource for TwitterSource {
    fn name(&self) -> &str { "Twitter/X" }
    fn source_type(&self) -> SourceType { SourceType::Tweet }

    async fn is_configured(&self) -> bool {
        self.bearer_token.is_some()
    }

    async fn fetch(&self, query: &str, limit: usize) -> Result<Vec<RawNewsItem>, anyhow::Error> {
        let token = self.bearer_token.as_ref()
            .ok_or(anyhow::anyhow!("Twitter API key not configured"))?;

        let response = self.client
            .get("https://api.twitter.com/2/tweets/search/recent")
            .bearer_auth(token)
            .query(&[
                ("query", query),
                ("max_results", &limit.to_string()),
                ("tweet.fields", "created_at,author_id,public_metrics"),
            ])
            .send()
            .await?;

        let body: serde_json::Value = response.json().await?;
        let tweets = body["data"].as_array().unwrap_or(&vec![]);

        Ok(tweets.iter().map(|t| RawNewsItem {
            id: t["id"].as_str().unwrap_or("").to_string(),
            title: format!("@{}", t["author_id"].as_str().unwrap_or("unknown")),
            content: t["text"].as_str().unwrap_or("").to_string(),
            summary: t["text"].as_str().unwrap_or("").chars().take(200).collect(),
            url: format!("https://twitter.com/i/status/{}", t["id"].as_str().unwrap_or("")),
            source_name: "Twitter/X".to_string(),
            source_type: SourceType::Tweet,
            published_at: chrono::DateTime::parse_from_rfc3339(
                t["created_at"].as_str().unwrap_or("")
            ).map(|d| d.timestamp_millis()).unwrap_or(0),
            keywords: vec![],
            related_symbol: None,
        }).collect())
    }
}
```

---

## 7. Tauri IPC Commands

```rust
// src-tauri/src/commands/mod.rs
use tauri::{AppHandle, Manager};
use crate::AppState;
use tokio::sync::mpsc;

/// 获取 K 线数据
#[tauri::command]
async fn get_klines(
    state: tauri::State<'_, AppState>,
    symbol: String,
    interval: String,
    limit: Option<u16>,
) -> Result<Vec<binance::Kline>, String> {
    state.binance
        .rest
        .get_klines(&symbol, &interval, limit.unwrap_or(100))
        .await
        .map_err(|e| e.to_string())
}

/// 发送聊天消息 (Agent 循环)
#[tauri::command]
async fn chat_send(
    app: AppHandle,
    state: tauri::State<'_, AppState>,
    message: String,
    context: agent::AgentContext,
) -> Result<(), String> {
    let agent = state.agent.clone();
    let (tx, mut rx) = mpsc::unbounded_channel::<agent::AgentEvent>();

    // 启动 Agent 循环
    tokio::spawn(async move {
        if let Err(e) = agent.execute(&message, &context, tx).await {
            tracing::error!("Agent error: {}", e);
        }
    });

    // 将 Agent 事件转发给前端
    let app_clone = app.clone();
    tokio::spawn(async move {
        while let Some(event) = rx.recv().await {
            let _ = app_clone.emit("chat-stream", &event);
        }
    });

    Ok(())
}

/// 获取资讯流
#[tauri::command]
async fn feed_fetch(
    state: tauri::State<'_, AppState>,
    symbol: String,
    filter: Option<String>,
) -> Result<Vec<data_sources::RawNewsItem>, String> {
    // 使用 RAG 检索最近的数据，不重新从 API 拉取
    let source_type = match filter.as_deref() {
        Some("news") => Some(SourceType::News),
        Some("tweet") => Some(SourceType::Tweet),
        Some("onchain") => Some(SourceType::Onchain),
        _ => None,
    };

    let docs = state.rag
        .retrieve(&symbol, source_type, None, 50)
        .await
        .map_err(|e| e.to_string())?;

    // 转换为 FeedItem 返回
    Ok(docs.into_iter().map(|d| d.into()).collect())
}

/// 设置 API Key
#[tauri::command]
async fn settings_set_api_key(
    state: tauri::State<'_, AppState>,
    provider: String,
    key: String,
) -> Result<(), String> {
    state.keychain
        .set_secret(&provider, &key)
        .map_err(|e| e.to_string())
}
```

---

## 8. 密钥管理 (OS Keychain)

```rust
// src-tauri/src/commands/keychain.rs
use keyring::Entry;

pub struct KeychainManager {
    service_name: String,
}

impl KeychainManager {
    pub fn new() -> Self {
        Self {
            service_name: "crypto-quant-tool".to_string(),
        }
    }

    pub fn set_secret(&self, key: &str, value: &str) -> Result<(), anyhow::Error> {
        let entry = Entry::new(&self.service_name, key)?;
        entry.set_secret(value)?;
        Ok(())
    }

    pub fn get_secret(&self, key: &str) -> Result<String, anyhow::Error> {
        let entry = Entry::new(&self.service_name, key)?;
        Ok(entry.get_secret()?)
    }

    pub fn delete_secret(&self, key: &str) -> Result<(), anyhow::Error> {
        let entry = Entry::new(&self.service_name, key)?;
        entry.delete_secret()?;
        Ok(())
    }
}
```

---

## 9. 前端关键组件实现

### 9.1 WebSocket/Binance Hook

```typescript
// src/hooks/useBinanceWs.ts
import { listen } from '@tauri-apps/api/event';
import { useMarketStore } from '../stores/useMarketStore';
import { useSymbolStore } from '../stores/useSymbolStore';

export function useBinanceWs() {
  const selectedSymbol = useSymbolStore(s => s.selectedSymbol);
  const updateKline = useMarketStore(s => s.setKlineData);
  const updateOrderBook = useMarketStore(s => s.updateOrderBook);
  const updateTicker = useMarketStore(s => s.updateTicker);

  useEffect(() => {
    const unlisten = listen<MarketUpdate>('market-data', (event) => {
      switch (event.payload.type) {
        case 'Kline':
          updateKline(event.payload.interval, event.payload.kline);
          break;
        case 'OrderBook':
          updateOrderBook(event.payload.depth);
          break;
        case 'Ticker':
          updateTicker(event.payload.ticker);
          break;
      }
    });

    return () => { unlisten.then(fn => fn()) };
  }, []);

  // 当选中币种变化时，发送订阅命令
  useEffect(() => {
    invoke('subscribe_symbol', {
      symbol: selectedSymbol,
      intervals: ['1h', '4h', '1d'],
    });
  }, [selectedSymbol]);
}
```

### 9.2 K 线图组件

```typescript
// src/components/chart/KLineChart.tsx
import { createChart, ColorType } from 'lightweight-charts';
import { useMarketStore } from '../../stores/useMarketStore';

export function KLineChart() {
  const containerRef = useRef<HTMLDivElement>(null);
  const chartRef = useRef<ReturnType<typeof createChart>>();
  const candleSeriesRef = useRef<IChartApi>();

  useEffect(() => {
    if (!containerRef.current) return;

    const chart = createChart(containerRef.current, {
      layout: {
        background: { type: ColorType.Solid, color: '#0d1117' },
        textColor: '#8b949e',
      },
      grid: {
        vertLines: { color: '#21262d' },
        horzLines: { color: '#21262d' },
      },
      crosshair: { mode: 1 },
      rightPriceScale: { borderColor: '#30363d' },
      timeScale: { borderColor: '#30363d', timeVisible: true },
    });

    const candleSeries = chart.addCandlestickSeries({
      upColor: '#26a69a',
      downColor: '#ef5350',
      borderUpColor: '#26a69a',
      borderDownColor: '#ef5350',
      wickUpColor: '#26a69a',
      wickDownColor: '#ef5350',
    });

    chartRef.current = chart;
    candleSeriesRef.current = candleSeries;

    return () => chart.remove();
  }, []);

  return (
    <div className="flex flex-col h-full">
      <ChartToolbar />
      <div ref={containerRef} className="flex-1" />
      <OrderBook />
    </div>
  );
}
```

### 9.3 对话面板

```typescript
// src/components/chat/ChatPanel.tsx
import { useChatStore } from '../../stores/useChatStore';
import { ChatHistory } from './ChatHistory';
import { ChatInput } from './ChatInput';

export function ChatPanel() {
  const messages = useChatStore(s => s.messages);
  const isStreaming = useChatStore(s => s.isStreaming);
  const sendMessage = useChatStore(s => s.sendMessage);

  return (
    <div className="flex flex-col h-full bg-[#0d1117] border-l border-[#21262d]">
      <div className="px-4 py-3 border-b border-[#21262d]">
        <h2 className="text-sm font-semibold text-[#c9d1d9]">AI 分析助手</h2>
        {isStreaming && (
          <span className="text-xs text-[#f0b90b] animate-pulse">● 分析中...</span>
        )}
      </div>
      <ChatHistory messages={messages} />
      <ChatInput onSend={sendMessage} disabled={isStreaming} />
    </div>
  );
}
```

### 9.4 资讯流组件

```typescript
// src/components/feed/NewsFeed.tsx
import { useFeedStore } from '../../stores/useFeedStore';
import { FeedItem } from './FeedItem';
import { FeedFilter } from './FeedFilter';
import { useSymbolStore } from '../../stores/useSymbolStore';

export function NewsFeed() {
  const { items, loading, filter, setFilter, fetchFeed } = useFeedStore();
  const selectedSymbol = useSymbolStore(s => s.selectedSymbol);

  useEffect(() => {
    fetchFeed(selectedSymbol);
  }, [selectedSymbol]);

  return (
    <div className="flex flex-col h-full overflow-hidden">
      <FeedFilter active={filter} onChange={setFilter} />
      <div className="flex-1 overflow-y-auto space-y-2 p-2">
        {items.map(item => (
          <FeedItem key={item.id} item={item} />
        ))}
        {loading && <LoadingSkeleton />}
        {!loading && items.length === 0 && (
          <p className="text-sm text-[#8b949e] text-center py-4">
            暂无相关资讯
          </p>
        )}
      </div>
    </div>
  );
}
```

---

## 10. 统一错误类型

### 10.1 Rust 侧错误枚举

```rust
// src-tauri/src/types.rs

#[derive(Debug, thiserror::Error)]
pub enum AppError {
    #[error("Binance WebSocket 连接断开")]
    BinanceWsDisconnected,

    #[error("Binance API 请求频率超限")]
    BinanceRateLimited,

    #[error("无效的交易对: {0}")]
    BinanceInvalidSymbol(String),

    #[error("RAG 引擎初始化失败: {0}")]
    RagInitFailed(String),

    #[error("向量嵌入生成失败: {0}")]
    RagEmbedFailed(String),

    #[error("向量存储写入失败: {0}")]
    RagStoreFailed(String),

    #[error("检索失败: {0}")]
    RagRetrieveFailed(String),

    #[error("数据源 {0} 未配置 API Key")]
    SourceNotConfigured(String),

    #[error("数据源 {0} 请求频率超限")]
    SourceRateLimited(String),

    #[error("数据源 {0} 请求失败: {1}")]
    SourceFetchFailed(String, String),

    #[error("未配置 LLM API Key")]
    LlmNotConfigured,

    #[error("LLM API 请求频率超限")]
    LlmRateLimited,

    #[error("LLM API 请求超时")]
    LlmTimeout,

    #[error("LLM 返回无效响应: {0}")]
    LlmInvalidResponse(String),

    #[error("Keychain 读取失败")]
    KeychainReadFailed,

    #[error("Keychain 写入失败")]
    KeychainWriteFailed,

    #[error("数据库打开失败: {0}")]
    DbOpenFailed(String),

    #[error("数据库写入失败: {0}")]
    DbWriteFailed(String),

    #[error("无效的参数: {0}")]
    InvalidArgument(String),

    #[error("网络不可用")]
    NetworkUnavailable,
}
```

### 10.2 Tauri Command 错误传播

```rust
// 所有 #[tauri::command] 返回 Result<T, String>
// 调用方通过 app.emit("error", payload) 推送全局错误给前端 Toast

fn emit_error(app: &AppHandle, e: anyhow::Error) {
    let payload = serde_json::json!({
        "code": "UNKNOWN",
        "message": e.to_string(),
        "severity": "error",
        "timestamp": chrono::Utc::now().timestamp_millis(),
    });
    let _ = app.emit("error", &payload);
}
```

---

## 11. 数据刷新节流 (500ms)

### 后端合并

```rust
// Binance WS → 500ms 缓冲区 → 去重 → 批量 emit

pub struct ThrottledEventBus {
    buffer: Arc<Mutex<Vec<MarketUpdate>>>,
}

impl ThrottledEventBus {
    pub fn start(&self, app: AppHandle) {
        let buffer = self.buffer.clone();
        tokio::spawn(async move {
            let mut ticker = tokio::time::interval(Duration::from_millis(500));
            loop {
                ticker.tick().await;
                let mut buf = buffer.lock().await;
                if !buf.is_empty() {
                    let batch: Vec<_> = buf.drain(..).collect();
                    let _ = app.emit("market-data", &batch);
                }
            }
        });
    }
}
```

### 前端合并

```typescript
// 500ms 后端节流 + requestAnimationFrame 合并
const pendingRef = useRef<MarketUpdate[]>([]);
const rafRef = useRef<number>();

const flush = useCallback(() => {
    const batch = pendingRef.current;
    pendingRef.current = [];
    rafRef.current = undefined;
    for (const update of batch) {
        applyToStore(update);
    }
}, []);
```

---

## 12. 应用入口（含路由守卫 + 全局错误监听）

```typescript
// src/App.tsx
import { useSettingsStore } from './stores/useSettingsStore';
import { AppLayout } from './components/layout/AppLayout';
import { SettingsPage } from './components/settings/SettingsPage';
import { LoadingScreen } from './components/LoadingScreen';

function App() {
  const { loading, requiredConfigured, fetchStatus } = useSettingsStore();

  useEffect(() => { fetchStatus(); }, []);

  // 全局错误监听 → Toast
  useEffect(() => {
    const unlisten = listen<AppError>('error', (event) => {
      const { severity, message } = event.payload;
      if (severity === 'error') toast.error(message);
      else if (severity === 'warning') toast.warning(message);
    });
    return () => { unlisten.then(fn => fn()) };
  }, []);

  if (loading) return <LoadingScreen />;

  return requiredConfigured
    ? <AppLayout />
    : <SettingsPage onboarding />;
}
```
