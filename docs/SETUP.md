# 开发环境搭建 (SETUP)

## 系统要求

| 平台 | 最低要求 |
|------|---------|
| macOS | 12.0+ (Monterey), Apple Silicon 或 Intel |
| Windows | 10+ (64-bit), MSVC Build Tools |
| Linux | Ubuntu 22.04+ / Debian 12+ / Fedora 38+ |

## 前置依赖

### 1. Rust

```bash
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh

# 验证
rustc --version   # >= 1.78.0
cargo --version   # >= 1.78.0

# 添加 wasm target (Tauri 2.x 不再需要, 但保留以防万一)
rustup target add wasm32-unknown-unknown
```

### 2. Node.js

```bash
# 推荐使用 fnm 管理版本
curl -fsSL https://fnm.vercel.app/install | bash
fnm install 20
fnm use 20

# 验证
node --version    # >= 20.0.0
npm --version     # >= 10.0.0
```

### 3. 系统依赖

#### macOS
```bash
xcode-select --install  # Command Line Tools

# Tauri 2.x 不需要额外的系统包
```

#### Windows
```powershell
# 1. 安装 Microsoft Visual C++ Build Tools
#    https://visualstudio.microsoft.com/visual-cpp-build-tools/
#    选择 "Desktop development with C++"

# 2. 安装 WebView2 (Windows 10 通常已预装)
#    https://developer.microsoft.com/en-us/microsoft-edge/webview2/
```

#### Linux (Ubuntu/Debian)
```bash
sudo apt update
sudo apt install -y \
    libwebkit2gtk-4.1-dev \
    build-essential \
    curl \
    wget \
    file \
    libxdo-dev \
    libssl-dev \
    libayatana-appindicator3-dev \
    librsvg2-dev \
    libclang-dev \
    cmake \
    protobuf-compiler  # lancedb/arrow 需要
```

#### Linux (Fedora)
```bash
sudo dnf install -y \
    webkit2gtk4.1-devel \
    openssl-devel \
    libappindicator-gtk3-devel \
    librsvg2-devel \
    clang-devel \
    cmake \
    protobuf-compiler
```

---

## 快速开始

### 1. 克隆项目

```bash
git clone https://github.com/yourname/crypto-quant-tool
cd crypto-quant-tool
```

### 2. 安装前端依赖

```bash
npm install
```

### 3. 编译 Rust 后端 (首次构建较慢)

```bash
cargo build --manifest-path src-tauri/Cargo.toml
# 首次编译可能需要 5-10 分钟 (binance-sdk 代码量较大)
```

### 4. 启动开发模式

```bash
npm run tauri dev
```

Tauri 会自动：
1. 启动 Vite 开发服务器 (前端热更新)
2. 编译并启动 Rust 后端
3. 打开桌面窗口

### 5. 配置

首次启动后，进入设置页面配置至少以下两项：
- **LLM API Key** (OpenAI 或 Anthropic)
- **Binance API Key** (可选，用于查看更多市场数据)

---

## 项目脚本

```bash
# 开发
npm run tauri dev          # 启动开发模式 (带热更新)
npm run dev                # 仅启动前端 (不带 Tauri)

# 类型检查
npm run typecheck          # tsc --noEmit

# 代码检查
npm run lint               # ESLint

# Rust 检查
cargo check --manifest-path src-tauri/Cargo.toml
cargo clippy --manifest-path src-tauri/Cargo.toml

# 构建
npm run tauri build        # 生产构建
npm run tauri build -- --debug  # 带调试信息的构建

# 测试 (占位)
cargo test --manifest-path src-tauri/Cargo.toml
npm run test               # 前端测试 (vitest)
```

---

## 目录结构

