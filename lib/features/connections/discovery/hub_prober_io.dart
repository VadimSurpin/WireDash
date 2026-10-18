import 'dart:convert';
import 'dart:io';

import 'hub_probe.dart';

HubProber createHubProber() => const HttpHubProber();

/// The scan's second look (2.9.3): a slower first connect.
HubProber createPatientHubProber() =>
    const HttpHubProber(tcpTimeout: Duration(milliseconds: 1500));

/// Identifies a hub by fetching the first bytes of its web page: a fast TCP
/// connect first (closed ports refuse at once), then a plain HTTP GET, and
/// HTTPS when plain fails (Home Assistant with SSL on serves only HTTPS).
/// Reads at most [maxBytes]; never throws.
class HttpHubProber implements HubProber {
  const HttpHubProber({
    this.tcpTimeout = const Duration(milliseconds: 500),
    this.httpTimeout = const Duration(milliseconds: 1500),
    this.maxBytes = 65536,
  });

  final Duration tcpTimeout;
  final Duration httpTimeout;
  final int maxBytes;

  @override
  Future<HubKind?> probe(String host, int port) async {
    try {
      final sock = await Socket.connect(host, port, timeout: tcpTimeout);
      sock.destroy();
    } catch (_) {
      return null;
    }
    for (final scheme in const ['http', 'https']) {
      final body = await _fetch(
        Uri(scheme: scheme, host: host, port: port, path: '/'),
      );
      if (body == null) continue;
      return hubKindOfPage(body);
    }
    return null;
  }

  Future<String?> _fetch(Uri url) async {
    final client = HttpClient()
      ..connectionTimeout = httpTimeout
      ..badCertificateCallback = (_, __, ___) => true;
    try {
      final request = await client.getUrl(url).timeout(httpTimeout);
      request.followRedirects = true;
      final response = await request.close().timeout(httpTimeout);
      final bytes = <int>[];
      await for (final chunk in response.timeout(httpTimeout)) {
        bytes.addAll(chunk);
        if (bytes.length >= maxBytes) break;
      }
      return utf8.decode(bytes, allowMalformed: true);
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }
}
