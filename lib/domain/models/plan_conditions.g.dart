// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'plan_conditions.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

PlanConditions _$PlanConditionsFromJson(Map<String, dynamic> json) =>
    PlanConditions(
      version: (json['version'] as num?)?.toInt() ?? 1,
      strategy: json['strategy'] as String? ?? 'UNKNOWN',
      regime: json['regime'] as String? ?? 'UNKNOWN',
      triggerType: json['trigger_type'] as String?,
      triggerPrice: (json['trigger_price'] as num?)?.toDouble(),
      volumeMultiple: (json['volume_multiple'] as num?)?.toDouble(),
      timeframeMinutes: (json['timeframe_minutes'] as num?)?.toInt() ?? 15,
      stopReference: json['stop_reference'] as String? ?? 'LastPrice',
      cancellationPrice: (json['cancellation_price'] as num?)?.toDouble(),
      expiresAt: json['expires_at'] == null
          ? null
          : DateTime.parse(json['expires_at'] as String),
    );

Map<String, dynamic> _$PlanConditionsToJson(PlanConditions instance) =>
    <String, dynamic>{
      'version': instance.version,
      'strategy': instance.strategy,
      'regime': instance.regime,
      'trigger_type': instance.triggerType,
      'trigger_price': instance.triggerPrice,
      'volume_multiple': instance.volumeMultiple,
      'cancellation_price': instance.cancellationPrice,
      'timeframe_minutes': instance.timeframeMinutes,
      'stop_reference': instance.stopReference,
      'expires_at': instance.expiresAt?.toIso8601String(),
    };
