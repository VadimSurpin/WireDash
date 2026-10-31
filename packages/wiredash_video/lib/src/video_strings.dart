import 'package:flutter/widgets.dart';
import 'video_messages.g.dart';

/// Follows the host's selected locale, including locale changes and RTL. A
/// standalone plugin consumer needs no WireDash app dependency or delegate.
class VideoStrings {
  const VideoStrings(this.language);
  final String language;
  factory VideoStrings.of(BuildContext context) =>
      VideoStrings(Localizations.maybeLocaleOf(context)?.languageCode ?? 'en');

  String message(String key, [Map<String, Object> values = const {}]) {
    var text =
        (videoMessages[language] ?? videoMessages['en']!)[key] ??
        videoMessages['en']![key]!;
    for (final entry in values.entries) {
      text = text.replaceAll('{${entry.key}}', entry.value.toString());
    }
    return text;
  }

  /// Protocol/model errors remain locale-independent until presentation. Status
  /// numbers and sanitized recorder codes retain their original spelling.
  String text(String english) {
    final key = videoMessageIds[english];
    if (key != null) return message(key);
    final rejected = RegExp(
      r'^(Event|Recording) search rejected by the recorder \(([^)]*)\)\.$',
    ).firstMatch(english);
    if (rejected != null) {
      return message(
        rejected[1] == 'Event' ? 'eventRejected' : 'recordingRejected',
        {'details': rejected[2]!},
      );
    }
    final denied = RegExp(
      r'^Recorder access denied\. Enable recording playback permission(?: \(([a-zA-Z][a-zA-Z0-9_]{0,63})\))?\.$',
    ).firstMatch(english);
    if (denied != null) {
      return message('accessDenied', {
        'details': denied[1] == null ? '' : ' (${denied[1]})',
      });
    }
    return english;
  }

  String? nullable(String? value) => value == null ? null : text(value);

  String duration(Duration value) => value.inHours > 0
      ? message('durationHours', {
          'hours': value.inHours,
          'minutes': value.inMinutes % 60,
        })
      : value.inMinutes > 0
      ? message('durationMinutes', {
          'minutes': value.inMinutes,
          'seconds': value.inSeconds % 60,
        })
      : message('durationSeconds', {'seconds': value.inSeconds});
}

extension VideoI18n on BuildContext {
  VideoStrings get videoStrings => VideoStrings.of(this);
}
