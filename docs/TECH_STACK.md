# 技术选型文档 (TECH_STACK)

## 选型原则

1. **全 Rust 后端**：单一语言栈，无 GC 停顿，确定性延迟，静态编译
2. **嵌入式优先**：能本地跑的服务绝不依赖外部进程（LanceDB 代替 Qdrant/Docker）
3. **官方 SDK 优先**：Binance 官方 > 社区维护
4. **O(1) 增量计算**：技术指标支持实时流式更新而非批量重算
5. **统一 LLM 接口**：支持 OpenAI/Anthropic/Ollama 等切换

## 依赖清单

### Rust 核心依赖 (src-tauri/Cargo.toml)

```toml
[dependencies]
# Tauri 框架
tauri = { version = "2", features = ["unstable"] }
tauri-plugin-shell = "2"

# 交易所
binance-sdk = { version = "46", features = ["full"] }

# 技术指标
kand = "0.2"

# 向量数据库
lancedb = "0.27"

# 本地嵌入
fastembed = "5"

# LLM 统一接口
genai = "0.6"

# 本地 LLM
ollama-rs = "0.3"

# 异步运行时
tokio = { version = "1", features = ["full"] }

# HTTP 客户端
reqwest = { version = "0.12", features = ["json", "stream"] }

# WebSocket (自实现 Binance WS 层)
tokio-tungstenite = "0.24"

# 序列化
serde = { version = "1", features = ["derive"] }
serde_json = "1"

# 时间
chrono = { version = "0.4", features = ["serde"] }

# 日志
tracing = "0.1"
tracing-subscriber = "0.3"

# 密钥管理 (跨平台 Keychain)
keyring = "3"

# 错误处理
thiserror = "2"
anyhow = "1"

# UUID 生成
uuid = { version = "1", features = ["v4"] }

# 文本分块
text-splitter = "0.18"

# RSS/Atom 订阅解析
feed-rs = "2"

# 并发数据结构
dashmap = "6"
parking_lot = "0.12"
```

### 前端依赖 (package.json)

```json
{
  "dependencies": {
    "react": "^18.3.0",
    "react-dom": "^18.3.0",
    "@tauri-apps/api": "^2.0.0",
    "@tauri-apps/plugin-shell": "^2.0.0",
    "zustand": "^5.0.0",
    "lightweight-charts": "^4.2.0",
    "lucide-react": "^0.460.0",
    "clsx": "^2.1.0",
    "tailwind-merge": "^2.5.0"
  },
  "devDependencies": {
    "typescript": "^5.6.0",
    "@types/react": "^18.3.0",
    "@types/react-dom": "^18.3.0",
    "vite": "^6.0.0",
    "@vitejs/plugin-react": "^4.3.0",
    "tailwindcss": "^3.4.0",
    "postcss": "^8.4.0",
    "autoprefixer": "^10.4.0",
    "@tauri-apps/cli": "^2.0.0"
  }
}
```

## 核心 Libraries 详细评估

### 1. binance-sdk (v46)

