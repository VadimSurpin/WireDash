import 'dart:convert';
import 'dart:io';

/// ZigDash's identity at Home Assistant's login: a page on GitHub Pages that
/// names `zigdash://auth` as its return link with `<link rel="redirect_uri">`
/// (docs/design/ha-import.md, Q1). Home Assistant fetches it during login
/// and checks it again when a refresh token is used.
const haClientId = 'https://giladtamam.github.io/zigdash/ha/';

/// How a Home Assistant sign-in is kept in the password slot of a home that
/// connects through Home Assistant (docs/design/ha-route.md): a refresh
/// token from the login page carries this prefix and is traded for a short
/// access token on every connect; a pasted long-lived token is stored as is.
const haRefreshPrefix = 'refresh:';

String haStoredRefresh(String refreshToken) => '$haRefreshPrefix$refreshToken';

bool isHaRefresh(String stored) => stored.startsWith(haRefreshPrefix);

/// Why a stored sign-in could not become an access token.
enum HaTokenError {
  /// Home Assistant refused the refresh token: it was revoked, or the user
  /// signed out of ZigDash under Profile › Security.
  rejected,

  /// Nothing answered, or the answer was not Home Assistant's.
  unreachable,
}

typedef HaAccessToken = ({String? token, HaTokenError? error});

/// Trades a refresh token for an access token (`/auth/token`,
/// `grant_type=refresh_token`); Home Assistant requires the same client id
/// the login used.
Future<HaAccessToken> refreshHaAccessToken(
  Uri base,
  String refreshToken, {
  Duration timeout = const Duration(seconds: 8),
}) async {
  final client = HttpClient()..connectionTimeout = timeout;
  try {
    final request = await client
        .postUrl(base.replace(path: '/auth/token'))
        .timeout(timeout);
    request.headers.contentType = ContentType(
      'application',
      'x-www-form-urlencoded',
      charset: 'utf-8',
    );
    request.write(
      Uri(
        queryParameters: {
          'grant_type': 'refresh_token',
          'refresh_token': refreshToken,
          'client_id': haClientId,
        },
      ).query,
    );
    final response = await request.close().timeout(timeout);
    final body = await response.transform(utf8.decoder).join().timeout(timeout);
    if (response.statusCode == 200) {
      final json = jsonDecode(body);
      final access = json is Map ? json['access_token'] : null;
      if (access is String && access.isNotEmpty) {
        return (token: access, error: null);
      }
      return (token: null, error: HaTokenError.unreachable);
    }
    // 400 invalid_grant for a revoked token; 401/403 likewise.
    return (
      token: null,
      error: response.statusCode >= 400 && response.statusCode < 500
          ? HaTokenError.rejected
          : HaTokenError.unreachable,
    );
  } catch (_) {
    return (token: null, error: HaTokenError.unreachable);
  } finally {
    client.close(force: true);
  }
}

/// The access token for a stored sign-in: a long-lived token is itself one;
/// a refresh token is exchanged first.
Future<HaAccessToken> haAccessTokenFor(Uri base, String stored) =>
    isHaRefresh(stored)
    ? refreshHaAccessToken(base, stored.substring(haRefreshPrefix.length))
    : Future.value((token: stored, error: null));
