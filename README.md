# CryptoQuant - AI 驱动的加密货币量化看板

基于 **Tauri 2.x + Rust + React** 的跨平台桌面量化工具，集成 LLM Agent、RAG 资讯聚合、多数据源分析。

## 核心理念

> **AI 是军师，不是将军。** 所有分析、搜索、归纳由 AI 完成；所有交易决策权保留在人和规则引擎手中。

## 功能

- **交易看板**：K 线图（Lightweight Charts）、订单簿深度、实时价格行情
- **多币种资讯流**：新闻、推文、链上数据实时聚合，按币种筛选
- **AI 对话分析**：自然语言交互，AI 自动搜索/分析/总结（类似 Cursor 交互模式）
- **多数据源 RAG**：NewsAPI + Twitter/X + Whale Alert + Etherscan 自动向量化检索
- **本地运行**：所有数据存储、向量搜索、嵌入模型本地执行，无需云端

## 技术栈

| 层 | 技术 |
|----|------|
| 桌面壳 | Tauri 2.x (Rust) |
| 前端 | React 18 + TypeScript + Tailwind CSS + shadcn/ui |
| 状态管理 | Zustand |
| 图表 | Lightweight Charts v4 (TradingView) |
| 后端 | Rust (集成在 Tauri 内) |
| 交易所数据 | `binance-sdk` (官方 Rust SDK) |
| 技术指标 | `kand` (50+ 指标, O(1) 增量计算) |
| 向量数据库 | `lancedb` (嵌入式, 无服务) |
| 本地嵌入 | `fastembed` (ONNX, 30+ 模型) |
| LLM 客户端 | `genai` (20+ 提供商统一 API) + `ollama-rs` (本地) |
| 数据采集 | `reqwest` + `serde` (新闻/Twitter/链上) |
| 异步运行时 | `tokio` |

## 架构概览

```
┌─────────────────────────────────────────────┐
│                Tauri Shell (Rust)            │
│  ┌─────────────────┐  ┌──────────────────┐  │
│  │  React 前端      │  │  Rust 后端逻辑    │  │
│  │  - 看板 UI       │  │  - Binance 数据   │  │
│  │  - 对话界面      │  │  - TA 指标计算    │  │
│  │  - 资讯流        │  │  - RAG 引擎       │  │
│  │                  │  │  - Agent 循环     │  │
│  └────────┬─────────┘  │  - LLM 调用       │  │
│           │ IPC         │  - 数据采集       │  │
│           └─────────────┤                  │  │
│                         └──────────────────┘  │
└─────────────────────────────────────────────┘
```

## 界面布局

```
┌──────────────────────────────┬─────────────────────────────┐
│  左侧 (~60%)                 │  右侧 (~40%)                 │
│  ┌────────────────────────┐  │  ┌───────────────────────┐  │
│  │ 币种切换 [BTC][ETH]...  │  │  │ AI 对话历史            │  │
│  └────────────────────────┘  │  │ "分析BTC最近走势..."   │  │
│  ┌────────────────────────┐  │  │ AI: 正在搜索新闻...    │  │
│  │ K线图 + 指标叠加        │  │  │ AI: [分析报告卡片]     │  │
│  │ (Lightweight Charts)   │  │  │                       │  │
│  ├────────────────────────┤  │  │                       │  │
│  │ 订单簿 (买/卖盘口)     │  │  │                       │  │
│  ├────────────────────────┤  │  ├───────────────────────┤  │
│  │ 资讯流 (新闻/推文/链上) │  │  │ 输入框 [发送]          │  │
│  └────────────────────────┘  │  └───────────────────────┘  │
└──────────────────────────────┴─────────────────────────────┘
```

## 快速开始

### 前置依赖

- Rust 1.78+
- Node.js 20+
- ONNX Runtime (fastembed 运行时自动下载)

### 安装

```bash
git clone https://github.com/yourname/crypto-quant-tool
cd crypto-quant-tool
npm install
```

### 开发

```bash
npm run tauri dev
```

### 构建

```bash
npm run tauri build
```

## 配置

用户需在设置页面配置以下 API Key（至少配置前两项）：

| API | 用途 | 获取地址 |
|-----|------|---------|
| LLM API Key | AI 对话分析 | [OpenAI](https://platform.openai.com) / [Anthropic](https://console.anthropic.com) |
| Binance API Key | 交易所数据 | [Binance API管理](https://www.binance.com/en/my/settings/api-management) |
| NewsAPI Key | 新闻采集 | [NewsAPI.org](https://newsapi.org/register) |
| Twitter API Key | 推文采集 | [Twitter Developer](https://developer.twitter.com) |
| Etherscan API Key | 链上数据 | [Etherscan](https://etherscan.io/apis) |

所有密钥通过 OS Keychain 安全存储，不上传，不记录日志。

## 项目结构

```
crypto-quant-tool/
├── src/                    # React 前端
│   ├── components/         # UI 组件
│   │   ├── layout/         # 左右分栏布局
│   │   ├── symbol/         # 币种切换
│   │   ├── chart/          # K线图表
│   │   ├── feed/           # 资讯流
│   │   ├── chat/           # AI 对话
│   │   └── settings/       # 设置页面
│   ├── stores/             # Zustand 状态管理
│   ├── hooks/              # 自定义 Hooks
│   ├── lib/                # 工具函数
│   └── styles/             # 全局样式
├── src-tauri/              # Tauri Rust 后端
│   └── src/
│       ├── main.rs         # 入口
│       ├── binance/        # Binance 接口封装
│       ├── indicators/     # 技术指标计算
│       ├── rag/            # RAG 检索增强生成
│       ├── agent/          # LLM Agent 循环
│       ├── data_sources/   # 新闻/推文/链上采集
│       └── commands/       # Tauri IPC Commands
└── docs/                   # 设计文档
    ├── ARCHITECTURE.md     # 架构设计
    ├── TECH_STACK.md       # 技术选型
    ├── IMPLEMENTATION.md   # 模块实现细节
    ├── MVP_PLAN.md         # MVP 阶段规划
    ├── TODO.md             # 任务清单
    ├── DATA_FLOW.md        # 数据流设计
    ├── RAG_DESIGN.md       # RAG 管道设计
    ├── AGENT_LOOP.md       # Agent 循环设计
    └── SETUP.md            # 开发环境搭建
```

## 安全声明

- 所有 API 密钥存储在操作系统原生 Keychain 中（macOS Keychain / Windows Credential Manager / Linux Secret Service）
- 不包含任何硬编码密钥或默认端点
- 不包含任何遥测、埋点或数据上报
- AI 输出仅供分析参考，不自动执行交易

## 许可证

MIT
