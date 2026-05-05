# MVP 阶段规划 (MVP_PLAN)

## 版本策略

```
v0.1.0 ──→ v0.2.0 ──→ v0.3.0 ──→ v1.0.0
 骨架       数据源      AI 对话      正式发布
```

---

## Phase 1: 骨架搭建 (v0.1.0)

**目标**：Tauri + React 跑通，界面骨架完整，能看到实时 K 线

**周期**：2-3 周

### 任务清单

#### 1.1 项目初始化
- [ ] `npm create tauri-app@latest crypto-quant-tool -- --template react-ts`
- [ ] 配置 Tailwind CSS + shadcn/ui 暗色主题
- [ ] 配置 ESLint + Prettier
- [ ] 配置 `src-tauri/Cargo.toml` 依赖
- [ ] 配置 `tauri.conf.json`（窗口大小、标题、权限）

#### 1.2 布局骨架
- [ ] 实现 `AppLayout`：左右分栏 + 可拖拽调整宽度
- [ ] 实现 `LeftPanel` 容器
- [ ] 实现 `RightPanel` 容器
- [ ] 实现 `ResizeHandle` 拖拽手柄

#### 1.3 币种切换
- [ ] 实现 `SymbolSelector` 组件
- [ ] 实现 `useSymbolStore`（Zustand）
- [ ] 默认币种列表：BTC, ETH, BNB, SOL, XRP, DOGE

#### 1.4 K 线图
- [ ] 集成 Lightweight Charts v4
- [ ] 实现 `KLineChart` 组件（Candlestick + Volume）
- [ ] 实现 `ChartToolbar`（周期切换: 1m/5m/15m/1h/4h/1d）
- [ ] 实现 Binance REST 获取历史 K 线（`binance-sdk`）
- [ ] 实现 Binance WebSocket 实时更新 K 线（`tokio-tungstenite`）

#### 1.5 订单簿
- [ ] 实现 `OrderBook` 组件（买卖盘口表）
- [ ] Binance WebSocket 实时深度数据

#### 1.6 价格行情
- [ ] 实现 `PriceTicker` 组件（当前价 + 24h 涨跌 + 量）
- [ ] Binance WebSocket 24h Ticker

#### 1.7 后端基础
- [ ] `main.rs` Tauri 入口 + `AppState` 管理
- [ ] `commands/` 实现 `get_klines`, `get_order_book`, `get_ticker_24h`
- [ ] Binance WebSocket 连接 + 重连逻辑
- [ ] Event 推送机制（`market-data` event）

#### 1.8 设置页面
- [ ] `SettingsPage` 框架（空壳）
- [ ] API Key 输入表单（Binance API Key）

### Phase 1 交付物

```
✅ 应用可启动，显示 K 线图
✅ 可切换不同币种，图表自动更新
✅ 实时显示价格、涨跌幅、订单簿
✅ 暗色主题
```

---

## Phase 2: 数据源集成 (v0.2.0)

**目标**：资讯流可用，RAG 管道跑通，能搜索新闻/推文/链上数据

**周期**：3-4 周

### 任务清单

#### 2.1 资讯流 UI
- [ ] 实现 `NewsFeed` 容器组件
- [ ] 实现 `FeedItem` 卡片（标题 + 摘要 + 来源图标 + 时间）
- [ ] 实现 `FeedFilter` 筛选（全部/新闻/推文/链上）
- [ ] 实现 `useFeedStore`（Zustand）

#### 2.2 RAG 引擎
- [ ] 实现 `rag/mod.rs` `RagEngine` 结构体
- [ ] 集成 `fastembed`（本地嵌入模型 all-MiniLM-L6-v2）
- [ ] 集成 `lancedb`（嵌入式向量数据库）
- [ ] 实现 `chunker` 文本分块（递归字符分割）
- [ ] 实现 `embedder` 向量嵌入生成
- [ ] 实现 `store` 向量存储与索引
- [ ] 实现 `retriever` 语义检索（向量+文本混合搜索）

#### 2.3 数据采集器
- [ ] 实现 `collector` 定时采集任务（每 5 分钟）
- [ ] 实现去重逻辑（相同 URL 不重复入库）
- [ ] 实现过期清理（超过 7 天的数据自动清理）

#### 2.4 NewsAPI 集成
- [ ] 实现 `data_sources/news.rs` `NewsApiSource`
- [ ] REST 封装（搜索 + 分页 + 错误处理）
- [ ] API Key 配置（设置页面）

#### 2.5 Twitter API 集成
- [ ] 实现 `data_sources/twitter.rs` `TwitterSource`
- [ ] Bearer Token 认证
- [ ] 推文搜索 + 格式化
- [ ] API Key 配置

#### 2.6 链上数据集成
- [ ] 实现 `data_sources/onchain.rs`
- [ ] Whale Alert API（大额转账）
- [ ] Etherscan API（交易所流入流出）
- [ ] API Key 配置

#### 2.7 设置页面完善
- [ ] NewsAPI Key 输入
- [ ] Twitter API Key 输入
- [ ] Etherscan/Whale Alert API Key 输入
- [ ] API Key 状态检测（配置了/未配置）

