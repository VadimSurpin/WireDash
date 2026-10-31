enum RecordingEvent {
  scheduled,
  motion,
  alarm,
  lineCrossing,
  intrusion,
  human,
  vehicle,
  manual,
  other;

  String get label => switch (this) {
    scheduled => 'Continuous recording',
    motion => 'Motion',
    alarm => 'Alarm',
    lineCrossing => 'Line crossing',
    intrusion => 'Intrusion',
    human => 'Person',
    vehicle => 'Vehicle',
    manual => 'Manual recording',
    other => 'Event recording',
  };

  static RecordingEvent? fromDescriptor(String value) {
    final type = value.trim().split('/').last.toLowerCase();
    return switch (type) {
      'timing' || 'cmr' || 'continuous' || 'scheduled' => scheduled,
      'motion' || 'vmd' || 'motiondetection' => motion,
      'alarm' || 'alarmrecord' => alarm,
      'linedetection' || 'crossline' || 'linecrossing' => lineCrossing,
      'fielddetection' || 'intrusion' => intrusion,
      'human' ||
      'humandetection' ||
      'humanrecognition' ||
      'humanbodydetection' ||
      'facedetection' ||
      'facecapture' => human,
      'vehicle' || 'vehicledetection' => vehicle,
      'manual' || 'manualrecord' => manual,
      'edr' ||
      'event' ||
      'mixedtargetdetection' ||
      'alarmandmotion' ||
      'alarmormotion' => other,
      _ => null,
    };
  }
}
