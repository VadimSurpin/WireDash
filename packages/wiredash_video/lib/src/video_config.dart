import 'dart:convert';

enum RecordingTarget { all, human, vehicle }

class VideoCredentials {
  const VideoCredentials(this.username, this.password);
  final String username, password;
  String encode() => jsonEncode({'username': username, 'password': password});
  static VideoCredentials decode(String? raw) {
    if (raw == null) return const VideoCredentials('', '');
    final j = jsonDecode(raw) as Map<String, dynamic>;
    return VideoCredentials(
      j['username'] as String? ?? '',
      j['password'] as String? ?? '',
    );
  }

  Uri authenticate(Uri uri) => username.isEmpty
      ? uri.replace(userInfo: '')
      : uri.replace(
          userInfo:
              '${Uri.encodeComponent(username)}:${Uri.encodeComponent(password)}',
        );
}

class VideoConfig {
  const VideoConfig({
    this.streamUrl = '',
    this.recorderUrl = '',
    this.channel = 1,
    this.substream = true,
    this.recordings = false,
    this.muted = true,
    this.credentialId = '',
    this.useHomeNetwork = true,
  });
  final String streamUrl, recorderUrl, credentialId;
  final int channel;
  final bool substream, recordings, muted, useHomeNetwork;
  int get liveTrack => channel * 100 + (substream ? 2 : 1);
  int get recordingTrack => channel * 100 + 1;
  Uri get liveUri {
    if (streamUrl.trim().isNotEmpty) {
      final uri = Uri.parse(streamUrl.trim());
      return uri.replace(
        userInfo: '',
        port: uri.hasPort
            ? uri.port
            : uri.scheme == 'rtsps'
            ? 322
            : 554,
      );
    }
    final api = Uri.parse(recorderUrl);
    return Uri(
      scheme: 'rtsp',
      host: api.host,
      port: 554,
      path: '/Streaming/Channels/$liveTrack',
    );
  }

  String? validate() {
    if (channel < 1 || channel > 1024) {
      return 'Channel must be between 1 and 1024.';
    }
    if (streamUrl.isEmpty && recorderUrl.isEmpty) {
      return 'Enter an RTSP URL or a Hikvision recorder address.';
    }
    try {
      final uri = liveUri;
      if (!['rtsp', 'rtsps'].contains(uri.scheme) ||
          uri.host.isEmpty ||
          uri.hasFragment ||
          uri.port < 1 ||
          uri.port > 65535) {
        return 'Enter a valid rtsp:// or rtsps:// stream URL.';
      }
      if (recordings || streamUrl.isEmpty) {
        final api = Uri.parse(recorderUrl);
        if (!['http', 'https'].contains(api.scheme) ||
            api.host.isEmpty ||
            api.userInfo.isNotEmpty ||
            (api.path.isNotEmpty && api.path != '/') ||
            api.hasQuery ||
            api.hasFragment) {
          return 'Enter the recorder base address, such as https://192.168.1.64.';
        }
      }
    } catch (_) {
      return 'Check the video and recorder addresses.';
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
    'streamUrl': streamUrl.isEmpty
        ? ''
        : Uri.parse(streamUrl).replace(userInfo: '').toString(),
    'recorderUrl': recorderUrl,
    'channel': channel,
    'substream': substream,
    'recordings': recordings,
    'muted': muted,
    'credentialId': credentialId,
    'useHomeNetwork': useHomeNetwork,
  };
  factory VideoConfig.fromJson(Map<String, dynamic> j) => VideoConfig(
    streamUrl: j['streamUrl'] as String? ?? '',
    recorderUrl: j['recorderUrl'] as String? ?? '',
    channel: (j['channel'] as num?)?.toInt() ?? 1,
    substream: j['substream'] as bool? ?? true,
    recordings: j['recordings'] as bool? ?? false,
    muted: j['muted'] as bool? ?? true,
    credentialId: j['credentialId'] as String? ?? '',
    useHomeNetwork: j['useHomeNetwork'] as bool? ?? true,
  );

  /// DVRs often return their LAN address. Keep the exact recording path/query
  /// but use the explicitly configured RTSP endpoint, never a response's host.
  Uri playbackUri(String raw) {
    final returned = Uri.parse(raw.trim());
    if (!['rtsp', 'rtsps'].contains(returned.scheme) || returned.path.isEmpty) {
      throw const FormatException(
        'The recorder returned an invalid playback address.',
      );
    }
    final live = liveUri;
    return returned.replace(
      scheme: live.scheme,
      host: live.host,
      port: live.port,
      userInfo: '',
    );
  }
}
