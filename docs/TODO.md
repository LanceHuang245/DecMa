# 任务清单 (TODO)

> 状态: ⬜ 待开始 | 🔄 进行中 | ✅ 已完成 | ❌ 已取消

---

## Phase 1: 骨架搭建 (v0.1.0)

### 1.1 项目初始化
- [ ] ⬜ 创建 Tauri + React + TypeScript 项目
- [ ] ⬜ 配置 Tailwind CSS + shadcn/ui 暗色主题
- [ ] ⬜ 配置 ESLint + Prettier
- [ ] ⬜ 配置 `src-tauri/Cargo.toml` Rust 依赖
- [ ] ⬜ 配置 `tauri.conf.json` 窗口与权限
- [ ] ⬜ 验证 `npm run tauri dev` 正常启动

### 1.2 布局
- [ ] ⬜ 实现 `AppLayout` 左右分栏
- [ ] ⬜ 实现 `ResizeHandle` 拖拽调整分栏宽度
- [ ] ⬜ 实现 `LeftPanel` / `RightPanel` 容器
- [ ] ⬜ 响应式：窗口缩小到一定宽度时自动切换上下布局

### 1.3 币种切换
- [ ] ⬜ 实现 `SymbolSelector` 组件 (Tab 式切换)
- [ ] ⬜ 实现 `useSymbolStore` Zustand Store
- [ ] ⬜ 默认币种: BTCUSDT, ETHUSDT, BNBUSDT, SOLUSDT, XRPUSDT, DOGEUSDT

### 1.4 K 线图
- [ ] ⬜ 集成 Lightweight Charts v4
- [ ] ⬜ 实现 `KLineChart` 组件 (Candlestick + Volume 副图)
- [ ] ⬜ 实现 `ChartToolbar` 周期选择器
- [ ] ⬜ 实现 `get_klines` Tauri command (REST 获取历史数据)
- [ ] ⬜ 实现 Binance WebSocket 实时 K 线推送
- [ ] ⬜ 实现 `useMarketStore` klineData 管理

### 1.5 订单簿
- [ ] ⬜ 实现 `OrderBook` 组件 (Ask/Bid 双列表)
- [ ] ⬜ Binance WebSocket depth20@100ms 推送
- [ ] ⬜ 买卖盘口颜色区分 (红/绿)

### 1.6 价格行情
- [ ] ⬜ 实现 `PriceTicker` 组件
- [ ] ⬜ Binance WebSocket 24h Ticker 推送

### 1.7 Rust 后端
- [ ] ⬜ `main.rs` + `AppState` 管理
- [ ] ⬜ `binance/mod.rs` + `rest.rs` + `ws.rs` + `types.rs`
- [ ] ⬜ WS 重连逻辑 (指数退避, 最大 60s)
- [ ] ⬜ `commands/mod.rs` IPC 命令
- [ ] ⬜ Event: `market-data` 推前端

### 1.8 设置页
- [ ] ⬜ `SettingsPage` 框架
- [ ] ⬜ Binance API Key 输入 (OS Keychain 存储)
- [ ] ⬜ `useSettingsStore`

---

## Phase 2: 数据源集成 (v0.2.0)

### 2.1 资讯流 UI
- [ ] ⬜ 实现 `NewsFeed` 容器
- [ ] ⬜ 实现 `FeedItem` 卡片 (来源图标/标题/摘要/时间)
- [ ] ⬜ 实现 `FeedFilter` (全部/新闻/推文/链上)
- [ ] ⬜ 实现 `useFeedStore`
- [ ] ⬜ 虚拟滚动 (资讯量 > 100 条时)

### 2.2 RAG 引擎
- [ ] ⬜ `rag/mod.rs` `RagEngine` 结构体
- [ ] ⬜ 集成 `fastembed` (all-MiniLM-L6-v2)
- [ ] ⬜ 集成 `lancedb` (嵌入式, 本地持久化)
- [ ] ⬜ 实现 `chunker.rs` 递归字符分割
- [ ] ⬜ 实现 `embedder.rs` 批量向量化
- [ ] ⬜ 实现 `store.rs` LanceDB 建表与写入
- [ ] ⬜ 实现 `retriever.rs` 混合检索 (向量 + 全文)

