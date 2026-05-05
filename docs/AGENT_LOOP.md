# Agent 循环设计 (AGENT_LOOP)

## 1. 架构模式：ReAct

```
ReAct = Reasoning + Acting

循环:
  Thought → Action → Observation → Thought → Action → ... → Final Answer

伪代码:
  while not finished AND iteration < max_iterations:
      response = LLM(messages + tools)
      if response has tool_calls:
          for each tool_call:
              result = execute(tool_call)
              messages += [tool_result]
      else:
          return response.text  # 最终回答
```

---

## 2. Agent 结构

```rust
pub struct Agent {
    /// LLM 客户端 (genai 多提供商统一接口)
    llm_client: genai::Client,

    /// 模型名称 (如 "gpt-4o-mini", "claude-3-haiku", "ollama/qwen2.5")
    model_name: String,

    /// 可用工具列表
    tools: Vec<Tool>,

    /// 最大工具调用轮数 (防止无限循环)
    max_iterations: usize,  // 默认 5

    /// 最大上下文 tokens (超出则截断历史)
    max_context_tokens: usize,  // 默认 32000

    /// RAG 引擎引用
    rag: Arc<RagEngine>,

    /// 数据源引用
    data_sources: Arc<DataSourceHub>,

    /// Binance 客户端引用
    binance: Arc<BinanceClient>,
}
```

---

## 3. 执行流程 (详细)

### 3.1 主循环

```rust
impl Agent {
    pub async fn execute(
        &self,
        user_message: &str,
        context: &AgentContext,
        event_tx: mpsc::UnboundedSender<AgentEvent>,
    ) -> Result<()> {
        // Step 1: 构建初始消息
        let system_prompt = self.build_system_prompt(context);
        let mut messages = vec![
            ChatMessage::system(system_prompt),
            ChatMessage::user(user_message),
        ];

        // Step 2: ReAct 循环
        for iteration in 0..self.max_iterations {
            tracing::info!("Agent iteration {}/{}", iteration + 1, self.max_iterations);

            // 2a. 调用 LLM
            let request = ChatRequest::new(messages.clone())
                .with_tools(self.tools.clone())
                .with_temperature(0.3)  // 低温度减少幻觉
                .with_max_tokens(4096);

            let (full_text, tool_calls) = self
                .call_llm_with_stream(&request, &event_tx)
                .await?;

            // 2b. 无工具调用 → 最终回答
            if tool_calls.is_empty() {
                event_tx.send(AgentEvent::Done)?;
                return Ok(());
            }

            // 2c. 记录工具调用
            messages.push(ChatMessage::assistant_with_tools(
                full_text,
                tool_calls.clone(),
            ));

            // 2d. 执行所有工具调用
            for tc in &tool_calls {
                // 通知前端
                event_tx.send(AgentEvent::ToolStart {
                    tool_name: tc.name.clone(),
                    args: tc.arguments.clone(),
                })?;

                // 执行
                let result = match self.execute_tool(tc).await {
                    Ok(r) => {
                        event_tx.send(AgentEvent::ToolEnd {
                            tool_name: tc.name.clone(),
                            result: r.clone(),
                        })?;
                        ChatMessage::tool_result(tc.id.clone(), r)
                    }
                    Err(e) => {
                        let error_msg = json!({"error": e.to_string()});
                        event_tx.send(AgentEvent::ToolEnd {
                            tool_name: tc.name.clone(),
                            result: error_msg.clone(),
                        })?;
                        ChatMessage::tool_result(tc.id.clone(), error_msg)
                    }
                };

                messages.push(result);
            }

            // 2e. 检查上下文长度
            self.trim_context_if_needed(&mut messages);
        }

        // Step 3: 达到最大迭代，强制 LLM 总结
        messages.push(ChatMessage::user(
            "你已达到最大操作次数限制。请基于以上所有已获取的信息，给出你的最终分析总结。"
        ));
        // ... 再调一次 LLM（不允许工具调用）
        event_tx.send(AgentEvent::Done)?;
        Ok(())
    }
}
```

### 3.2 流式 LLM 调用

