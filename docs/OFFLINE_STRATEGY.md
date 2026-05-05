# 离线策略 (OFFLINE_STRATEGY)

## 一、断网检测

### 1.1 检测机制

```
前端: navigator.onLine (浏览器原生 API, Tauri WebView 支持)
后端: Binance WS ping/pong 超时 + REST API 超时 = 综合判断
```

### 1.2 状态传播

```
Rust 后端                     React 前端
┌──────────┐                ┌──────────────┐
│          │  binance WS    │              │
│ tokio::  │── timeout ──→  │ connection-  │
│ select!  │  (30s 无响应)  │  status      │
│          │                │  Event       │
│          │                │              │
│  REST    │── timeout ──→  │              │
│  reqwest │  (10s 无响应)  │              │
│          │                │              │
│          │  任一恢复 ──→  │ connection-  │
│          │                │  status      │
│          │                │  Event       │
└──────────┘                └──────┬───────┘
                                   │
                          listen("connection-status")
                                   │
                          ┌────────▼───────┐
                          │ Toast:          │
                          │ "⚠️ 网络已断开" │
                          │ (可关闭)        │
                          │              │
                          │ 顶部横幅:       │
                          │ [离线模式] K线数据│
                          │ 可能已过期      │
                          └────────────────┘
```

---

## 二、各功能降级行为

| 功能 | 离线时行为 | 恢复后行为 |
|------|-----------|-----------|
| **K 线图** | 显示本地缓存的历史 K 线，图表右上角标注 `[离线]` 红色角标 | 自动重连 WS，补全缺失数据段 |
| **订单簿** | 清空，显示 "实时数据不可用" | 自动恢复推送 |
| **价格行情** | 冻结在最后价格，灰色显示，标注 "最后更新: HH:MM:SS" | 自动恢复颜色和实时更新 |
| **资讯流** | 显示上次采集的数据，顶部提示 "资讯更新已暂停" | 触发一次立即采集 |
| **AI 对话** | 输入框禁用，显示 "需要网络连接以使用 AI 分析" | 自动恢复可用 |
| **设置页** | 完全可用（本地 Keychain 读写） | 无变化 |

---

## 三、K 线本地缓存

### 3.1 缓存策略

```
存储位置: $APP_DATA/cache/klines.db (SQLite)
每条记录: symbol + interval + open_time + ohlcv 数据
缓存数量: 每个币种/周期存储最近 1000 根 K 线
清理策略: 超过 1000 根的旧数据自动删除 (FIFO)
```

### 3.2 表结构

```sql
CREATE TABLE IF NOT EXISTS kline_cache (
    symbol TEXT NOT NULL,        -- "BTCUSDT"
    interval TEXT NOT NULL,      -- "1h" | "4h" | "1d"
    open_time INTEGER NOT NULL,  -- Unix ms
    open REAL NOT NULL,
    high REAL NOT NULL,
    low REAL NOT NULL,
    close REAL NOT NULL,
    volume REAL NOT NULL,
    close_time INTEGER NOT NULL,
    quote_volume REAL NOT NULL,
    trades INTEGER NOT NULL,
    taker_buy_volume REAL NOT NULL,
    taker_buy_quote_volume REAL NOT NULL,
    cached_at INTEGER NOT NULL,  -- 缓存时间
    PRIMARY KEY (symbol, interval, open_time)
);

CREATE INDEX idx_kline_cache_symbol_interval
    ON kline_cache(symbol, interval);
```

### 3.3 Rust 实现要点

```rust
// src-tauri/src/binance/cache.rs
pub struct KlineCache {
    db: rusqlite::Connection,
}

impl KlineCache {
    pub fn new(data_dir: &Path) -> Result<Self> {
        let db = Connection::open(data_dir.join("cache").join("klines.db"))?;
        db.execute_batch(CREATE_TABLE_SQL)?;
        Ok(Self { db })
    }

    /// 每次收到新 K 线时写入缓存
    pub async fn cache_kline(&self, symbol: &str, interval: &str, kline: &Kline) -> Result<()> {
        self.db.execute(INSERT_SQL, params![
            symbol, interval, kline.open_time,
            kline.open, kline.high, kline.low, kline.close, kline.volume,
            kline.close_time, kline.quote_volume, kline.trades,
            kline.taker_buy_volume, kline.taker_buy_quote_volume,
            Utc::now().timestamp_millis(),
        ])?;
        Ok(())
    }

    /// 离线时读取缓存
    pub fn get_cached_klines(&self, symbol: &str, interval: &str, limit: u16) -> Result<Vec<Kline>> {
        let mut stmt = self.db.prepare(SELECT_SQL)?;
        let rows = stmt.query_map(params![symbol, interval, limit], |row| {
            Ok(Kline { /* map fields */ })
        })?;
        Ok(rows.filter_map(|r| r.ok()).collect())
    }

    /// 清理超出限制的旧数据
    pub fn prune(&self, symbol: &str, interval: &str, keep: u16) -> Result<()> {
        // DELETE ... WHERE rowid NOT IN (SELECT rowid ... ORDER BY open_time DESC LIMIT keep)
        Ok(())
    }
}
```

---

## 四、Binance WebSocket 重连策略

### 4.1 重连参数

```
初始重连延迟: 1 秒
最大重连延迟: 60 秒
退避算法: 指数退避 (delay = min(prev * 2, 60))
最大重试次数: 无限制 (持续重试直到应用关闭)
```

### 4.2 数据补全

```
WS 断连期间:
  记录断开时间 disconnection_time

WS 重连成功后:
  1. 调用 REST API 获取 (disconnection_time, now] 区间的 K 线
  2. 与缓存合并，去重 (按 open_time)
  3. 推送给前端 (emit market-data 批量)
```

### 4.3 连接状态事件

```typescript
// 三种状态轮流推送
{ binance_ws: "connected" }       // 正常
{ binance_ws: "reconnecting" }    // 断连后首次重试
{ binance_ws: "disconnected" }    // 重连超过 5 次仍未成功
```

---

## 五、LLM API 不可用时的降级

LLM API 调用超时或返回错误时，Agent 循环不崩溃：

```
Agent 循环内的工具调用不受影响（仍可检索 RAG、获取 K 线等）
仅 LLM 推理步骤失败时：
  1. 若在工具调用前失败 → 返回 "AI 服务暂时不可用，请稍后重试"
  2. 若在工具调用后失败 → 返回已收集的工具结果，附带 "AI 总结不可用，以下为原始数据"
```

---

## 六、前端离线检测 Hook

```typescript
// src/hooks/useConnectionStatus.ts
import { listen } from '@tauri-apps/api/event';
import { useEffect } from 'react';

export function useConnectionStatus() {
  const [status, setStatus] = useState<ConnectionStatus>({
    connected: true,
    binance_ws: "connected",
  });

  useEffect(() => {
    const unlisten = listen<ConnectionStatus>('connection-status', (event) => {
      setStatus(event.payload);

      if (!event.payload.connected) {
        toast.warning('网络已断开，部分功能不可用', {
          id: 'offline-toast',
          duration: Infinity,  // 不自动消失
        });
      } else {
        toast.dismiss('offline-toast');
        toast.success('网络已恢复');
      }
    });

    return () => { unlisten.then(fn => fn()) };
  }, []);

  return status;
}
```

---

## 七、存储容量

```
缓存位置: $APP_DATA/cache/
├── klines.db          # ~10MB (6 币种 × 3 周期 × 1000 根 × ~500B)
├── chat_history.db    # ~5MB  (对话历史)
└── lancedb/           # ~100MB (7 天向量数据)

总计: ~115MB (正常使用 30 天后)
```
