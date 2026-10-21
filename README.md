English | [简体中文](README_CN.md)

# DecMa

DecMa is a Flutter desktop workspace for read-only Bybit Linear perpetual-market analysis. It combines a live chart, curated market news, deterministic market features, optional external data tools, and an LLM agent in one interface. It can present candidate entry, stop-loss, and take-profit levels, but it never places, amends, or cancels orders.

## Screenshots

### Workspace

The three-column workspace keeps the chart, market-news feed, and agent response visible together.

![DecMa workspace with chart, market news, and Trading Agent](assets/img/Main.png)

### One-click analysis

Select a token and click Analyze current contract. The connected LLM explains whether to favor long, short, or waiting at the current price; no account, leverage, or fee form is required.


### Agent and data-source settings

Save multiple LLM connections, sign in to OpenAI Codex when selected, and enable only the MCP and API sources you need.

![Agent settings dialog](assets/img/AgentSettings.png)

### Market-news settings

Control official macro feeds and optional Finnhub and Marketaux news sources separately.

![Market News settings dialog](assets/img/NewsSettings.png)

## Features

- Search Bybit Linear perpetual symbols and view 1m, 5m, 15m, 1h, 4h, or 1D candlestick charts. The application loads up to 1,000 candles and refreshes the latest candles every second.
- View the chart, a filterable market-news feed, and the Trading Agent side by side in a Fluent UI desktop workspace.
- Run structured market analysis and ask follow-up questions in the same input. Previous-analysis context is kept only for the current application session.
- Build each analysis from a current Bybit market snapshot and calculated 5m, 15m, 1h, and 4h features, including EMA, MACD, RSI, ATR, VWAP, realized volatility, volume, and range-expansion metrics.
- Validate the model's structured plan before drawing its entry zone, stop loss, and take-profit levels on the active chart. Plans for another symbol or invalid price relationships are not drawn.
- Choose from Anthropic Messages, OpenAI Responses, OpenAI Chat Completions-compatible endpoints, or OpenAI Codex. Multiple named LLM connections can be saved; the Codex option uses a browser sign-in flow.
- Use optional analysis sources: Bybit MCP, OpenWebSearch MCP, Nansen MCP, and the Coinalyze API. The Bybit MCP integration exposes only explicitly public, read-only operations.
- With OpenWebSearch enabled, the agent can reuse seven-day project-background context and research current catalysts, checking original sources for strategy-relevant events. Unavailable web research does not block price-based analysis.
- Read macro and market-news feeds from BLS, BEA, and the Federal Reserve by default, with optional Finnhub and Marketaux sources. The feed can be filtered by current asset, category, and provider.
- Store API keys and OAuth credentials with `flutter_secure_storage`; non-secret settings, cached events, saved asset profiles, and the last viewed symbol are stored separately.
- Keep analysis conservative when data is missing, stale, or conflicting: the agent may return `WAIT`, `NO_TRADE`, or `DATA_INSUFFICIENT` and cannot execute trades.

## Current opportunity checks

Select a token, click **分析当前合约**, and read the direction and immediate next action. There is no first-use risk setup. After analysis, reference prices are refreshed automatically. An unentered plan that already reached TP1 is marked as missed; a chase-limit violation waits for a new confirmation after a pullback.

Machine-readable fields stay behind the chart and checks. Bybit reference data does not verify execution on other venues. `PlanConditions` serialization is generated with `dart run build_runner build`. Only plans and assessment-state changes are saved, with at most 300 evidence records. Entry triggers use native 5m/15m/1h/4h candles; one-minute candles check whether the opportunity has already reached its target or invalidation price. Plans expire after three trigger periods or an earlier explicit expiry. Auxiliary allocation/precision warnings retain reference prices, and the chart displays up to three targets.

## Code organization

- `lib/data/services/`: external APIs, LLM/MCP adapters, and local storage.
- `lib/data/repositories/`: news refresh/cache coordination and asset resolution.
- `lib/domain/models/`: settings, market data, news, and trade-plan models.
- `lib/domain/analysis/` and `lib/domain/news/`: deterministic calculations, validation, and event selection.
- `lib/ui/`: Fluent UI features and their state owners. Market and news controllers own their polling and cancellation; the dashboard coordinates analysis.
- `lib/providers/`: service construction and lifecycle management.
- `test/`: tests grouped by layer/feature, with shared helpers in `test/fixtures/`.

## Reference entry assessment

- Closed-bar features include KDJ (9/3/3), ADX/DMI, Bollinger bandwidth and percentile, RSI changes, and prior structure levels. All values are serialized into the analysis context; correlated price indicators are not independent votes.
- Optional public Bybit OI history supplies 15-minute and one-hour changes without blocking core price analysis on failure.
- Entry checks use Ask for longs and Bid for shorts, with a minimum reference net reward/risk of 1:1 to TP1 and a cost-adjusted chase boundary. The public scenario uses 0.055% taker fees per leg, adverse half-spread at exit, and payable funding over three hours. It excludes size-dependent market impact and is not a personal cost estimate.
- Breakout/retest requires separate closed candles. Range reentry must touch its directional boundary. Volume alone cannot approve entry; a cost pause requires a new trigger after recovery.

