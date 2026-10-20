import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../../mqtt/ha_token.dart';

import 'package:crypto/crypto.dart';

export '../../mqtt/ha_token.dart' show haClientId;

const haRedirectUri = 'zigdash://auth';
const haCallbackScheme = 'zigdash';

/// Why signing in did not give a token.
enum HaSignInError {
  /// The user closed the login tab.
  cancelled,

  /// Home Assistant sent back an error or no code (often: it could not read
  /// ZigDash's page, so it refused the return link).
  refused,

  /// The returned code could not be turned into a token.
  failed,
}

typedef HaSignInResult = ({
  String? accessToken,
  String? refreshToken,
  HaSignInError? error,
});

/// Opens [url] in the browser and returns the URL Home Assistant sent the
/// user back to, or throws when the user closed it.
typedef BrowserSignIn = Future<String> Function(Uri url);

/// A random PKCE code verifier (RFC 7636): 64 URL-safe characters.
String pkceVerifier([Random? random]) {
  final r = random ?? Random.secure();
  const chars =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';
  return String.fromCharCodes([
    for (var i = 0; i < 64; i++) chars.codeUnitAt(r.nextInt(chars.length)),
  ]);
}

/// The S256 challenge for [verifier]: base64url of its SHA-256, unpadded.
String pkceChallenge(String verifier) => base64Url
    .encode(sha256.convert(ascii.encode(verifier)).bytes)
    .replaceAll('=', '');

/// Home Assistant's login page for ZigDash at [base].
Uri haAuthorizeUri(
  Uri base, {
  required String state,
  required String challenge,
}) => base.replace(
  path: '/auth/authorize',
  queryParameters: {
    'response_type': 'code',
    'client_id': haClientId,
    'redirect_uri': haRedirectUri,
    'state': state,
    'code_challenge': challenge,
    'code_challenge_method': 'S256',
  },
);

/// Signs in at Home Assistant's own login page (in the browser, so ZigDash
/// never sees the password), then trades the returned code for tokens.
/// Home Assistant before 2026.10 ignores the PKCE fields.
Future<HaSignInResult> signInToHa(
  Uri base, {
  required BrowserSignIn browser,
  Random? random,
}) async {
  final verifier = pkceVerifier(random);
  final state = pkceVerifier(random).substring(0, 24);
  final String returned;
  try {
    returned = await browser(
      haAuthorizeUri(base, state: state, challenge: pkceChallenge(verifier)),
    );
  } catch (_) {
    return (
      accessToken: null,
      refreshToken: null,
      error: HaSignInError.cancelled,
    );
  }
  final back = Uri.tryParse(returned);
  final code = back?.queryParameters['code'];
  if (back == null || code == null || back.queryParameters['state'] != state) {
    return (
      accessToken: null,
      refreshToken: null,
      error: HaSignInError.refused,
    );
  }
  final tokens = await _post(base, '/auth/token', {
    'grant_type': 'authorization_code',
    'code': code,
    'client_id': haClientId,
    'code_verifier': verifier,
  });
  final access = tokens?['access_token'];
  if (access is! String) {
    return (accessToken: null, refreshToken: null, error: HaSignInError.failed);
  }
  final refresh = tokens!['refresh_token'];
  return (
    accessToken: access,
    refreshToken: refresh is String ? refresh : null,
    error: null,
  );
}

/// Ends the sign-in: Home Assistant drops the refresh token and every
/// access token made from it (decision Q2: import once, keep nothing).
Future<void> revokeHaSignIn(Uri base, String refreshToken) async {
  await _post(base, '/auth/revoke', {'token': refreshToken});
}

Future<Map<String, Object?>?> _post(
  Uri base,
  String path,
  Map<String, String> form,
) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
  try {
    final request = await client.postUrl(base.replace(path: path));
    request.headers.contentType = ContentType(
      'application',
      'x-www-form-urlencoded',
      charset: 'utf-8',
    );
    request.write(Uri(queryParameters: form).query);
    final response = await request.close().timeout(const Duration(seconds: 10));
    final body = await response.transform(utf8.decoder).join();
    if (response.statusCode != 200) return null;
    if (body.isEmpty) return const {};
    final decoded = jsonDecode(body);
    return decoded is Map ? Map<String, Object?>.from(decoded) : null;
  } catch (_) {
    return null;
  } finally {
    client.close(force: true);
  }
}
