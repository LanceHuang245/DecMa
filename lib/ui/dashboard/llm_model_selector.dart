import 'dart:async';

import 'package:dio/dio.dart';
import 'package:fluent_ui/fluent_ui.dart';

import '../../domain/models/app_settings.dart';
import '../../domain/models/llm_model_info.dart';
import '../../utils/network.dart';
import '../core/reasoning_effort_labels.dart';

// Keep catalog requests local to the selected connection and cancel stale work.
class LlmModelSelector extends StatefulWidget {
  const LlmModelSelector({
    super.key,
    required this.llm,
    required this.loadModels,
    required this.onChanged,
    required this.onReasoningChanged,
    required this.enabled,
  });

  final LlmSettings llm;
  final Future<List<LlmModelInfo>> Function(CancelToken) loadModels;
  final Future<void> Function(String) onChanged;
  final Future<void> Function(String?) onReasoningChanged;
  final bool enabled;

  @override
  State<LlmModelSelector> createState() => _LlmModelSelectorState();
}

class _LlmModelSelectorState extends State<LlmModelSelector> {
  CancelToken? _cancel;
  List<LlmModelInfo> _models = const [];
  bool _loading = false, _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(LlmModelSelector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.llm.id != widget.llm.id ||
        oldWidget.llm.provider != widget.llm.provider ||
        oldWidget.llm.endpoint != widget.llm.endpoint) {
      _models = const [];
      unawaited(_load());
    }
  }

  Future<void> _load() async {
    _cancel?.cancel();
    final cancel = _cancel = CancelToken();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final models = await widget.loadModels(cancel);
      if (mounted && !cancel.isCancelled) setState(() => _models = models);
    } catch (error) {
      if (mounted && !cancel.isCancelled && !isRequestCancelled(error)) {
        setState(() => _error = '模型列表获取失败：$error');
      }
    } finally {
      if (mounted && !cancel.isCancelled) setState(() => _loading = false);
    }
  }

  Future<void> _select(String? value, {bool reasoning = false}) async {
    if (value == null || (!reasoning && value == widget.llm.model)) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (reasoning) {
        await widget.onReasoningChanged(value);
      } else {
        await widget.onChanged(value);
      }
    } catch (error) {
      if (mounted) setState(() => _error = '模型保存失败：$error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Retain the saved model even when a catalog is empty or unavailable.
    final models = {
      ..._models.map((model) => model.id),
      if (widget.llm.model.isNotEmpty) widget.llm.model,
    }.toList()..sort();
    final advertisedEfforts = _models
        .where((model) => model.id == widget.llm.model)
        .firstOrNull
        ?.reasoningEfforts;
    // Exclude default/off/minimal choices from catalogs and saved values.
    final efforts = {
      ...(advertisedEfforts ?? widget.llm.provider.standardReasoningEfforts),
      ?widget.llm.reasoningEffort,
    }..removeAll(['', 'default', 'none', 'minimal']);
    final selectedEffort = efforts.contains(widget.llm.reasoningEffort)
        ? widget.llm.reasoningEffort
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Tooltip(
                message: widget.llm.name,
                child: Text(
                  widget.llm.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: ComboBox<String>(
                value: widget.llm.model.isEmpty ? null : widget.llm.model,
                isExpanded: true,
                placeholder: Text(_loading ? '正在获取模型…' : '选择模型'),
                items: [
                  for (final model in models)
                    ComboBoxItem(value: model, child: Text(model)),
                ],
                onChanged: widget.enabled && !_saving ? _select : null,
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 88,
              child: Tooltip(
                message: _loading
                    ? '正在获取思考等级'
                    : efforts.isEmpty
                    ? '此模型不支持选择思考等级'
                    : advertisedEfforts == null
                    ? '思考等级：通用选项，具体支持范围由服务端决定'
                    : '思考等级',
                child: ComboBox<String>(
                  value: selectedEffort,
                  isExpanded: true,
                  placeholder: const Text('思考等级'),
                  items: [
                    for (final effort in efforts)
                      ComboBoxItem(
                        value: effort,
                        child: Text(reasoningEffortLabels[effort] ?? effort),
                      ),
                  ],
                  onChanged: widget.enabled && !_saving && efforts.isNotEmpty
                      ? (value) => _select(value, reasoning: true)
                      : null,
                ),
              ),
            ),
            const SizedBox(width: 4),
            Tooltip(
              message: '刷新模型列表',
              child: IconButton(
                icon: const Icon(FluentIcons.refresh),
                onPressed: _loading ? null : _load,
              ),
            ),
          ],
        ),
        if (_error != null) ...[
          const SizedBox(height: 6),
          Text(
            _error!,
            style: const TextStyle(color: Colors.errorPrimaryColor),
          ),
        ],
      ],
    );
  }

  @override
  void dispose() {
    _cancel?.cancel();
    super.dispose();
  }
}
