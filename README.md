English | [简体中文](README_CN.md)

# DecMa

DecMa is a Flutter desktop dashboard for **read-only cryptocurrency perpetual-contract analysis**. It combines live Bybit Linear market data with an LLM-driven trading-analysis agent. The agent can produce a decision brief and candidate entry, stop-loss, and take-profit levels; DecMa never places, changes, or cancels orders.

## Features

- Live Bybit Linear contract search and candlestick charts. Choose 1m, 5m, 15m, 1h, 4h, or 1D intervals; the chart refreshes its latest candles every second.
- A Fluent UI desktop dashboard with chart overlays for an accepted analysis plan's entry area, stop loss, and take-profit levels.
- Two agent modes: market analysis and contextual conversation.
- Configurable LLM transports for Anthropic Messages, OpenAI Responses, and OpenAI Chat Completions-compatible endpoints.
- Optional data sources:
  - **Bybit MCP** for public, read-only market data.
  - **OpenWebSearch MCP** for news and official-source discovery.
  - **Nansen MCP** for on-chain context.
  - **Coinalyze API** for derivatives history, funding, open interest, liquidations, and long/short-ratio data.
- API keys are stored with `flutter_secure_storage`; endpoint, model, and source-toggle settings are stored separately.
- Guardrails in the agent prompt prioritize live tool results, allow `WAIT`/`NO_TRADE` outcomes, require risk and data-quality disclosures, and prohibit trade execution.

## Requirements

- Flutter SDK with Dart `^3.12.2`.
- A desktop Flutter target (Windows, macOS, or Linux).
- An LLM API key and a model that supports the selected provider protocol.
- Node.js and `npx` to use the bundled Bybit MCP and OpenWebSearch MCP integrations. They are not needed for the built-in chart, Nansen MCP, or Coinalyze API.
- Optional Nansen and Coinalyze API keys when enabling those sources.

The first MCP request can download the corresponding `npx` package, so it requires network access.

## Quick start

```bash
# Fetch the Flutter packages.
flutter pub get

# Run the desktop target that matches your machine.
flutter run -d windows
```

Replace `windows` with `macos` or `linux` where appropriate.

## Configure the agent

1. Start the app and select **设置** (Settings).
2. Choose an LLM protocol, then enter its endpoint, model, and API key. The default endpoints are:

   | Protocol | Default endpoint | Request path added by DecMa |
   | --- | --- | --- |
   | Anthropic Messages | `https://api.anthropic.com` | `/v1/messages` |
   | OpenAI Responses | `https://api.openai.com/v1` | `/responses` |
   | OpenAI Chat Completions | `https://api.openai.com/v1` | `/chat/completions` |

3. Enable only the sources you want:
   - Bybit MCP and OpenWebSearch MCP are enabled by default and require Node.js plus `npx`.
   - Nansen MCP requires a Nansen API key.
   - Coinalyze requires a Coinalyze API key; it starts disabled and has a local guard for its 40-request-per-minute quota.
4. Save the settings. Leaving a masked key field unchanged preserves the key already stored on the device.

## Use DecMa

1. Search for a Bybit Linear symbol such as `BTCUSDT` and choose a chart interval.
2. In **分析** (Analysis) mode, describe the market or press **分析当前合约** (Analyze current contract).
3. Review the agent's Markdown report, warnings, and any chart levels. A parsed plan is drawn only when the response identifies the same active symbol.
4. Use **对话** (Conversation) mode for follow-up questions. Conversation context is retained only for the current app session and can be cleared from the dashboard.

## Data sources and limits

| Source | Purpose in DecMa | Notes |
| --- | --- | --- |
| Bybit public API | Symbol list and displayed OHLCV chart | No Bybit account credentials are used. |
| Bybit MCP | Additional public market facts | DecMa filters the server to explicitly public, read-only tools. |
| OpenWebSearch MCP | Event and official-source discovery | Search results are leads, not verified facts. |
| Nansen MCP | On-chain and smart-money context | Optional; requires its own API key. |
| Coinalyze API | Cross-market derivatives context | Optional; does not replace contemporaneous Bybit venue data. |

The app's agent instructions treat Bybit as the primary source for Bybit price, mark/index price, order book, funding, and open interest. If required data is unavailable, stale, or conflicted, the intended outcome is a cautious `WAIT`, `NO_TRADE`, or `DATA_INSUFFICIENT` result.

## Project layout

```text
lib/
├── main.dart                         # Application and desktop-window startup
├── models/trading_models.dart         # Settings, candle, and trade-plan models
├── services/                          # LLM, market-data, MCP, and secure-key services
└── ui/
    ├── dashboard/                     # Chart and agent panels
    ├── chart/                         # Candlestick rendering and viewport logic
    └── settings/                      # Agent configuration dialog
```

## Important notice

DecMa is an analysis and decision-support tool, not investment advice or an execution system. Market data, web content, and LLM outputs can be incomplete, delayed, or wrong. Verify information independently, manage risk, and make your own trading decisions.