## Requirements

- Flutter SDK with Dart `^3.12.2`.
- A Flutter desktop target: Windows, macOS, or Linux.
- An LLM API key and model for Anthropic Messages, OpenAI Responses, or OpenAI Chat Completions; alternatively, a ChatGPT account for the OpenAI Codex sign-in option.
- Node.js and `npx` when using the bundled Bybit MCP or OpenWebSearch MCP integrations. They are not required for charts, news feeds, Nansen MCP, or Coinalyze.
- Optional API keys for Nansen, Coinalyze, Finnhub, and Marketaux when those providers are enabled.

The first request to a bundled MCP integration can download its `npx` package, so it requires network access.

## Quick start

```bash
# Fetch the Flutter packages.
flutter pub get

# Run the desktop target that matches your machine.
flutter run -d windows
```

Replace `windows` with `macos` or `linux` where appropriate.

## Configure DecMa

### 1. Configure an LLM connection

1. Start DecMa and select the settings icon in the **Trading Agent** panel.
2. Create or select a saved connection, then choose its provider.
3. For Anthropic Messages, OpenAI Responses, or OpenAI Chat Completions, enter the endpoint, model, and API key. DecMa adds the following request paths to the configured endpoint:

   | Provider | Default endpoint | Request path added by DecMa |
   | --- | --- | --- |
   | Anthropic Messages | `https://api.anthropic.com` | `/v1/messages` |
   | OpenAI Responses | `https://api.openai.com/v1` | `/responses` |
   | OpenAI Chat Completions | `https://api.openai.com/v1` | `/chat/completions` |

4. For **OpenAI Codex**, sign in through the browser and select a model. The application uses the Codex endpoint and credentials from that sign-in flow.
5. Save the settings. Leaving a masked credential field unchanged keeps the credential already stored on the device.

### 2. Configure analysis sources

Enable only the sources relevant to your workflow in **Agent Settings**:

| Source | Default | Credential | Notes |
| --- | --- | --- | --- |
| Bybit MCP | Enabled | Optional Bybit API key and secret | Requires Node.js and `npx`. The app admits only explicitly public, read-only MCP tools; optional account credentials are used to read fee rates. |
| OpenWebSearch MCP | Enabled | None | Requires Node.js and `npx`. |
| Nansen MCP | Disabled | Nansen API key | Optional on-chain context. |
| Coinalyze API | Disabled | Coinalyze API key | Optional derivatives data. The app applies a local 40-request-per-minute guard. |

### 3. Configure the market-news feed

Select the settings icon in **Market News** to enable sources and save optional API keys:

| Source | Default | Credential | Purpose |
| --- | --- | --- | --- |
| BLS | Enabled | None | Official U.S. labor releases. |
| BEA | Enabled | None | Official U.S. economic releases. |
| Federal Reserve | Enabled | None | Federal Reserve news and releases. |
| Finnhub | Disabled | Finnhub API key | Market-news feed. |
| Marketaux | Disabled | Marketaux API key | News for the current asset. |

The app checks feeds every minute, while each provider applies its own caching interval. Provider failures remain isolated from the chart and Agent.

## Use DecMa

1. Search for a Linear symbol such as `BTCUSDT` and select a chart interval.
2. Review the chart and **Market News** panel. Use its category and source filters to narrow the event list.
3. Describe the market directly or select **分析当前合约** (Analyze current contract) to get the current direction and entry conditions.
4. Review the Agent's report, warnings, and plan card. A plan is overlaid on the chart only after its symbol and price levels pass validation.
5. Continue asking follow-up questions in the same input. Select **清空** (Clear) to remove the current session's messages and analysis context.

## Data boundaries

DecMa treats Bybit as the primary source for its displayed price, mark/index price, order book, funding rate, and open interest. News and web search results are leads rather than verified facts. External data can be delayed, incomplete, unavailable, or contradictory, so outputs must be independently checked.

DecMa is an analysis and decision-support tool, not investment advice or a trade-execution system. Manage risk and make your own decisions.

## Project layout

```text
lib/
├── main.dart                         # Application and desktop-window startup
├── models/                           # Settings, market, news, and plan models
├── services/                         # LLM, market data, MCP, news, and secure storage
└── ui/
    ├── dashboard/                     # Workspace, chart controls, and Agent panel
    ├── chart/                         # Candlestick rendering and viewport logic
    ├── news/                          # News feed and settings dialog
    └── settings/                      # Agent settings dialog
```

# LICENSE
[MIT](LICENSE)
