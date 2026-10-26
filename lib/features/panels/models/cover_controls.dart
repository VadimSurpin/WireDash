enum CoverButtonIcon {
  up,
  down,
  left,
  right,
  stop,
  rollerOpen,
  rollerClosed,
  gateOpen,
  gateClosed,
  gatePartial,
}

class CoverButtonConfig {
  const CoverButtonConfig({this.visible = true, this.title, this.icon});
  final bool visible;
  final String? title;
  final CoverButtonIcon? icon;

  CoverButtonConfig copyWith({
    bool? visible,
    String? title,
    CoverButtonIcon? icon,
  }) => CoverButtonConfig(
    visible: visible ?? this.visible,
    title: title ?? this.title,
    icon: icon ?? this.icon,
  );

  Map<String, dynamic> toJson() => {
    'visible': visible,
    if (title != null) 'title': title,
    if (icon != null) 'icon': icon!.name,
  };

  factory CoverButtonConfig.fromJson(Map<String, dynamic> json) =>
      CoverButtonConfig(
        visible: json['visible'] as bool? ?? true,
        title: json['title'] as String?,
        icon: CoverButtonIcon.values
            .where((v) => v.name == json['icon'])
            .firstOrNull,
      );
}

/// MQTT IDs, not translated control titles. Commands append `/on`.
class WirenBoardCoverBinding {
  const WirenBoardCoverBinding({required this.deviceId, required this.number});
  final String deviceId;
  final int number;
  String get openTopic => '/devices/$deviceId/controls/Curtain $number Open';
  String get closeTopic => '/devices/$deviceId/controls/Curtain $number Close';
  Map<String, dynamic> toJson() => {'deviceId': deviceId, 'number': number};
  factory WirenBoardCoverBinding.fromJson(Map<String, dynamic> json) {
    final id = json['deviceId'] as String;
    final number = json['number'] as int;
    if (id.isEmpty || id.contains('/') || number < 1 || number > 3) {
      throw const FormatException('Invalid WB curtain binding');
    }
    return WirenBoardCoverBinding(deviceId: id, number: number);
  }
}