| 维度 | 说明 |
|------|------|
| 维护者 | Binance 官方 |
| 覆盖面 | Spot + USDS-M + COIN-M + 期权 + 保证金 + 质押 |
| REST 可靠性 | 🟢 生产级 |
| WebSocket 可靠性 | 🟡 有已知 bug (#85, #25)，需自实现 WS 层 |
| 日志大小 | ~13MB 代码，216K 行 |
| 使用策略 | REST 部分直接使用；WebSocket 用 `tokio-tungstenite` 自实现 |

**自实现 WS 层的理由**：
- 官方 SDK 的 WebSocket 在长时运行后连接超时
- 重连逻辑不符合 Binance 的频率限制要求
- 多流合并（Combined Streams）需要自定义 buffer 策略

### 2. kand (v0.2)

| 维度 | 说明 |
|------|------|
| 指标数量 | 50+ (SMA, EMA, MACD, RSI, BB, OBV, ADX, ATR, SAR, VWAP, Supertrend...) |
| 计算模式 | O(1) 增量更新（流式友好） |
| 成熟度 | ⚠️ 0.2 版本，部分指标标记 Untested/Unstable |
| 替代方案 | `ta` crate (停滞 4 年，仅 ~18 个指标) |

**使用策略**：
- 优先使用 `kand` 的已验证指标（SMA, EMA, RSI, MACD）
- 对标记 `[Unstable]` 的指标（VEGAS 等），交叉验证后使用
- 缺失指标（Sharpe, Sortino, Drawdown）手写实现

### 3. lancedb (v0.27)

| 维度 | 说明 |
|------|------|
| 运行模式 | 嵌入式（进程内），无服务 |
| 存储后端 | Lance (列式) + Arrow |
| 检索延迟 | <1ms @ 1M 128D 向量 |
| 搜索方式 | 向量搜索 + 全文搜索 + SQL |
| 已知问题 | 大规模(>100M)时内存泄漏，桌面级(1M-10M)无影响 |
| 替代方案 | `qdrant-client` (需部署服务), `chromadb` (Rust 客户端不成熟) |

**使用策略**：
- 桌面场景向量量级 < 10M，LanceDB 完全胜任
- 数据持久化到 `$APP_DATA/lancedb/`
- 定期运行 `optimize()` 清理版本历史

### 4. fastembed (v5)

| 维度 | 说明 |
|------|------|
| 模型数量 | 30+ (BGE, all-MiniLM, nomic-embed, Jina, Qwen3...) |
| 推理引擎 | ONNX Runtime |
| 下载量 | 235K/月 |
| 默认模型 | `BAAI/bge-small-en-v1.5` (384维, 133MB) |
| 离线 | 首次下载后缓存，后续本地运行 |

**使用策略**：
- 默认用 `all-MiniLM-L6-v2` (384维, 80MB, 平衡速度与质量)
- 中文场景可选 `BAAI/bge-small-zh-v1.5`
- 通过 `fastembed::TextEmbedding::try_new()` 初始化

### 5. genai (v0.6)

| 维度 | 说明 |
|------|------|
| 提供商 | OpenAI, Anthropic, Gemini, Groq, DeepSeek, Ollama, xAI, Cohere 等 20+ |
| 统一 API | `genai::Client` → `client.exec_chat()` |
| 流式输出 | `ChatStream` 迭代器 |
| 成熟度 | ⚠️ Beta (0.6.0-beta.18) |
| 替代方案 | `async-openai` (650K 下载, 仅 OpenAI), `ollama-rs` (仅 Ollama) |

**使用策略**：
- `genai` 作为主接口（多提供商切换）
- `ollama-rs` 作为本地 LLM 补充
- 构建时禁用不需要的提供商 feature 以减小二进制体积

### 6. text-splitter (v0.18)

| 维度 | 说明 |
|------|------|
| 分割方式 | 递归字符分割 + Token 分割 |
| 支持 Tokenizer | tiktoken (OpenAI), HuggingFace Tokenizers |
| 下载量 | ~50K |
| 成熟度 | 中等，功能简单够用 |

**使用策略**：
- chunk_size = 512 tokens
- chunk_overlap = 50 tokens
- 按 `\n\n` → `\n` → `.` → ` ` 逐级分割

## 技术风险矩阵

| 风险项 | 严重性 | 概率 | 缓解措施 |
|--------|--------|------|----------|
| binance-sdk WS 不可靠 | 高 | 高 | 自实现 WS 层 |
| kand 指标计算错误 | 中 | 中 | 交叉验证 + 社区反馈 |
| genai breaking change | 中 | 高 | 锁定版本 + 立即跟进 |
| LanceDB 内存泄漏 | 低 | 低 | 桌面量级无影响 + 定期 optimize |
| fastembed ONNX 兼容性 | 中 | 低 | 锁定 ONNX Runtime 版本 |
| 编译时间过长 | 低 | 高 | 增量编译 + workspace 拆分 |