```rust
async fn call_llm_with_stream(
    &self,
    request: &ChatRequest,
    event_tx: &mpsc::UnboundedSender<AgentEvent>,
) -> Result<(String, Vec<ToolCall>)> {
    let mut chat_stream = self.llm_client
        .exec_chat_stream(&self.model_name, request.clone(), None)
        .await?;

    let mut full_text = String::new();
    let mut tool_calls: Vec<ToolCall> = vec![];

    // 流式处理每个 chunk
    while let Some(result) = chat_stream.next().await {
        match result {
            Ok(ChatStreamEvent::TextDelta(text)) => {
                full_text.push_str(&text);
                // 推送文本增量给前端
                let _ = event_tx.send(AgentEvent::TextDelta {
                    content: text,
                });
            }
            Ok(ChatStreamEvent::ToolCall(tc)) => {
                tool_calls.push(tc);
            }
            Ok(ChatStreamEvent::End(meta)) => {
                // 流结束，返回完整结果
                return Ok((full_text, tool_calls));
            }
            Err(e) => {
                let _ = event_tx.send(AgentEvent::Error {
                    message: format!("LLM error: {}", e),
                });
                return Err(e.into());
            }
        }
    }

    Ok((full_text, tool_calls))
}
```

---

## 4. System Prompt 设计

### 4.1 模板

```rust
fn build_system_prompt(&self, context: &AgentContext) -> String {
    format!(r#"你是 CryptoQuant AI 助手，一个专业的加密货币市场分析师。

## 你的能力
你可以通过调用工具来获取实时数据：
- `search_news` — 搜索最新加密货币新闻、政策动态、市场事件
- `get_klines` — 获取 K 线数据（开盘/收盘/最高/最低/成交量）
- `get_tweets` — 搜索 Twitter/X 上的相关推文
- `get_onchain_activity` — 查询链上活动（大额转账、交易所流入流出）
- `analyze_technicals` — 执行技术指标分析（MA/MACD/RSI/布林带）
- `get_market_overview` — 获取市场整体概况

## 当前上下文
- 用户选中的币种: {symbol}
- 当前时间: {current_time}
- 已配置数据源: {available_sources}

## 分析原则

### 数据获取
1. 每次分析前，务必先调用 search_news 获取最新资讯
2. 需要价格走势时调用 get_klines
3. 技术面分析用 analyze_technicals（会自动计算指标并解读）
4. 所有数据源都要交叉验证，不同来源的信息冲突时请注明

### 分析输出
5. 每条结论必须注明数据来源和时间
6. 如果某条信息的可信度低于 80%，必须说明"该信息可能存在偏差"
7. 信息不足时明确告知用户，绝不编造或猜测
8. 给出分析观点时必须附带风险提示

### 禁止行为
- ❌ 禁止预测具体价格
- ❌ 禁止建议杠杆倍数  
- ❌ 禁止给出"必涨"、"必跌"、"稳赚"等确定性断言
- ❌ 禁止建议具体的买入/卖出/止盈/止损价位
- ❌ 禁止处理与加密货币分析无关的请求

## 输出格式
- Markdown 格式，结构清晰
- 消息来源标注: `[来源: NewsAPI, 时间: 2026-05-04 14:30]`
- 每条分析末尾加: `⚠️ 以上为 AI 分析，不构成投资建议`
- 关键数据使用 **加粗** 突出
"#,
        symbol = context.symbol,
        current_time = chrono::Utc::now().format("%Y-%m-%d %H:%M:%S UTC"),
        available_sources = context.available_sources.join(", "),
    )
}
```

### 4.2 上下文注入策略

```
AgentContext {
    symbol: "ETHUSDT",          // 当前选中币种
    current_price: 3456.78,     // 当前价格 (可选)
    selected_interval: "4h",    // 当前图表周期 (可选)
    available_sources: [        // 用户已配置的数据源
        "NewsAPI",
        "Etherscan",
        // "Twitter" 未配置, 不显示
    ],
    conversation_history: [     // 最近 3 轮对话摘要 (节省 token)
        { role: "user", content: "ETH 走势怎么样？" },
        { role: "assistant", summary: "分析了ETH 4h K线 + 新闻..." },
    ],
}
```

---

## 5. 工具返回格式

### 5.1 标准化返回结构

```json
{
  "success": true,
  "data": [...],
  "metadata": {
    "source": "NewsAPI",
    "timestamp": 1714800000000,
    "query": "ETH",
    "result_count": 15
  },
  "summary": "找到 15 条 ETH 相关新闻，时间范围 2026-05-01 至 2026-05-04"
}
```

