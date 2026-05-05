# RAG 管道设计 (RAG_DESIGN)

## 架构概览

```
    数据采集层                   处理层                      存储层              检索层
┌──────────────┐          ┌──────────────┐          ┌──────────────┐    ┌──────────────┐
│ NewsAPI      │──┐       │              │       ┌─→│ LanceDB      │    │              │
│ (newsapi.org)│  │       │  Collector   │       │  │ (news_table) │──┐ │  Retriever   │
└──────────────┘  │       │  (5min tick) │       │  └──────────────┘  │ │  (混合检索)  │
                  ├──────→│              │──────→│                    ├→│              │──→ LLM Context
┌──────────────┐  │       │  - 去重       │       │  ┌──────────────┐  │ │              │
│ Twitter API  │──┤       │  - 过滤       │       │  │ LanceDB      │  │ └──────────────┘
│ (v2 search)  │  │       │  - 分块       │       └─→│ (tweets_tbl) │──┤
└──────────────┘  │       │  - 嵌入       │          └──────────────┘  │
                  │       │              │                             │
┌──────────────┐  │       │  Embedder    │          ┌──────────────┐  │
│ Whale Alert  │──┤       │  (fastembed) │       ┌─→│ LanceDB      │  │
│ Etherscan    │──┘       │  all-MiniLM  │       │  │ (onchain_tbl)│──┘
│ ...          │          │  384 dims    │       │  └──────────────┘
└──────────────┘          └──────────────┘       │
                                                  │  索引更新
                                                  │  每 5 分钟
                                                  └──────────────┘
```

---

## 1. 采集器 (Collector)

### 采集策略

| 数据源 | 采集频率 | 每次数量 | API 缓存 |
|--------|---------|---------|---------|
| NewsAPI | 每 5 分钟 | 每条币种 20 条 | 本地 LRU 去重 |
| Twitter | 每 10 分钟 | 总量 50 条 | 本地 LRU 去重 |
| Whale Alert | 每 5 分钟 | 总量 20 条 | URL 去重 |
| Etherscan | 每 15 分钟 | 每条链 10 条 | API 自带限流 |

### 去重算法

```rust
// LRU Cache 记录最近 5000 条 URL
struct DedupCache {
    seen_urls: LruCache<String, ()>,  // capacity = 5000
}

impl DedupCache {
    fn is_duplicate(&mut self, url: &str) -> bool {
        if self.seen_urls.contains(url) {
            return true;
        }
        self.seen_urls.put(url.to_string(), ());
        false
    }
}
```

### 过滤规则

```
过滤条件:
  1. 标题长度 < 5 字符 → 过滤 (太短无意义)
  2. 内容包含 "sponsored" / "advertisement" → 过滤 (广告)
  3. 内容仅含链接无正文 → 过滤 (空内容)
  4. 新闻日期 > 7 天前 → 不采集 (过期)
  5. 推文互动量 (like+retweet) < 10 → 过滤 (低质量)
```

---

## 2. 文本分块 (Chunker)

### 分块策略

```
递归字符分割:
  separators: ["\n\n", "\n", ". ", " ", ""]
  chunk_size: 512 (字符数, 约 120-150 tokens)
  chunk_overlap: 50

示例输入 (900 字符的新闻):
  段落 1 (300 字符)
  段落 2 (300 字符)
  段落 3 (300 字符)

分块结果:
  Chunk 1: 段落 1 + 部分段落 2 (512 字符)
  Chunk 2: 段落 2 + 部分段落 3 + 部分段落 1 (512 字符, 50 字符重叠)
  Chunk 3: 段落 3 + 部分段落 2 (512 字符, 50 字符重叠)
```

### 实现 (使用 text-splitter)

```rust
use text_splitter::TextSplitter;

pub struct Chunker {
    splitter: TextSplitter<text_splitter::TokenCount>,
}

impl Chunker {
    pub fn new() -> Self {
        let splitter = TextSplitter::default()
            .with_chunk_size(512)
            .with_chunk_overlap(50);
        Self { splitter }
    }

    pub fn split(&self, text: &str) -> Vec<String> {
        self.splitter.chunks(text).map(|c| c.to_string()).collect()
    }
}
```

---

## 3. 嵌入器 (Embedder)

### 模型选择

| 模型 | 维度 | 大小 | 质量 (MTEB) | 适用场景 |
|------|------|------|-------------|---------|
| `all-MiniLM-L6-v2` | 384 | 80MB | 56.3 | **默认**，平衡速度与质量 |
| `BAAI/bge-small-en-v1.5` | 384 | 133MB | 62.2 | 英文为主 |
| `BAAI/bge-small-zh-v1.5` | 512 | 102MB | - | 中文为主 |
| `intfloat/multilingual-e5-small` | 384 | 118MB | 60.1 | 多语言混合 |

**默认选 `all-MiniLM-L6-v2`**，体积最小，质量可接受。用户可在设置中切换模型。

### 实现

