import 'recording_event.dart';

/// An actual stored camera capture; its time is independent of pre-recording.
class RecordingPicture {
  const RecordingPicture(this.time, this.uri, this.events);
  final DateTime time;
  final Uri uri;
  final List<RecordingEvent> events;
}
