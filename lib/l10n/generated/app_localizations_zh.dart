// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get language => '语言';

  @override
  String get save => '保存';

  @override
  String get saving => '保存中…';

  @override
  String get close => '关闭';

  @override
  String get notProvided => '未提供';

  @override
  String get noValue => '暂无';

  @override
  String get encryptedKeyPlaceholder => '输入新密钥以加密保存';

  @override
  String secureStorageFailed(Object error) {
    return '安全存储失败：$error';
  }

  @override
  String get effortLow => '低';

  @override
  String get effortMedium => '中';

  @override
  String get effortHigh => '高';

  @override
  String get effortXhigh => '极高';

  @override
  String get effortMax => '最高';

  @override
  String get effortUltra => '极致';

  @override
  String failurePrefix(Object provider) {
    return '$provider：';
  }

  @override
  String get failureCancelled => '请求已取消。';

  @override
  String get failureNetworkUnavailable => '网络不可用，请检查连接后重试。';

  @override
  String get failureTimeout => '请求超时，请稍后重试。';

  @override
  String get failureAuthentication => '认证失败，请检查 API Key 或登录状态。';

  @override
  String get failureRateLimited => '请求过于频繁，请稍后重试。';

  @override
  String get failureUpstream => '服务暂时不可用，请稍后重试。';

  @override
  String get failureInvalidResponse => '服务返回了无效响应。';

  @override
  String get failureConfiguration => '服务配置不完整。';

  @override
  String get nodeMissingTitle => 'Nodejs 未检测到';

  @override
  String get nodeMissingBody => '未检测到Nodejs，部分功能有缺失。';

  @override
  String get openNodeSite => '前往 Nodejs 官网';

  @override
  String get gotIt => '知道了';

  @override
  String get searchTokenPlaceholder => '搜索代币，例如 BTC';

  @override
  String get entryZone => '开仓区';

  @override
  String get stopLoss => '止损';

  @override
  String get takeProfit => '止盈';

  @override
  String get scrollToBottom => '滚动到底部';

  @override
  String get promptPlaceholder => '输入代币或继续追问分析结果';

  @override
  String get analyzeCurrentContract => '分析当前合约';

  @override
  String get stopGenerating => '停止生成';

  @override
  String get send => '发送';

  @override
  String get clear => '清空';

  @override
  String get chartLong => '做多';

  @override
  String get chartShort => '做空';

  @override
  String get chartWaitZone => '等待区';

  @override
  String chartEntryLevel(Object label) {
    return '$label 开仓';
  }

  @override
  String chartAggregated(Object end, Object start) {
    return '$start — $end（聚合）';
  }

  @override
  String get ohlcOpen => '开';

  @override
  String get ohlcHigh => '高';

  @override
  String get ohlcLow => '低';

  @override
  String get ohlcClose => '收';

  @override
  String get chartCursor => '鼠标';

  @override
  String get chartLatest => '最新';

  @override
  String planEntryZone(Object value) {
    return '开仓区：$value';
  }

  @override
  String planStopLoss(Object value) {
    return '止损：$value';
  }

  @override
  String planTakeProfit(Object value) {
    return '止盈：$value';
  }

  @override
  String get viewFullJson => '点击查看完整 JSON 解析';

  @override
  String jsonResultTitle(Object decision) {
    return '$decision：JSON 解析结果';
  }

  @override
  String get fullJson => '完整 JSON';

  @override
  String get decisionLongSetup => '做多方案';

  @override
  String get decisionShortSetup => '做空方案';

  @override
  String get decisionWait => '等待';

  @override
  String get decisionNoTrade => '不交易';

  @override
  String get decisionDataInsufficient => '数据不足';

  @override
  String klineLoadFailed(Object error) {
    return 'K 线加载失败：$error';
  }

  @override
  String historyLoadFailed(Object error) {
    return '更早历史加载失败：$error';
  }

  @override
  String get fetchingModels => '正在获取模型…';

  @override
  String get selectModel => '选择模型';

  @override
  String get fetchingEffort => '正在获取思考等级';

  @override
  String get effortUnsupported => '此模型不支持选择思考等级';

  @override
  String get effortGeneric => '思考等级：通用选项，具体支持范围由服务端决定';

  @override
  String get reasoningEffort => '思考等级';

  @override
  String get refreshModels => '刷新模型列表';

  @override
  String get newsAll => '全部新闻';

  @override
  String newsRelated(Object asset) {
    return '$asset 相关';
  }

  @override
  String get newsCryptoMarket => '加密市场';

  @override
  String get updatingNews => '正在更新新闻';

  @override
  String get allSources => '全部来源';

  @override
  String get fetchingNews => '正在获取新闻…';

  @override
  String get noRelatedNews => '暂无相关新闻';

  @override
  String get verifyUnverified => '待核实';

  @override
  String get verifySecondary => '媒体确认';

  @override
  String get verifyPrimary => '官方确认';

  @override
  String get verifyConflicted => '信息存疑';

  @override
  String get importanceCritical => '重大';

  @override
  String get importanceHigh => '重要';

  @override
  String get importanceMedium => '中等';

  @override
  String get importanceLow => '较低';

  @override
  String get categoryMacro => '宏观';

  @override
  String get categoryRegulation => '监管';

  @override
  String get categoryCentralBank => '央行';

  @override
  String get categoryExchange => '交易所';

  @override
  String get categorySecurity => '安全';

  @override
  String get categoryProject => '项目';

  @override
  String get categoryMarket => '市场';

  @override
  String get categoryOther => '其他';

  @override
  String get newsSettingsTitle => 'Market News 设置';

  @override
  String get finnhubDocs => '查看 Finnhub Market News 文档';

  @override
  String get marketauxDocs => '查看 Marketaux API 文档';

  @override
  String get officialSources => '官方数据源';

  @override
  String get sourcesStarting => '数据源启动中…';

  @override
  String get noNewsSources => '未启用新闻源';

  @override
  String sourcesUnavailable(Object count) {
    return '$count 个来源暂不可用';
  }

  @override
  String sourcesAvailable(Object count) {
    return '$count 个来源可用';
  }

  @override
  String get noSuccessfulUpdate => '暂无成功更新时间';

  @override
  String lastSuccessfulUpdate(Object time) {
    return '最近成功更新：$time';
  }

  @override
  String get updatedAtNone => '更新于 —';

  @override
  String updatedAt(Object time) {
    return '更新于 $time';
  }

  @override
  String get providerActive => '可用';

  @override
  String get providerDisabled => '未启用';

  @override
  String get providerError => '连接失败';

  @override
  String get providerRateLimited => '请求受限';

  @override
  String get agentSettings => 'Agent 设置';

  @override
  String get bybitAccountApi => 'Bybit 账户 API（可选）';

  @override
  String get bybitDocs => '查看 Bybit 只读账户 API 文档';

  @override
  String get bybitHint => '仅用于读取实际手续费率';

  @override
  String get nansenDocs => '查看 Nansen MCP 文档';

  @override
  String get coinalyzeDocs => '查看 Coinalyze API 文档';

  @override
  String get codexSignedIn => '已登录 ChatGPT，使用 Codex 订阅额度。';

  @override
  String get codexSignInHint => '通过 ChatGPT 登录以使用 Codex。';

  @override
  String get connecting => '正在连接…';

  @override
  String get signInAgain => '重新登录';

  @override
  String get signInChatGpt => '登录 ChatGPT';

  @override
  String get connectionNameEmpty => '配置名称不能为空。';

  @override
  String get connectionNameExists => '配置名称已存在。';

  @override
  String get newConnection => '新建配置';

  @override
  String get llmConnection => 'LLM 连接';

  @override
  String get savedConnections => '已保存的配置';

  @override
  String get deleteConnection => '删除配置';

  @override
  String get connectionName => '配置名称';

  @override
  String get apiType => '接口类型';

  @override
  String get activityThinking => '• Thinking - 分析中…';

  @override
  String get generationStopped => '> 已停止生成，未完成的回答未用于更新分析结果。';

  @override
  String agentRequestFailed(Object error) {
    return '> Agent 请求失败：$error';
  }

  @override
  String get codexNotReady => '> 请先在设置中登录 OpenAI Codex 并选择模型。';

  @override
  String get llmNotReady => '> 请先在设置中填写 LLM Endpoint、Model 并保存 API Key。';

  @override
  String noCandlesToAnalyze(Object symbol) {
    return '$symbol 没有可分析的 K 线。';
  }

  @override
  String get activityIndicatorsDone => '• Deterministic Engine - 指标计算完成';

  @override
  String get activityResultGenerating => '• Result - 结果生成中…';

  @override
  String get activityMarketSnapshot => '• Market Snapshot - 获取固定多周期行情';

  @override
  String invalidContract(Object symbol) {
    return '$symbol 合约状态或类型无效。';
  }

  @override
  String get noticeNoPlan => '暂未获得完整价格计划，请以文字说明为准。';

  @override
  String get noticePlanRejected => '价格计划未通过校验，暂不使用这些价位。';

  @override
  String noticeSymbolMismatch(Object symbol) {
    return '分析对象与 $symbol 不一致，请重新分析。';
  }

  @override
  String noticeChartSwitched(Object active, Object symbol) {
    return '当前图表已切换为 $active，未添加 $symbol 的图表标记。';
  }

  @override
  String dataSourceNotice(Object notices) {
    return '> 数据源提示：$notices';
  }

  @override
  String quickAnalyzePrompt(Object symbol) {
    return '分析 $symbol 现在更适合做多、做空还是等待。请结合当前价格，直接说明现在能否入场；如果机会已经走完，说明应该等待什么条件。';
  }

  @override
  String majorEventCancel(Object headline) {
    return '出现已确认的重大事件，请重新分析：$headline';
  }

  @override
  String get entryDetails => '开仓详情';

  @override
  String get planCleared => '当前计划已清除';

  @override
  String get biasLong => '偏多';

  @override
  String get biasShort => '偏空';

  @override
  String get actionConfirming => '正在确认';

  @override
  String get actionNoEntry => '暂不入场';

  @override
  String get actionMissed => '已经错过，不追价';

  @override
  String get actionInvalid => '原计划已失效';

  @override
  String get triggerCloseAbove => '收盘站上指定价格';

  @override
  String get triggerCloseBelow => '收盘跌破指定价格';

  @override
  String get triggerBreakoutRetest => '突破后另一根 K 线回踩守住';

  @override
  String get triggerTouchZone => '触及区间边界后收回区间';

  @override
  String get triggerVolume => '价格方向与放量共同确认';

  @override
  String statusTerminal(Object action, Object side) {
    return '等待 · $action（此前$side）';
  }

  @override
  String get refreshOpportunity => '刷新当前机会';

  @override
  String referencePrice(Object price) {
    return '参考现价 $price';
  }

  @override
  String entrySummary(Object high, Object low, Object stop) {
    return '开仓区 $low–$high · 止损 $stop';
  }

  @override
  String validUntil(Object time) {
    return '有效期至 $time';
  }

  @override
  String referenceEntry(Object price, Object rr) {
    return '参考入场 $price · 净盈亏比 $rr:1';
  }

  @override
  String chaseBoundary(Object price) {
    return '成本后追价边界 $price';
  }

  @override
  String get costEstimateNote => '按公共 Taker 费率和 3 小时资金费情景估算；未估计仓位冲击';

  @override
  String triggerSummary(Object minutes, Object price, Object trigger) {
    return '触发：$trigger · $minutes 分钟 · 价格 $price';
  }

  @override
  String get zoneEdge => '区间边界';

  @override
  String invalidationSummary(Object price, Object stop) {
    return '失效价 $price · 止损参考 $stop';
  }

  @override
  String featureSnapshot(Object time) {
    return '指标快照 $time';
  }

  @override
  String reviewedAt(Object time) {
    return '复核时间 $time';
  }

  @override
  String get viewDetails => '查看详情';

  @override
  String get checkingPrice => '正在检查最新价格';

  @override
  String get priceUnconfirmed => '暂未确认最新价格，等待行情刷新';

  @override
  String get awaitingQuotes => '等待买卖报价和资金费结算信息确认';

  @override
  String get rrTooLow => '当前参考净盈亏比不足 1:1，等待更优价格和新的触发';

  @override
  String get marketUnavailable => '暂未获取到最新行情，稍后重试';

  @override
  String get priceChanged => '价格变化，正在重新确认入场条件';

  @override
  String get recheckOnReturn => '返回后按最新行情重新确认';

  @override
  String get entryWaiting => '等待触发';

  @override
  String get entryReady => '当前可参考入场';

  @override
  String get entryPaused => '等待回踩';

  @override
  String get entryRealized => '机会已兑现';

  @override
  String get entryInvalid => '已失效';

  @override
  String get entryUnverified => '等待确认';

  @override
  String get entryNoPlan => '没有可核验的开仓计划';

  @override
  String get entryIncomplete => '价格或目标不完整';

  @override
  String get entryAmbiguousStart => '起始分钟内事件时间不明确，请重新分析';

  @override
  String get entryAmbiguousPath => '同分钟触及失效与目标，路径不确定';

  @override
  String get entryInvalidBeforeEntry => '入场前结构已失效';

  @override
  String get entryTargetReached => '未入场已到 TP1，需要新计划';

  @override
  String get entryStructureInvalid => '结构已失效';

  @override
  String get entryExpired => '候选计划已过期';

  @override
  String get entryStale => '行情已过期或价格路径不完整';

  @override
  String get entryNeedsConfirmation => '仍需确认入场条件，以最新行情为准';

  @override
  String get entryChaseUndefined => '最大追价未定义';

  @override
  String get entryAboveChase => '超过最大追价，等待回踩并重新核验';

  @override
  String get entryOutsideZone => '尚未进入允许开仓区域';

  @override
  String get entryAwaitTriggerCandle => '等待新的完整触发 K 线';

  @override
  String get entryTriggerConfirmed => '当前参考行情的入场触发已确认；价格变化后需要重新检查';

  @override
  String planUnknownDecision(Object decision) {
    return '未知决策类型 $decision';
  }

  @override
  String get planInvalidWaitZone => '候选等待区无效，价格标记已忽略';

  @override
  String get planWaitOnlyZone => 'WAIT 仅保留候选等待区，其他价格标记已忽略';

  @override
  String get planNonSetupIgnored => '非交易 Setup 的价格标记已忽略';

  @override
  String get planSetupMissingEntry => '交易 Setup 缺少完整开仓区或止损';

  @override
  String get planPricesInvalid => '价格必须为正数且有限';

  @override
  String get planEntryInverted => '开仓区下限高于上限';

  @override
  String get planMissingTargets => '交易 Setup 缺少止盈目标';

  @override
  String get planTooManyTargets => '图表仅显示前三档止盈目标';

  @override
  String get planLongStop => '多头止损必须低于开仓区';

  @override
  String get planLongTargets => '多头止盈必须高于开仓区';

  @override
  String get planLongTargetOrder => '多头止盈必须按价格升序排列';

  @override
  String get planLongChase => '多头最大追价不能低于开仓区上限';

  @override
  String get planShortStop => '空头止损必须高于开仓区';

  @override
  String get planShortTargets => '空头止盈必须低于开仓区';

  @override
  String get planShortTargetOrder => '空头止盈必须按价格降序排列';

  @override
  String get planShortChase => '空头最大追价不能高于开仓区下限';

  @override
  String get planTickMisaligned => '价格未对齐合约 Tick Size，仅供参考，实际下单需确认价格精度';

  @override
  String get planAllocationInvalid => '止盈比例不完整或无效，不作为分仓依据';

  @override
  String get planAllocationTotal => '止盈比例合计不是 100%，不作为分仓依据';

  @override
  String planGrossRrMismatch(Object price) {
    return '止盈 $price 的 Gross RR 与确定性计算不一致';
  }

  @override
  String planNetAboveGross(Object price) {
    return '止盈 $price 的 Net RR 高于 Gross RR';
  }

  @override
  String get coinalyzeKeyMissing => 'Coinalyze API: API Key 未配置。';

  @override
  String get nansenKeyMissing => 'Nansen MCP: API Key 未配置。';

  @override
  String activityFailed(Object activity) {
    return '$activity（失败）';
  }

  @override
  String get activityTokenBackground => '• 项目背景 - 更新背景缓存';

  @override
  String get activityDiscoverTools => '• MCP - 发现可用工具';

  @override
  String get signInChatGptFirst => '请先登录 ChatGPT。';

  @override
  String get oauthCallbackInvalid => 'OAuth 回调无效，请重试。';

  @override
  String get streamEndedEarly => '响应流提前结束，未收到成功完成信号。';

  @override
  String get codexMissingAccount => 'OpenAI Codex OAuth 缺少 ChatGPT account ID，请重新登录。';

  @override
  String get codexFailedStatus => 'Codex 返回失败状态。';

  @override
  String responseIncomplete(Object reason) {
    return '响应未完成：$reason';
  }

  @override
  String get responseNotCompleted => '响应未成功完成。';

  @override
  String get responseParseFailed => '响应解析失败。';

  @override
  String get llmKeyMissing => '请先在设置中保存 LLM API Key 或登录 OpenAI Codex。';

  @override
  String get bybitKeyPair => 'Bybit 账户 API：API Key 和 API Secret 需同时配置。';

  @override
  String get activityBybitFees => '• Bybit Account - 获取实际手续费率';

  @override
  String sourceDisabled(Object source) {
    return 'FULL_SOURCE_ENRICHMENT：$source 已禁用。';
  }

  @override
  String sourceUnavailable(Object source) {
    return 'FULL_SOURCE_ENRICHMENT：$source 当前不可用。';
  }

  @override
  String activityLlmRetry(Object attempt) {
    return '• LLM - 响应中断，正在重试 $attempt/4';
  }

  @override
  String activityFillSources(Object sources) {
    return '• Data Sources - 补充缺失来源：$sources';
  }

  @override
  String get enrichmentFailed => 'FULL_SOURCE_ENRICHMENT：补采请求失败，已保留首轮分析。';

  @override
  String enrichmentIncomplete(Object sources) {
    return 'FULL_SOURCE_ENRICHMENT 未完成：$sources 可用但未调用，可能不适用于当前资产或被模型跳过。';
  }

  @override
  String enrichmentInvalid(Object sources) {
    return 'FULL_SOURCE_ENRICHMENT：$sources 已尝试，但未返回有效数据。';
  }

  @override
  String get home => '首页';

  @override
  String get settings => '设置';

  @override
  String get retry => '重试';

  @override
  String get loadingKlines => '正在加载 Bybit 永续合约 K 线…';

  @override
  String get loadingHistory => '加载更早历史…';

  @override
  String modelListFailed(Object error) {
    return '模型列表获取失败：$error';
  }

  @override
  String modelSaveFailed(Object error) {
    return '模型保存失败：$error';
  }

  @override
  String codexLoginFailed(Object error) {
    return 'OpenAI Codex 登录失败：$error';
  }

  @override
  String planCardDecision(Object decision) {
    return '决策：$decision';
  }

  @override
  String planCardEntry(Object high, Object low) {
    return '开仓 $low – $high';
  }

  @override
  String get languageDescription => '更改应用的显示语言';

  @override
  String get agentSettingsDescription => 'LLM 连接、MCP 服务与数据 API';

  @override
  String get newsSettingsDescription => '新闻提供方与官方数据源';
}