```rust
use fastembed::{TextEmbedding, InitOptions, EmbeddingModel};

pub struct Embedder {
    model: TextEmbedding,
}

impl Embedder {
    pub fn new(model_name: &str, cache_dir: PathBuf) -> Result<Self> {
        let model = TextEmbedding::try_new(
            InitOptions::new()
                .with_model_name(model_name)
                .with_cache_dir(cache_dir)
                .with_show_download_progress(true)
        )?;
        Ok(Self { model })
    }

    /// 批量生成嵌入向量
    pub fn embed(&self, texts: Vec<&str>) -> Result<Vec<Vec<f32>>> {
        // fastembed 自动批处理 + 多线程 ONNX 推理
        Ok(self.model.embed(texts)?)
            .into_iter()
            .map(|e| e.to_vec())
            .collect()
    }
}
```

### 性能预期

```
硬件: M1/M2 Mac, 16GB RAM
批次: 100 段文本 × 512 字符
耗时: ~2 秒 (首次) / ~0.5 秒 (缓存预热后)

硬件: Intel i5, 16GB RAM
批次: 100 段文本 × 512 字符
耗时: ~5 秒 (首次) / ~2 秒 (缓存预热后)
```

---

## 4. 向量存储 (LanceDB)

### 表结构

```rust
// news_table / tweets_table / onchain_table 结构相同
use lancedb::arrow::arrow_schema::{Schema, Field, DataType};

// 创建表
let schema = Schema::new(vec![
    Field::new("id", DataType::Utf8, false),
    Field::new("source_url", DataType::Utf8, true),
    Field::new("source_type", DataType::Utf8, false),  // "news" | "tweet" | "onchain"
    Field::new("title", DataType::Utf8, true),
    Field::new("content", DataType::Utf8, false),
    Field::new("summary", DataType::Utf8, true),
    Field::new("published_at", DataType::Int64, false),  // Unix ms
    Field::new("keywords", DataType::List(Arc::new(Field::new("item", DataType::Utf8, true))), true),
    Field::new("related_symbol", DataType::Utf8, true),   // "BTC" | "ETH" | ...
    Field::new("embedding", DataType::FixedSizeList(Arc::new(Field::new("item", DataType::Float32, true)), 384), false),
]);

let table = db.create_table("news", schema).await?;
```

### 索引

```rust
// 创建向量索引 (IVF_PQ)
table
    .create_index(&["embedding"])
    .ivf_pq()
    .num_partitions(256)
    .num_sub_vectors(96)
    .build()
    .await?;

// 创建标量索引 (用于过滤)
table
    .create_index(&["related_symbol"])
    .btree()
    .build()
    .await?;

table
    .create_index(&["published_at"])
    .btree()
    .build()
    .await?;
```

### 数据清理

```rust
// 定期清理 7 天前的数据
let cutoff = chrono::Utc::now().timestamp_millis() - 7 * 24 * 3600 * 1000;
table
    .delete()
    .where_lt("published_at", cutoff)
    .await?;

// 压缩以回收空间 (version cleanup)
table.optimize().clean_up_old_versions(true).await?;
```

---

## 5. 检索器 (Retriever)

### 混合检索策略

```rust
pub async fn retrieve(
    &self,
    query: &str,
    source_type: Option<SourceType>,
    symbol: Option<&str>,
    limit: usize,
) -> Result<Vec<RagDocument>> {
    // 1. 向量检索
    let query_embedding = self.embedder.embed(vec![query])?;
    let vector_results = self.vector_search(&query_embedding[0], source_type, symbol, limit).await?;

    // 2. 全文检索 (作为补充)
    let fulltext_results = self.fulltext_search(query, source_type, symbol, limit).await?;

    // 3. 融合 (Reciprocal Rank Fusion)
    let fused = self.rrf_fusion(vector_results, fulltext_results, 60);

    // 4. 按发布时间降序排列 (近期优先)
    fused.sort_by_key(|d| -d.published_at);
    fused.truncate(limit);

    Ok(fused)
}
```

### RRF 融合算法

```
Reciprocal Rank Fusion:
  score(doc) = Σ (1 / (k + rank_i(doc)))
  
  k = 60 (常数，控制排名影响)
  
示例:
  文档 A: 向量排名 #1, 全文排名 #3
  score(A) = 1/(60+1) + 1/(60+3) = 0.0164 + 0.0159 = 0.0323
  
  文档 B: 向量排名 #2, 全文排名 #1
  score(B) = 1/(60+2) + 1/(60+1) = 0.0161 + 0.0164 = 0.0325
  
  → 文档 B 胜出 (在两个信号中都表现良好)
```

---

## 6. 存储容量估算

```
单条新闻: ~500 字符
分块后: ~2 chunks/条
每段向量: 384 × 4 bytes = 1.5KB
每段文本: ~0.5KB

每天采集量:
  NewsAPI: 6币种 × 20条 × 24次/天 = 2,880 条
  Twitter:  50条 × 12次/天 = 600 条
  链上:    20条 × 24次/天 = 480 条
  合计: ~3,960 条/天

数据库大小 (每天):
  文本: 3,960 × 0.5KB = ~2MB
  向量: 3,960 × 2 × 1.5KB = ~12MB
  总计: ~14MB/天

7 天保留: ~100MB
30 天保留: ~420MB

结论: 桌面应用量级完全可接受，LanceDB 胜任
```