### 5.2 技术指标返回示例

```json
{
  "success": true,
  "data": {
    "symbol": "ETHUSDT",
    "interval": "4h",
    "current_price": 3456.78,
    "indicators": {
      "ema": {
        "ema7": 3420.50,
        "ema25": 3380.30,
        "ema99": 3100.00,
        "signal": "ema7 位于 ema25 之上，短期偏多"
      },
      "macd": {
        "macd_line": 15.2,
        "signal_line": 12.8,
        "histogram": 2.4,
        "signal": "MACD 金叉，柱状图在零轴上方扩大，偏多信号"
      },
      "rsi": {
        "value": 62.5,
        "signal": "RSI 位于中性偏强区域，未进入超买"
      },
      "bollinger": {
        "upper": 3520.0,
        "middle": 3420.0,
        "lower": 3320.0,
        "position": "价格位于布林带中轨与上轨之间",
        "bandwidth": 0.058,
        "signal": "布林带收窄，可能即将出现突破"
      }
    },
    "overall_signal": "短期技术面偏多，EMA 多头排列 + MACD 金叉，但需注意布林带收窄可能意味着波动加剧"
  }
}
```

---

## 6. 错误处理策略

### 6.1 工具执行失败

```rust
// 工具执行失败时，返回错误信息给 LLM 而不是中止 Agent
match self.execute_tool(tc).await {
    Ok(r) => messages.push(ChatMessage::tool_result(tc.id, r)),
    Err(e) => messages.push(ChatMessage::tool_result(
        tc.id,
        json!({
            "success": false,
            "error": e.to_string(),
            "suggestion": "该工具调用失败，请尝试其他方式获取所需信息或询问用户"
        })
    )),
}
```

### 6.2 LLM 调用失败

- **临时错误** (429 rate limit, 503 service unavailable)：3 次重试，指数退避
- **永久错误** (401 unauthorized, 400 bad request)：立即中止，返回错误给用户
- **超时** (30 秒无响应)：中止当前调用，提示用户切换模型或检查网络

### 6.3 幻觉缓解

```
1. 强制引用来源：每个 news 工具结果包含 URL，LLM 必须引用
2. 数值交叉验证：analyze_technicals 返回的价格与实时 ticker 交叉比对
3. 时间戳检查：RAG 检索结果包含发布时间，LLM 必须标注
4. 置信度限制：prompt 中明确要求，不确定时标注而非断言
5. 输出校验（未来 Phase 4）：对 LLM 输出做规则校验 (e.g., 价格不能为负数)
```

---

## 7. 对话历史管理

### 7.1 本地持久化

```rust
use rusqlite::Connection;

pub struct ChatHistoryStore {
    db: Connection,
}

impl ChatHistoryStore {
    pub fn new(data_dir: &Path) -> Result<Self> {
        let db = Connection::open(data_dir.join("chat_history.db"))?;
        db.execute_batch(
            "CREATE TABLE IF NOT EXISTS conversations (
                id TEXT PRIMARY KEY,
                created_at INTEGER NOT NULL,
                updated_at INTEGER NOT NULL,
                messages TEXT NOT NULL  -- JSON array
            )"
        )?;
        Ok(Self { db })
    }

    pub fn save(&self, conv_id: &str, messages: &[ChatMessage]) -> Result<()> {
        self.db.execute(
            "INSERT OR REPLACE INTO conversations VALUES (?1, ?2, ?3, ?4)",
            params![conv_id, now_ms(), now_ms(), serde_json::to_string(messages)?],
        )?;
        Ok(())
    }
}
```

### 7.2 上下文窗口管理

```rust
/// 当消息总 token 数超过限制时，截断历史
fn trim_context_if_needed(&self, messages: &mut Vec<ChatMessage>) {
    let token_count = self.estimate_tokens(messages);
    if token_count > self.max_context_tokens {
        // 保留: system + 最近 3 轮对话 + 最新的工具结果
        // 移除中间的对话轮次
        let system_idx = 0;  // system prompt 位置
        let keep_recent = 6;  // 保留最近 3 轮 (user+assistant+tool 各 1)

        if messages.len() > keep_recent + 1 {
            // 在 system 后插入一条总结消息
            messages.insert(1, ChatMessage::user(
                "[更早的对话已省略以节省上下文空间]"
            ));
        }
    }
}
```