### 2.3 数据采集
- [ ] ⬜ `collector.rs` 定时采集 (5 分钟周期)
- [ ] ⬜ 去重逻辑 (URL 级别)
- [ ] ⬜ 过期清理 (7 天以上自动删除)
- [ ] ⬜ 采集器启动/停止控制

### 2.4 NewsAPI
- [ ] ⬜ `data_sources/news.rs` 实现 `DataSource` trait
- [ ] ⬜ REST 封装 (搜索/分页/错误处理)
- [ ] ⬜ 设置页 NewsAPI Key 输入

### 2.5 Twitter API
- [ ] ⬜ `data_sources/twitter.rs` 实现 `DataSource` trait
- [ ] ⬜ Bearer Token 认证
- [ ] ⬜ 设置页 Twitter API Key 输入

### 2.6 链上数据
- [ ] ⬜ `data_sources/onchain.rs` 实现 `DataSource` trait
- [ ] ⬜ Whale Alert API
- [ ] ⬜ Etherscan API (流入流出)
- [ ] ⬜ 设置页各 API Key 输入

### 2.7 设置页完善
- [ ] ⬜ API 配置状态指示 (已配置/未配置/错误)
- [ ] ⬜ 密钥安全删除

---

## Phase 3: AI 对话 (v0.3.0)

### 3.1 对话 UI
- [ ] ⬜ `ChatPanel` 主容器
- [ ] ⬜ `ChatHistory` 消息列表 (自动滚底)
- [ ] ⬜ `UserMessage` 组件
- [ ] ⬜ `AssistantMessage` 组件 (Markdown 渲染)
- [ ] ⬜ `ChatInput` 输入框 + 发送
- [ ] ⬜ `ToolCallBlock` 工具调用展示
- [ ] ⬜ `AnalysisCard` 分析报告卡片
- [ ] ⬜ `useChatStore` (消息管理 + 流式追加)

### 3.2 Agent 循环
- [ ] ⬜ `agent/mod.rs` + `loop.rs` ReAct 循环
- [ ] ⬜ `agent/tools.rs` 6 个工具的 Schema 定义
- [ ] ⬜ `agent/prompt.rs` System Prompt 模板
- [ ] ⬜ 流式输出 → Tauri Events → 前端

### 3.3 LLM 集成
- [ ] ⬜ `genai` crate 集成
- [ ] ⬜ OpenAI 提供商 (gpt-4o-mini / gpt-4o)
- [ ] ⬜ Anthropic 提供商 (claude-3-haiku / claude-3.5-sonnet)
- [ ] ⬜ `ollama-rs` 本地 LLM 提供商
- [ ] ⬜ 设置页 LLM API Key + Model 选择

### 3.4 Agent 工具实现
- [ ] ⬜ `search_news` — RAG 检索
- [ ] ⬜ `get_klines` — K 线获取
- [ ] ⬜ `get_tweets` — 推文搜索
- [ ] ⬜ `get_onchain_activity` — 链上数据
- [ ] ⬜ `analyze_technicals` — 技术指标 + 信号解读
- [ ] ⬜ `get_market_overview` — 市场概览 (恐惧贪婪指数等)

### 3.5 技术指标 (kand)
- [ ] ⬜ `indicators/mod.rs` 统一接口
- [ ] ⬜ SMA/EMA (7/25/99)
- [ ] ⬜ MACD (12/26/9)
- [ ] ⬜ RSI (14)
- [ ] ⬜ Bollinger Bands (20/2)
- [ ] ⬜ K 线图上叠加 MA 线