### Phase 2 交付物

```
✅ 左侧资讯流显示最新新闻/推文/链上数据
✅ 支持按来源类型筛选
✅ 切换币种自动切换资讯内容
✅ API Key 安全管理（OS Keychain）
```

---

## Phase 3: AI 对话 (v0.3.0)

**目标**：AI 对话栏可用，Agent 能搜索/分析/总结

**周期**：3-4 周

### 任务清单

#### 3.1 对话 UI
- [ ] 实现 `ChatPanel` 主容器
- [ ] 实现 `ChatHistory` 消息列表（自动滚动）
- [ ] 实现 `UserMessage` 组件（Markdown 渲染）
- [ ] 实现 `AssistantMessage` 组件（Markdown + 代码块）
- [ ] 实现 `ChatInput` 组件（输入框 + 发送按钮）
- [ ] 实现 `ToolCallBlock`（工具调用过程可视化）
- [ ] 实现 `AnalysisCard`（结构化分析报告卡片）
- [ ] 实现 `useChatStore`（消息列表 + 流式更新）

#### 3.2 Agent 循环
- [ ] 实现 `agent/loop.rs` ReAct Agent 循环
- [ ] 实现 `agent/tools.rs` 工具注册与 Schema 定义
- [ ] 实现 `agent/prompt.rs` System Prompt 模板
- [ ] 流式输出：逐 token 推送前端

#### 3.3 LLM 集成
- [ ] 集成 `genai` crate
- [ ] OpenAI 提供商
- [ ] Anthropic 提供商
- [ ] Ollama 提供商（本地 LLM）
- [ ] LLM API Key 配置

#### 3.4 工具实现
- [ ] `search_news` — RAG 检索新闻
- [ ] `get_klines` — 获取 K 线
- [ ] `get_tweets` — 搜索推文
- [ ] `get_onchain_activity` — 链上数据
- [ ] `analyze_technicals` — 技术指标分析
- [ ] `get_market_overview` — 市场概览

#### 3.5 技术指标
- [ ] 集成 `kand` crate
- [ ] 实现 SMA/EMA（7/25/99）
- [ ] 实现 MACD（12/26/9）
- [ ] 实现 RSI（14）
- [ ] 实现 Bollinger Bands（20/2）
- [ ] K 线图上叠加 MA 线

#### 3.6 对话上下文
- [ ] 自动注入当前选中币种
- [ ] 自动注入 K 线数据摘要
- [ ] 对话历史持久化（本地 SQLite）

### Phase 3 交付物

```
✅ AI 对话栏完整可用
✅ 输入"分析 ETH 走势" → AI 自动搜索新闻 + 技术分析 → 流式输出报告
✅ 工具调用过程可视化
✅ 支持 OpenAI / Anthropic / Ollama 切换
```

---

## Phase 4: 打磨与发布 (v1.0.0)

**目标**：性能优化、错误处理、跨平台构建验证、文档完善

**周期**：2-3 周

### 任务清单

#### 4.1 性能优化
- [ ] WS 数据批量合并（减少 event 频率）
- [ ] LanceDB 索引优化
- [ ] fastembed 模型预热（启动时后台加载）
- [ ] 图表大数据量渲染优化
- [ ] 内存泄漏检查

#### 4.2 错误处理
- [ ] 全局错误边界（React Error Boundary）
- [ ] 后端错误统一格式化 + 前端 Toast 通知
- [ ] WS 断连 UI 提示 + 自动恢复
- [ ] API 限流提示
- [ ] 无效配置检测 + 引导

#### 4.3 跨平台构建
- [ ] macOS Apple Silicon 构建验证
- [ ] macOS Intel 构建验证
- [ ] Windows x64 构建验证
- [ ] Linux x64 构建验证
- [ ] 构建脚本 + CI/CD (GitHub Actions)

#### 4.4 文档
- [ ] 用户使用指南
- [ ] API Key 获取教程（图文）
- [ ] 开发者贡献指南
- [ ] CHANGELOG

### Phase 4 交付物

```
✅ 稳定可用的 v1.0.0 版本
✅ macOS / Windows / Linux 三平台构建产物
✅ 完整文档
```

---

## 里程碑时间线

```
Week  1-2:  ████ Phase 1: 骨架 (K线 + 订单簿 + 价格)
Week  3-4:  ████ Phase 1: 骨架 (BS 完善 + 设置页)
Week  5-6:  ████ Phase 2: 数据源 (RAG 引擎 + NewsAPI)
Week  7-8:  ████ Phase 2: 数据源 (Twitter + 链上 + 资讯流 UI)
Week  9-10: ████ Phase 3: AI 对话 (LLM 集成 + Agent 循环)
Week 11-12: ████ Phase 3: AI 对话 (工具 + 指标 + K线叠加)
Week 13-14: ████ Phase 4: 打磨 (性能 + 错误处理 + 构建)
Week 15-16: ████ Phase 4: 发布 (文档 + 发布 v1.0.0)
```

总预估：**3-4 个月**（业余时间，全职可压缩至 2 个月）
