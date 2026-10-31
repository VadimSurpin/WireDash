import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'video_config.dart';

/// RFC 7616 challenge authentication. Credentials are sent only to the
/// configured origin; callers do not follow DVR redirects.
class DigestAuth {
  DigestAuth(this.credentials, {String Function()? cnonce})
    : cnonce =
          cnonce ??
          (() => List.generate(
            16,
            (_) => Random.secure().nextInt(256),
          ).map((n) => n.toRadixString(16).padLeft(2, '0')).join());
  final VideoCredentials credentials;
  final String Function() cnonce;
  int _count = 0;
  String? _nonce;
  String authorization(String challenge, String method, Uri uri, String body) {
    String quote(String s) =>
        '"${s.replaceAll('\\', '\\\\').replaceAll('"', '\\"')}"';
    if (challenge.toLowerCase().startsWith('basic ')) {
      return 'Basic ${base64Encode(utf8.encode('${credentials.username}:${credentials.password}'))}';
    }
    if (!challenge.toLowerCase().startsWith('digest ')) {
      throw const FormatException('Recorder authentication is unsupported.');
    }
    final parameters = <String, String>{};
    final pattern = RegExp(r'(\w+)\s*=\s*(?:"((?:\\.|[^"\\])*)"|([^,\s]+))');
    for (final m in pattern.allMatches(challenge.substring(7))) {
      parameters[m[1]!.toLowerCase()] = (m[2] ?? m[3]!).replaceAllMapped(
        RegExp(r'\\(.)'),
        (m) => m[1]!,
      );
    }
    final realm = parameters['realm'], nonce = parameters['nonce'];
    if (realm == null || nonce == null) {
      throw const FormatException('Invalid authentication challenge.');
    }
    if (_nonce != nonce) {
      _nonce = nonce;
      _count = 0;
    }
    final algorithm = (parameters['algorithm'] ?? 'MD5').toUpperCase();
    if (!['MD5', 'MD5-SESS', 'SHA-256', 'SHA-256-SESS'].contains(algorithm)) {
      throw const FormatException('Recorder digest algorithm is unsupported.');
    }
    String hash(String s) => (algorithm.startsWith('SHA-256') ? sha256 : md5)
        .convert(utf8.encode(s))
        .toString();
    final path = uri.path.isEmpty ? '/' : uri.path;
    final target = '$path${uri.hasQuery ? '?${uri.query}' : ''}';
    final clientNonce = cnonce();
    final nc = (++_count).toRadixString(16).padLeft(8, '0');
    var ha1 = hash('${credentials.username}:$realm:${credentials.password}');
    if (algorithm.endsWith('-SESS')) ha1 = hash('$ha1:$nonce:$clientNonce');
    final options = parameters['qop']?.split(',').map((s) => s.trim()).toList();
    final qop = options == null
        ? null
        : options.contains('auth')
        ? 'auth'
        : options.contains('auth-int')
        ? 'auth-int'
        : null;
    if (options != null && qop == null) {
      throw const FormatException('Recorder digest quality is unsupported.');
    }
    final ha2 = hash(
      '$method:$target${qop == 'auth-int' ? ':${hash(body)}' : ''}',
    );
    final response = hash(
      qop == null
          ? '$ha1:$nonce:$ha2'
          : '$ha1:$nonce:$nc:$clientNonce:$qop:$ha2',
    );
    return 'Digest ${['username=${quote(credentials.username)}', 'realm=${quote(realm)}', 'nonce=${quote(nonce)}', 'uri=${quote(target)}', 'response=${quote(response)}', 'algorithm=$algorithm', if (parameters['opaque'] != null) 'opaque=${quote(parameters['opaque']!)}', if (qop != null) 'qop=$qop', if (qop != null) 'nc=$nc', if (qop != null || algorithm.endsWith('-SESS')) 'cnonce=${quote(clientNonce)}'].join(', ')}';
  }
}