### 3.6 对话增强
- [ ] ⬜ 自动注入当前选中币种
- [ ] ⬜ 对话历史本地持久化 (SQLite via `rusqlite`)
- [ ] ⬜ 对话清空/导出功能

---

## Phase 4: 打磨与发布 (v1.0.0)

### 4.1 性能
- [ ] ⬜ WS 批量合并 (100ms 窗口)
- [ ] ⬜ LanceDB 索引优化 + `optimize()`
- [ ] ⬜ fastembed 模型预加载 (应用启动时后台加载)
- [ ] ⬜ 图表渲染优化 (仅渲染可视区域)
- [ ] ⬜ 内存泄漏检查 (`tokio-console`)

### 4.2 错误处理
- [ ] ⬜ React Error Boundary
- [ ] ⬜ 后端错误 → 前端 Toast 通知
- [ ] ⬜ WS 断连 UI 提示
- [ ] ⬜ API 限流/配额用尽提示
- [ ] ⬜ 首次使用引导 (未配置 API Key 时)

### 4.3 跨平台构建
- [ ] ⬜ macOS aarch64 构建 + 签名
- [ ] ⬜ macOS x86_64 构建 + 签名
- [ ] ⬜ Windows x64 构建 + 安装包
- [ ] ⬜ Linux x64 AppImage 构建
- [ ] ⬜ CI/CD GitHub Actions

### 4.4 文档与发布
- [ ] ⬜ 用户使用指南
- [ ] ⬜ API Key 获取图文教程
- [ ] ⬜ 开发者贡献指南 (CONTRIBUTING.md)
- [ ] ⬜ CHANGELOG.md
- [ ] ⬜ LICENSE (MIT)
- [ ] ⬜ GitHub Release v1.0.0

---

## 新增任务 (基于已确认决策)

### Phase 1 补充
- [ ] ⬜ 实现 500ms 数据刷新节流 (后端合并去重 + 前端 RAF)
- [ ] ⬜ 实现全局错误监听 → Toast (`listen("error", ...)`)
- [ ] ⬜ 实现应用入口路由守卫 (未配置 API Key → 设置页)
- [ ] ⬜ 实现 K 线本地缓存 (离线降级, SQLite, 每币种每周期 1000 根)
- [ ] ⬜ 实现 Binance WS 断连重连 (指数退避 + 数据补全)

### Phase 2 补充
- [ ] ⬜ 实现资讯流时间倒序排序 + 来源筛选
- [ ] ⬜ 实现连接状态事件推送 (`connection-status`)
- [ ] ⬜ 实现离线 UI 提示横幅

### Phase 3 补充
- [ ] ⬜ 所有 UI 文字使用 i18n key (中文为主, 英文预留)
- [ ] ⬜ LLM 不可用时 Agent 降级处理 (返回已收集数据)
- [ ] ⬜ Token 合并渲染 (>20 字符或 >100ms 触发一次)

### Phase 4 补充
- [ ] ⬜ 首次引导流程测试 (必填项校验 + Key 验证 + 跳转)
- [ ] ⬜ 离线模式测试 (断网 + K线缓存 + 恢复)
- [ ] ⬜ Toast 错误提示调试

---

## 技术债务记录

| ID | 描述 | 严重性 | 计划修复 |
|----|------|--------|---------|
| TD-01 | binance-sdk WS 层需自实现 (官方有已知 bug) | 高 | Phase 1 即自实现 |
| TD-02 | kand 部分指标标记 Unstable，需交叉验证 | 中 | Phase 3 时验证 |
| TD-03 | genai 0.6.x 为 beta 版，API 可能变更 | 中 | 锁定版本，及时跟进 |
| TD-04 | Twitter API 免费版额度极低 (100/月) | 高 | 文档中明确说明限制 |
| TD-05 | LanceDB 大规模时内存泄漏 | 低 | 桌面级可忽略，Phase 4 验证 |
| TD-06 | fastembed ONNX Runtime 首次下载依赖网络 | 中 | 启动时显示加载进度 |
