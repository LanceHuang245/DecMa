[English](README.md) | 简体中文

# DecMa

DecMa 是一个 Flutter 桌面端的**只读加密货币永续合约分析看板**。它将 Bybit Linear 实时行情与由 LLM 驱动的交易分析 Agent 结合起来。Agent 可生成决策摘要及候选开仓区、止损和止盈位置；DecMa 不会下单、修改订单或撤单。

## 功能

- 实时搜索 Bybit Linear 合约并查看 K 线图。支持 1 分钟、5 分钟、15 分钟、1 小时、4 小时和日线周期，最新 K 线每秒刷新。
- 基于 Fluent UI 的桌面看板；当分析结果可解析时，在图表上标记开仓区、止损和止盈价位。
- 两种 Agent 模式：市场分析和带上下文的对话。
- 可配置 Anthropic Messages、OpenAI Responses 和 OpenAI Chat Completions 兼容接口的 LLM 传输协议。
- 可选数据源：
  - **Bybit MCP**：公共、只读市场数据。
  - **OpenWebSearch MCP**：新闻和官方来源发现。
  - **Nansen MCP**：链上背景信息。
  - **Coinalyze API**：衍生品历史数据、资金费率、未平仓量、爆仓和多空比数据。
- API 密钥使用 `flutter_secure_storage` 保存；接口地址、模型和数据源开关与密钥分开保存。
- Agent 提示词优先使用实时工具数据，允许给出 `WAIT`/`NO_TRADE`，要求披露风险和数据质量，并禁止执行交易。

## 环境要求

- Flutter SDK，Dart 版本为 `^3.12.2`。
- 一个 Flutter 桌面端目标（Windows、macOS 或 Linux）。
- LLM API Key，以及支持所选协议的模型。
- 如需使用内置的 Bybit MCP 和 OpenWebSearch MCP，需要安装 Node.js 与 `npx`。内置图表、Nansen MCP 和 Coinalyze API 不依赖 Node.js。
- 启用 Nansen 和 Coinalyze 时，分别需要对应的可选 API Key。

首次请求 MCP 时，`npx` 可能会下载相应的软件包，因此需要网络访问。

## 快速开始

```bash
# Fetch Flutter dependencies.
flutter pub get

# Run the desktop target for this machine.
flutter run -d windows
```

请按实际系统将 `windows` 替换为 `macos` 或 `linux`。

## 配置 Agent

1. 启动应用后，选择 **设置**。
2. 选择 LLM 协议，填写接口地址、模型和 API Key。默认接口地址如下：

   | 协议 | 默认接口地址 | DecMa 自动追加的请求路径 |
   | --- | --- | --- |
   | Anthropic Messages | `https://api.anthropic.com` | `/v1/messages` |
   | OpenAI Responses | `https://api.openai.com/v1` | `/responses` |
   | OpenAI Chat Completions | `https://api.openai.com/v1` | `/chat/completions` |

3. 仅启用需要的数据源：
   - Bybit MCP 和 OpenWebSearch MCP 默认启用，二者需要 Node.js 和 `npx`。
   - Nansen MCP 需要 Nansen API Key。
   - Coinalyze 需要 Coinalyze API Key；它默认关闭，并在本地限制为每分钟最多 40 个请求单位。
4. 保存设置。保留密钥输入框中的掩码文本不变，即会继续使用设备上已保存的密钥。

## 使用 DecMa

1. 搜索 `BTCUSDT` 等 Bybit Linear 合约，并选择图表周期。
2. 在 **分析** 模式中描述要分析的市场，或点击 **分析当前合约**。
3. 查看 Agent 的 Markdown 报告、警告信息和图表价位。仅当响应识别出的币种与当前图表币种一致时，系统才绘制解析后的交易计划。
4. 在 **对话** 模式中继续提问。对话上下文只保留在当前应用会话中，可在看板中清空。

## 数据源与限制

| 数据源 | 在 DecMa 中的用途 | 说明 |
| --- | --- | --- |
| Bybit 公共 API | 合约列表和图表 OHLCV 数据 | 不使用 Bybit 账户凭证。 |
| Bybit MCP | 更多公共市场事实 | DecMa 仅保留明确公开、只读的工具。 |
| OpenWebSearch MCP | 事件与官方来源发现 | 搜索结果只是线索，而非已验证事实。 |
| Nansen MCP | 链上与聪明钱背景 | 可选，需要独立 API Key。 |
| Coinalyze API | 跨市场衍生品背景 | 可选，不会替代同一时刻的 Bybit 场内数据。 |

Agent 指令将 Bybit 作为 Bybit 价格、标记价/指数价、订单簿、资金费率和未平仓量的主要来源。如所需数据缺失、过期或冲突，预期结果应是审慎的 `WAIT`、`NO_TRADE` 或 `DATA_INSUFFICIENT`。

## 项目结构

```text
lib/
├── main.dart                         # App and desktop-window startup
├── models/trading_models.dart         # Settings, candle, and trade-plan models
├── services/                          # LLM, market-data, MCP, and secure-key services
└── ui/
    ├── dashboard/                     # Chart and agent panels
    ├── chart/                         # Candlestick rendering and viewport logic
    └── settings/                      # Agent configuration dialog
```

## 重要提示

DecMa 是分析和决策辅助工具，不构成投资建议，也不是交易执行系统。行情、网页内容和 LLM 输出都可能不完整、延迟或错误。请独立核实信息、管理风险，并自行作出交易决策。
