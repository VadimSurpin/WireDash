// Connecting a home through Home Assistant (docs/design/ha-route.md,
// route A): the address the user opens Home Assistant with, a sign-in,
// and a check that Home Assistant's MQTT is usable; then the setup
// coordinator reads and reviews the devices like any other candidate.
//
// The sign-in is kept: a refresh token from the login page (stored as
// `refresh:<token>`) or a pasted long-lived token, in the same secure
// storage as broker passwords, under the home's row.

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../../mqtt/ha_address.dart';
import '../../../mqtt/ha_mqtt_client.dart';
import '../../../mqtt/ha_token.dart';
import '../../ha_import/ha_auth.dart';
import '../../ha_import/ha_import_controller.dart' show HaSignIn;

/// Why connecting stopped, for the screen.
enum HaConnectProblem {
  noAddress,
  noToken,
  unreachable,
  notHomeAssistant,
  certificate,
  signInRefused,
  signInFailed,
  badToken,
  notAdmin,
  noMqtt,
}

sealed class HaConnectState {
  const HaConnectState();
}

/// Waiting for the address and a sign-in; [problem] after a failed try.
class HaConnectAsk extends HaConnectState {
  const HaConnectAsk({required this.address, this.problem});
  final String address;
  final HaConnectProblem? problem;
}

/// Signing in, or checking Home Assistant.
class HaConnectChecking extends HaConnectState {
  const HaConnectChecking();
}

/// Home Assistant accepted the sign-in and its MQTT is usable; the
/// coordinator took over (devices, review).
class HaConnectDone extends HaConnectState {
  const HaConnectDone();
}

/// Connects once to Home Assistant with [stored] (the stored form of the
/// sign-in) and says what is wrong, or null when it is usable.
typedef HaProbe = Future<HaConnectProblem?> Function(Uri base, String stored);

/// Hands the checked home to the setup coordinator.
typedef HaAdopt = Future<void> Function(Uri address, String signIn);

/// The real probe: a [HaMqttClient] connect, then disconnect.
Future<HaConnectProblem?> probeHomeAssistant(Uri base, String stored) async {
  final client = HaMqttClient(haWebSocketUri(base), 'zd-check')
    ..connectTimeoutPeriod = 12000
    ..keepAlivePeriod = 0;
  try {
    await client.connect(null, stored);
  } on TimeoutException {
    return HaConnectProblem.unreachable;
  } on HandshakeException {
    return HaConnectProblem.certificate;
  } on WebSocketException {
    // Something answered HTTP but refused the upgrade: not Home Assistant.
    return HaConnectProblem.notHomeAssistant;
  } catch (_) {
    return HaConnectProblem.unreachable;
  } finally {
    client.disconnect();
  }
  return switch (client.problem) {
    null => null,
    HaClientProblem.signInRejected => HaConnectProblem.badToken,
    HaClientProblem.notAdmin => HaConnectProblem.notAdmin,
    HaClientProblem.noMqtt => HaConnectProblem.noMqtt,
    HaClientProblem.unreachable => HaConnectProblem.unreachable,
  };
}

class HaConnectController extends ValueNotifier<HaConnectState> {
  HaConnectController({
    required String address,
    required HaAdopt adopt,
    HaProbe probe = probeHomeAssistant,
    HaSignIn? signIn,
  }) : _adopt = adopt,
       _probe = probe,
       _signIn = signIn,
       super(HaConnectAsk(address: address));

  final HaAdopt _adopt;
  final HaProbe _probe;
  final HaSignIn? _signIn;

  bool get canSignIn => _signIn != null;

  String get _address => switch (value) {
    HaConnectAsk(:final address) => address,
    _ => '',
  };

  void _ask(String address, HaConnectProblem? problem) =>
      value = HaConnectAsk(address: address, problem: problem);

  /// Home Assistant's own login page in the browser, then the check.
  Future<void> signInAndConnect(String address) async {
    final signIn = _signIn;
    if (signIn == null) return;
    final base = haBaseUri(address);
    if (base == null) {
      return _ask(address, HaConnectProblem.noAddress);
    }
    value = const HaConnectChecking();
    final signed = await signIn(base);
    final access = signed.accessToken;
    if (access == null) {
      switch (signed.error) {
        case HaSignInError.cancelled || null:
          return _ask(address, null);
        case HaSignInError.refused:
          return _ask(address, HaConnectProblem.signInRefused);
        case HaSignInError.failed:
          return _ask(address, HaConnectProblem.signInFailed);
      }
    }
    // Kept as the refresh token when there is one: access tokens last
    // 30 minutes. Without one, the access token still connects for now.
    final refresh = signed.refreshToken;
    await _check(
      base,
      address,
      refresh != null ? haStoredRefresh(refresh) : access,
    );
  }

  /// A pasted long-lived token.
  Future<void> connectWithToken(String address, String token) async {
    final base = haBaseUri(address);
    if (base == null) {
      return _ask(address, HaConnectProblem.noAddress);
    }
    if (token.trim().isEmpty) return _ask(address, HaConnectProblem.noToken);
    value = const HaConnectChecking();
    await _check(base, address, token.trim());
  }

  Future<void> _check(Uri base, String address, String stored) async {
    final problem = await _probe(base, stored);
    if (problem != null) {
      return _ask(address, problem);
    }

    value = const HaConnectDone();
    await _adopt(base, stored);
  }

  void back() => _ask(_address, null);
}
