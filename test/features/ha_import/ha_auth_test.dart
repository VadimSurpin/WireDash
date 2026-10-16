import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:zigdash/features/ha_import/ha_auth.dart';

/// A fake Home Assistant token endpoint: trades `the-code` for tokens when
/// the PKCE verifier matches, and records revocations.
Future<(HttpServer, List<String>)> _fakeAuth({
  required String challenge,
}) async {
  final revoked = <String>[];
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    final form = Uri.splitQueryString(await utf8.decodeStream(request));
    final response = request.response;
    if (request.uri.path == '/auth/token' &&
        form['grant_type'] == 'authorization_code' &&
        form['code'] == 'the-code' &&
        form['client_id'] == haClientId &&
        pkceChallenge(form['code_verifier'] ?? '') == challenge) {
      response.headers.contentType = ContentType.json;
      response.write(
        jsonEncode({
          'access_token': 'access',
          'refresh_token': 'refresh',
          'expires_in': 1800,
          'token_type': 'Bearer',
        }),
      );
    } else if (request.uri.path == '/auth/revoke') {
      revoked.add(form['token'] ?? '');
    } else {
      response.statusCode = 400;
    }
    await response.close();
  });
  return (server, revoked);
}

void main() {
  // The test binding answers every HttpClient request with 400; these tests
  // talk to a real local server.
  setUpAll(() => HttpOverrides.global = null);

  test('PKCE S256: base64url of SHA-256, unpadded', () {
    // Checked against Python's hashlib and base64.urlsafe_b64encode.
    expect(
      pkceChallenge('dBjftJeZ4CVP-mJ92K9qqVIhIMH8AZ7ByIaUoOpMlBk'),
      'dOBKL7AO2jqUQZBCqNMAhE3-xhkUaDFkbxZYD2-c72E',
    );
    final v = pkceVerifier();
    expect(v, hasLength(64));
    expect(RegExp(r'^[A-Za-z0-9\-._~]+$').hasMatch(v), isTrue);
  });

  test('the login page link carries ZigDash\'s identity and return', () {
    final uri = haAuthorizeUri(
      Uri.parse('http://192.168.68.52:8123'),
      state: 's',
      challenge: 'c',
    );
    expect(uri.path, '/auth/authorize');
    expect(uri.queryParameters, {
      'response_type': 'code',
      'client_id': 'https://giladtamam.github.io/zigdash/ha/',
      'redirect_uri': 'zigdash://auth',
      'state': 's',
      'code_challenge': 'c',
      'code_challenge_method': 'S256',
    });
  });

  test('sign in, trade the code, revoke', () async {
    // A fixed random source makes the verifier known up front, so the fake
    // token endpoint can check the PKCE pair.
    final challenge = pkceChallenge(pkceVerifier(_Fixed()));
    final (server, revoked) = await _fakeAuth(challenge: challenge);
    addTearDown(server.close);
    final base = Uri.parse('http://127.0.0.1:${server.port}');
    late Uri opened;
    final result = await signInToHa(
      base,
      random: _Fixed(),
      browser: (url) async {
        opened = url;
        return 'zigdash://auth?code=the-code&state=${url.queryParameters['state']}';
      },
    );
    expect(opened.queryParameters['code_challenge'], challenge);
    expect(result.error, isNull);
    expect(result.accessToken, 'access');
    expect(result.refreshToken, 'refresh');

    await revokeHaSignIn(base, 'refresh');
    expect(revoked, ['refresh']);
  });

  test(
    'closing the login tab is a cancel; no token endpoint is a failure',
    () async {
      final cancelled = await signInToHa(
        Uri.parse('http://127.0.0.1:1'),
        browser: (_) async => throw StateError('closed'),
      );
      expect(cancelled.error, HaSignInError.cancelled);
      final noEndpoint = await signInToHa(
        Uri.parse('http://127.0.0.1:1'),
        browser: (url) async =>
            'zigdash://auth?code=the-code&state=${url.queryParameters['state']}',
      );
      expect(noEndpoint.error, HaSignInError.failed);
    },
  );

  test('a returned error or a wrong state is refused', () async {
    final noCode = await signInToHa(
      Uri.parse('http://127.0.0.1:1'),
      browser: (_) async => 'zigdash://auth?error=access_denied',
    );
    expect(noCode.error, HaSignInError.refused);
    final wrongState = await signInToHa(
      Uri.parse('http://127.0.0.1:1'),
      browser: (_) async => 'zigdash://auth?code=x&state=not-ours',
    );
    expect(wrongState.error, HaSignInError.refused);
  });
}

/// The same "random" values every time, so two sign-ins share a verifier.
class _Fixed implements Random {
  var _i = 0;
  @override
  int nextInt(int max) => (_i++ * 7) % max;
  @override
  bool nextBool() => false;
  @override
  double nextDouble() => 0;
}
