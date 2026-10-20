import 'package:json_annotation/json_annotation.dart';

part 'plan_conditions.g.dart';

@JsonSerializable(fieldRename: FieldRename.snake)
// Machine-checkable entry rules; missing legacy rules remain unverified.
class PlanConditions {
  const PlanConditions({
    this.version = 1,
    this.strategy = 'UNKNOWN',
    this.regime = 'UNKNOWN',
    this.triggerType,
    this.triggerPrice,
    this.volumeMultiple,
    this.timeframeMinutes = 15,
    this.stopReference = 'LastPrice',
    this.cancellationPrice,
    this.expiresAt,
  });

  final int version;
  final String strategy, regime;
  final String? triggerType;
  final double? triggerPrice, volumeMultiple, cancellationPrice;
  final int timeframeMinutes;
  final String stopReference;
  final DateTime? expiresAt;

  bool get supported =>
      (version == 1 || version == 2) &&
      (triggerType != 'VOLUME_ABOVE_MULTIPLE' || volumeMultiple != null) &&
      const [
        'CLOSE_ABOVE',
        'CLOSE_BELOW',
        'TOUCH_ZONE_AND_CLOSE_INSIDE',
        'VOLUME_ABOVE_MULTIPLE',
        'BREAKOUT_RETEST',
      ].contains(triggerType) &&
      const [5, 15, 60, 240].contains(timeframeMinutes) &&
      (volumeMultiple == null ||
          (volumeMultiple!.isFinite && volumeMultiple! > 0)) &&
      (!const [
            'CLOSE_ABOVE',
            'CLOSE_BELOW',
            'BREAKOUT_RETEST',
            'VOLUME_ABOVE_MULTIPLE',
          ].contains(triggerType) ||
          (triggerPrice?.isFinite == true && triggerPrice! > 0));

  Map<String, dynamic> toJson() => _$PlanConditionsToJson(this);

  factory PlanConditions.fromJson(Map<String, dynamic> json) =>
      _$PlanConditionsFromJson(json);
}
