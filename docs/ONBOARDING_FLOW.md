# 首次引导流程 (ONBOARDING_FLOW)

## 一、流程总览

```
应用启动
    │
    ▼
invoke("settings_get_status")
    │
    ├─→ 必填项 (LLM + Binance) 都已配置?
    │       │
    │       ├─ YES ──→ 直接进入看板 (AppLayout)
    │       │
    │       └─ NO ───→ 进入设置页面 (SettingsPage)
    │                    │
    │                    ▼
    │              单页表单，分 3 个区域:
    │              ┌──────────────────────────┐
    │              │ 🔴 必填: LLM API Key      │
    │              │    提供商选择 + Key 输入  │
    │              │                          │
    │              │ 🔴 必填: Binance API Key  │
    │              │    Key + Secret 输入     │
    │              │                          │
    │              │ 🔵 可选: 更多数据源       │
    │              │    NewsAPI / Twitter /   │
    │              │    Etherscan (可跳过)    │
    │              │                          │
    │              │ [跳过可选] [开始使用]     │
    │              └──────────────────────────┘
    │                    │
    │              用户填写 LLM + Binance
    │              点击 "开始使用" 或 "跳过可选"
    │                    │
    │              invoke("settings_set_api_key", ...)  × 2
    │                    │
    │              invoke("settings_get_status")
    │                    │
    │                    ▼
    │              进入看板 (AppLayout)
    │
    └─────────────────────┘
```

---

## 二、React 路由守卫设计

```typescript
// src/App.tsx
function App() {
  const { requiredConfigured, loading } = useSettingsStore();

  if (loading) return <LoadingScreen />;

  return requiredConfigured ? <AppLayout /> : <SettingsPage onboarding />;
}
```

### 2.1 useSettingsStore 守卫逻辑

```typescript
// src/stores/useSettingsStore.ts
interface SettingsState {
  apiKeys: Record<string, ApiKeyStatus>;
  loading: boolean;

  // 派生状态：是否所有必填项已配置
  requiredConfigured: boolean;  // LLM + Binance 都配置了

  // 派生状态：哪些可选源已配置
  optionalConfigured: string[];

  fetchStatus: () => Promise<void>;
  setApiKey: (provider: string, key: string) => Promise<void>;
  deleteApiKey: (provider: string) => Promise<void>;
}
```

### 2.2 必填项定义

```rust
// Rust 侧定义
const REQUIRED_PROVIDERS: &[&str] = &[
    "binance",       // Binance API Key + Secret
    "llm",           // 至少一个 LLM 提供商已配置
];

// llm 满足条件: openai OR anthropic OR ollama 至少一个已配置
```

---

## 三、设置页 UI 设计

### 3.1 布局

```
┌────────────────────────────────────────────────────┐
│                                                    │
│        🚀 欢迎使用 CryptoQuant                      │
│        请先配置 API 密钥以开始使用                    │
│                                                    │
│  ┌──────────────────────────────────────────────┐  │
│  │ 🔴 必填: AI 分析引擎                          │  │
│  │                                              │  │
│  │  提供商:  [OpenAI ▼]  [Anthropic]  [Ollama]  │  │
│  │  API Key: [                   ] [👁 显示]    │  │
│  │  模型:    [gpt-4o-mini ▼]                    │  │
│  │                                              │  │
│  │  💡 如何获取? → OpenAI API Keys 页面          │  │
│  └──────────────────────────────────────────────┘  │
│                                                    │
│  ┌──────────────────────────────────────────────┐  │
│  │ 🔴 必填: Binance 交易所                       │  │
│  │                                              │  │
│  │  API Key:    [                   ]           │  │
│  │  Secret Key: [                   ] [👁]      │  │
│  │                                              │  │
│  │  💡 如何获取? → Binance API 管理页面           │  │
│  │  ⚠️ 建议创建只读 API Key (关闭提现权限)        │  │
│  └──────────────────────────────────────────────┘  │
│                                                    │
│  ┌──────────────────────────────────────────────┐  │
│  │ 🔵 可选: 资讯数据源 (可跳过)                   │  │
│  │                                              │  │
│  │  ┌─ NewsAPI ──────────────────────────────┐  │  │
│  │  │ API Key: [                   ]  [跳过]  │  │  │
│  │  └────────────────────────────────────────┘  │  │
│  │  ┌─ Twitter/X ────────────────────────────┐  │  │
│  │  │ API Key: [                   ]  [跳过]  │  │  │
│  │  └────────────────────────────────────────┘  │  │
│  │  ┌─ Etherscan ────────────────────────────┐  │  │
│  │  │ API Key: [                   ]  [跳过]  │  │  │
│  │  └────────────────────────────────────────┘  │  │
│  └──────────────────────────────────────────────┘  │
│                                                    │
│              [跳过可选，开始使用]                    │
│                                                    │
└────────────────────────────────────────────────────┘
```

### 3.2 表单行为

| 状态 | 行为 |
|------|------|
| LLM 未填 + Binance 未填 | "开始使用" 按钮禁用，提示"请先配置必填项" |
| LLM 已填 + Binance 未填 | "开始使用" 按钮禁用 |
| LLM 未填 + Binance 已填 | "开始使用" 按钮禁用 |
| LLM 已填 + Binance 已填 | "开始使用" 按钮可点击 |
| 必填已填 + 可选空 | "跳过可选，开始使用" 可点击 |

### 3.3 Key 验证

点击 "开始使用" 后，在跳转前做一次即时验证：

```
1. invoke("settings_set_api_key", { provider: "openai", key: "sk-..." })
   → Rust 侧存储到 Keychain，同时做一次快速 LLM API 调用验证
   → 失败则 Toast 提示 "API Key 无效: 401 Unauthorized"

2. invoke("settings_set_api_key", { provider: "binance", key: "abc..." })
   → Rust 侧调用 Binance GET /api/v3/ping 验证连通性
   → 失败则 Toast 提示 "无法连接 Binance，请检查 Key 或网络"

3. 验证通过 → 跳转看板
```

### 3.4 头像/品牌区域

```
┌──────────────────────────────────┐
│                                  │
│     (logo 占位)                  │
│     CryptoQuant                  │
│     AI 驱动的加密货币量化看板     │
│                                  │
│     ✅ 本地运行，数据不上传       │
│     ✅ 开源 MIT 协议              │
│     ✅ 密钥存储在系统钥匙串       │
│                                  │
└──────────────────────────────────┘
```

---

## 四、设置页（非首次）

正常使用后的设置页布局与首次相同，但没有顶部品牌区域，取而代之的是：

- 左上角 "← 返回看板" 按钮
- 右上角系统信息（数据目录、存储大小等，通过 `settings_get_system_info` 获取）
- 底部 "删除所有本地数据" 危险按钮（清除 LanceDB + 聊天历史 + Keychain 中所有密钥）

---

## 五、未配置时的功能降级

若用户跳过了可选数据源，对应功能做降级处理：

| 未配置 | 影响 |
|--------|------|
| NewsAPI | 资讯流不显示新闻类目；Agent 的 `search_news` 不可用，提示用户 |
| Twitter | 资讯流不显示推文类目；Agent 的 `get_tweets` 不可用 |
| Etherscan/Whale Alert | 资讯流不显示链上类目；Agent 的 `get_onchain_activity` 不可用 |
| Ollama | LLM 提供商选择器不显示 Ollama 选项 |