```
crypto-quant-tool/
├── src/                         # React 前端
│   ├── main.tsx                 # 入口
│   ├── App.tsx                  # 根组件
│   ├── App.css
│   ├── components/
│   │   ├── layout/              # 布局组件
│   │   │   ├── AppLayout.tsx    # 左右分栏根布局
│   │   │   ├── LeftPanel.tsx
│   │   │   ├── RightPanel.tsx
│   │   │   └── ResizeHandle.tsx
│   │   ├── symbol/
│   │   │   └── SymbolSelector.tsx
│   │   ├── chart/
│   │   │   ├── KLineChart.tsx
│   │   │   ├── ChartToolbar.tsx
│   │   │   └── OrderBook.tsx
│   │   ├── feed/
│   │   │   ├── NewsFeed.tsx
│   │   │   ├── FeedItem.tsx
│   │   │   └── FeedFilter.tsx
│   │   ├── chat/
│   │   │   ├── ChatPanel.tsx
│   │   │   ├── ChatHistory.tsx
│   │   │   ├── UserMessage.tsx
│   │   │   ├── AssistantMessage.tsx
│   │   │   ├── ToolCallBlock.tsx
│   │   │   ├── AnalysisCard.tsx
│   │   │   └── ChatInput.tsx
│   │   └── settings/
│   │       └── SettingsPage.tsx
│   ├── stores/                  # Zustand 状态管理
│   │   ├── useSymbolStore.ts
│   │   ├── useMarketStore.ts
│   │   ├── useFeedStore.ts
│   │   ├── useChatStore.ts
│   │   └── useSettingsStore.ts
│   ├── hooks/                   # 自定义 Hooks
│   │   ├── useBinanceWs.ts
│   │   ├── useChatStream.ts
│   │   └── useResizeHandle.ts
│   ├── lib/                     # 工具函数
│   │   ├── chart.ts             # Lightweight Charts 封装
│   │   ├── format.ts            # 数字/时间格式化
│   │   └── eventBus.ts
│   └── styles/
│       └── globals.css          # Tailwind + 暗色主题
│
├── src-tauri/                   # Tauri Rust 后端
│   ├── Cargo.toml
│   ├── tauri.conf.json
│   ├── capabilities/
│   │   └── default.json
│   ├── icons/
│   └── src/
│       ├── main.rs              # 入口 + AppState
│       ├── binance/
│       │   ├── mod.rs
│       │   ├── types.rs
│       │   ├── rest.rs
│       │   └── ws.rs
│       ├── indicators/
│       │   ├── mod.rs
│       │   ├── ma.rs
│       │   ├── macd.rs
│       │   ├── rsi.rs
│       │   └── bollinger.rs
│       ├── rag/
│       │   ├── mod.rs
│       │   ├── collector.rs
│       │   ├── chunker.rs
│       │   ├── embedder.rs
│       │   ├── store.rs
│       │   └── retriever.rs
│       ├── agent/
│       │   ├── mod.rs
│       │   ├── loop.rs
│       │   ├── tools.rs
│       │   └── prompt.rs
│       ├── data_sources/
│       │   ├── mod.rs
│       │   ├── news.rs
│       │   ├── twitter.rs
│       │   └── onchain.rs
│       └── commands/
│           └── mod.rs
│
├── docs/                        # 设计文档
│   ├── ARCHITECTURE.md
│   ├── TECH_STACK.md
│   ├── IMPLEMENTATION.md
│   ├── MVP_PLAN.md
│   ├── TODO.md
│   ├── DATA_FLOW.md
│   ├── RAG_DESIGN.md
│   ├── AGENT_LOOP.md
│   └── SETUP.md
│
├── package.json
├── tsconfig.json
├── vite.config.ts
├── tailwind.config.ts
├── postcss.config.js
└── index.html
```

---

## VS Code 推荐插件

```json
{
  "recommendations": [
    "tauri-apps.tauri-vscode",
    "rust-lang.rust-analyzer",
    "vadimcn.vscode-lldb",
    "bradlc.vscode-tailwindcss",
    "dbaeumer.vscode-eslint",
    "esbenp.prettier-vscode"
  ]
}
```

### 调试配置 (`.vscode/launch.json`)

```json
{
  "version": "0.2.0",
  "configurations": [
    {
      "type": "lldb",
      "request": "launch",
      "name": "Tauri Development Debug",
      "cargo": {
        "args": ["build", "--manifest-path=./src-tauri/Cargo.toml", "--no-default-features"]
      },
      "env": {
        "TAURI_DEV": "true"
      },
      "preLaunchTask": "ui:dev"
    }
  ]
}
```

---

## 常见问题

### Q: Rust 编译失败 "failed to run custom build command for `openssl-sys`"
```bash
# Ubuntu/Debian
sudo apt install libssl-dev

# macOS
brew install openssl

# 或使用 rustls 替代 openssl
# 在 Cargo.toml 中: reqwest = { version = "0.12", default-features = false, features = ["rustls-tls"] }
```

### Q: Tauri 窗口无法打开 (Linux)
```bash
# 确保安装了 webkit2gtk
sudo apt install libwebkit2gtk-4.1-dev libjavascriptcoregtk-4.1-dev

# Wayland 环境可能需要:
export WEBKIT_DISABLE_COMPOSITING_MODE=1
```

### Q: fastembed 首次启动下载模型失败
```
# 手动下载模型放入缓存目录
# macOS: ~/Library/Caches/crypto-quant-tool/models/
# Linux: ~/.cache/crypto-quant-tool/models/
# Windows: %LOCALAPPDATA%/crypto-quant-tool/models/

# 模型 URL: https://huggingface.co/sentence-transformers/all-MiniLM-L6-v2
```

### Q: binance-sdk 编译时间过长
```
cargo build 时 binance-sdk 的编译是最慢的部分。
开发阶段建议:
1. 使用 cargo check 代替 cargo build (不生成二进制)
2. 开启增量编译: 在 Cargo.toml [profile.dev] 设置 incremental = true
3. 使用 sccache: https://github.com/mozilla/sccache
```
