import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:genkit/genkit.dart';

import '../../data/services/agent_service.dart';
import '../../utils/network.dart';

// Keep presentation messages independent of chart and exchange state.
enum DashboardMessageKind { user, agent, activity }

class DashboardMessage {
  const DashboardMessage.user(this.text) : kind = DashboardMessageKind.user;
  const DashboardMessage.agent(this.text) : kind = DashboardMessageKind.agent;
  const DashboardMessage.activity(this.text)
    : kind = DashboardMessageKind.activity;
  final String text;
  final DashboardMessageKind kind;
  bool get isUser => kind == DashboardMessageKind.user;
  bool get isActivity => kind == DashboardMessageKind.activity;
}

// Own conversation state and cancellation; business execution is supplied by the dashboard.
class AgentConversationController extends ChangeNotifier {
  AgentConversationController() {
    scroll.addListener(_handleScroll);
  }
  final prompt = TextEditingController();
  final scroll = ScrollController();
  final messages = <DashboardMessage>[];
  bool loading = false;
  bool showScrollToBottom = false;
  String? lastAnalysis;
  DateTime? lastAnalysisAt;
  CancellationController? _request;
  bool _atBottom = true;
  bool _scrollScheduled = false;
  bool _disposed = false;

  // Replace one draft and accept a result only while its original request is current.
  Future<void> run(
    Future<AgentResult> Function(
      CancellationToken,
      void Function(String),
      void Function(String),
    )
    generate, {
    FutureOr<String> Function(AgentResult)? finish,
  }) async {
    if (loading || _disposed) return;
    final request = _request = CancellationController();
    final input = prompt.text.trim();
    int? draft;
    bool current() => !_disposed && identical(_request, request);
    void publish(String text) {
      if (!current() || request.token.isCancelled) return;
      if (draft == null) {
        if (text.isEmpty) return;
        draft = messages.length;
        messages.add(DashboardMessage.agent(text));
      } else {
        messages[draft!] = DashboardMessage.agent(text);
      }
      _notify();
      _queueScroll();
    }

    loading = true;
    messages.add(DashboardMessage.user(input));
    messages.add(const DashboardMessage.activity('• Thinking - 分析中…'));
    prompt.clear();
    _notify();
    _queueScroll();
    try {
      final answer = await generate(request.token, publish, (activity) {
        if (current() && !request.token.isCancelled) recordActivity(activity);
      });
      request.token.throwIfCancelled();
      if (!current()) return;
      final text = await (finish?.call(answer) ?? answer.text);
      request.token.throwIfCancelled();
      if (!current()) return;
      publish(text);
      lastAnalysis =
          'User analysis request: $input\n\nAnalysis response:\n$text';
      lastAnalysisAt = DateTime.now();
    } catch (error) {
      if (!current()) return;
      final stopped = request.token.isCancelled || isRequestCancelled(error);
      final notice = stopped
          ? '> 已停止生成，未完成的回答未用于更新分析结果。'
          : '> Agent 请求失败：$error';
      if (draft == null) {
        messages.add(DashboardMessage.agent(notice));
      } else {
        final text = messages[draft!].text;
        messages[draft!] = DashboardMessage.agent(
          text.isEmpty ? notice : '$text\n\n$notice',
        );
      }
      _notify();
      _queueScroll();
    } finally {
      if (current()) {
        _request = null;
        loading = false;
        _notify();
      }
    }
  }

  // Preserve the existing clear, stop and activity controls.
  void stop() => _request?.cancel('user stopped');

  void addMessage(DashboardMessage message) {
    if (_disposed) return;
    messages.add(message);
    _notify();
    _queueScroll();
  }

  void recordActivity(String value) =>
      addMessage(DashboardMessage.activity(value));
  void clear() {
    if (loading) return;
    messages.clear();
    lastAnalysis = null;
    lastAnalysisAt = null;
    prompt.clear();
    _atBottom = true;
    showScrollToBottom = false;
    _notify();
  }

  // Schedule at most one follow-scroll per frame while tokens are arriving.
  void _handleScroll() {
    if (_disposed || !scroll.hasClients) return;
    _atBottom = scroll.position.maxScrollExtent - scroll.position.pixels <= 24;
    final visible = !_atBottom && messages.isNotEmpty;
    if (visible != showScrollToBottom) {
      showScrollToBottom = visible;
      _notify();
    }
  }

  void _queueScroll() {
    if (_scrollScheduled) return;
    _scrollScheduled = true;
    final follow = _atBottom;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollScheduled = false;
      if (_disposed || !scroll.hasClients) return;
      if (follow) {
        scrollToBottom();
      } else if (!showScrollToBottom && messages.isNotEmpty) {
        showScrollToBottom = true;
        _notify();
      }
    });
  }

  void scrollToBottom() {
    if (!scroll.hasClients) return;
    unawaited(
      scroll.animateTo(
        scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      ),
    );
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  // The conversation owns its controllers, never the injected business services.
  @override
  void dispose() {
    _disposed = true;
    stop();
    prompt.dispose();
    scroll
      ..removeListener(_handleScroll)
      ..dispose();
    super.dispose();
  }
}
