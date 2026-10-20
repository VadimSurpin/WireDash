/// Where Home Assistant is, from what the user typed or the scan saw:
/// `192.168.1.20`, `homeassistant.local:8123`, `http://…/lovelace/0`,
/// `https://xyz.ui.nabu.casa`. Without a scheme, http on 8123. Null when
/// nothing usable was typed.
Uri? haBaseUri(String input) {
  var text = input.trim();
  if (text.isEmpty) return null;
  final hasScheme = text.contains('://');
  if (!hasScheme) text = 'http://$text';
  final uri = Uri.tryParse(text);
  if (uri == null || uri.host.isEmpty) return null;
  if (uri.scheme != 'http' && uri.scheme != 'https') return null;
  return Uri(
    scheme: uri.scheme,
    host: uri.host,
    port: uri.hasPort ? uri.port : (hasScheme ? null : 8123),
  );
}

/// Home Assistant's WebSocket API for [base]: `ws(s)://host:port/api/websocket`.
Uri haWebSocketUri(Uri base) => base.replace(
  scheme: base.scheme == 'https' ? 'wss' : 'ws',
  path: '/api/websocket',
);

/// The address as stored on a Home Assistant home's row: the base URL text,
/// without a trailing slash, so `haBaseUri` reads it back unchanged.
String haAddressText(Uri base) {
  final text = base.toString();
  return text.endsWith('/') ? text.substring(0, text.length - 1) : text;
}
