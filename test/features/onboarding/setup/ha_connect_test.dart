import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:wiredash/features/ha_import/ha_auth.dart';
import 'package:wiredash/features/onboarding/setup/ha_address_shape.dart';
import 'package:wiredash/features/onboarding/setup/ha_connect.dart';
import 'package:wiredash/features/onboarding/setup/ha_discovery.dart';
import 'package:wiredash/mqtt/ha_token.dart';

void main() {
  late List<(Uri, String)> probed;
  late List<(Uri, String)> adopted;
  late int browsers;

  HaConnectController make({
    HaSignInResult? signIn,
    HaConnectProblem? problem,
    String address = '',
    HaReach? reach,
    Future<HaConnectProblem?> Function()? slowProbe,
    HaFind? find,
    String? phoneIp,
  }) {
    probed = [];
    adopted = [];
    browsers = 0;
    return HaConnectController(
      address: address,
      adopt: (a, s) async => adopted.add((a, s)),
      probe: (base, stored) async {
        probed.add((base, stored));
        return slowProbe != null ? slowProbe() : problem;
      },
      signIn: signIn == null
          ? null
          : (_) async {
              browsers++;
              return signIn;
            },
      reach: reach,
      find: find,
      phoneIp: phoneIp == null ? null : () async => phoneIp,
    );
  }

  test('starts asking, with the address the scan saw', () {
    final c = make(address: '192.168.68.52');
    expect((c.value as HaConnectAsk).address, '192.168.68.52');
    expect(c.canSignIn, isFalse);
  });

  test('the login page: keeps the refresh token, checks, hands over', () async {
    final c = make(
      signIn: (accessToken: 'acc', refreshToken: 'ref', error: null),
    );
    await c.signInAndConnect('https://abc.ui.nabu.casa');
    expect(probed.single.$1, Uri.parse('https://abc.ui.nabu.casa'));
    expect(probed.single.$2, haStoredRefresh('ref'));
    expect(adopted.single.$2, haStoredRefresh('ref'));
    expect(c.value, isA<HaConnectDone>());

    // Never a token in an event.
  });

  test('a pasted token is kept as is', () async {
    final c = make();
    await c.connectWithToken('192.168.68.52', ' eyJ.long.lived ');
    expect(probed.single.$1, Uri.parse('http://192.168.68.52:8123'));
    expect(probed.single.$2, 'eyJ.long.lived');
    expect(adopted.single.$2, 'eyJ.long.lived');
  });

  test('no address, no token: asked again, nothing probed', () async {
    final c = make(
      signIn: (accessToken: 'acc', refreshToken: 'ref', error: null),
    );
    await c.signInAndConnect('   ');
    expect((c.value as HaConnectAsk).problem, HaConnectProblem.noAddress);
    await c.connectWithToken('192.168.68.52', '');
    expect((c.value as HaConnectAsk).problem, HaConnectProblem.noToken);
    expect(probed, isEmpty);
  });

  test(
    'closing the login quietly returns; refused and failed say why',
    () async {
      for (final (error, problem, _) in [
        (HaSignInError.cancelled, null, 'sign_in_cancelled'),
        (
          HaSignInError.refused,
          HaConnectProblem.signInRefused,
          'sign_in_refused',
        ),
        (HaSignInError.failed, HaConnectProblem.signInFailed, 'sign_in_failed'),
      ]) {
        final c = make(
          signIn: (accessToken: null, refreshToken: null, error: error),
        );
        await c.signInAndConnect('192.168.68.52');
        expect((c.value as HaConnectAsk).problem, problem);
        expect(adopted, isEmpty);
      }
    },
  );

  test(
    'what the check finds is shown and counted, nothing handed over',
    () async {
      for (final (problem, _) in [
        (HaConnectProblem.unreachable, 'unreachable'),
        (HaConnectProblem.notHomeAssistant, 'not_home_assistant'),
        (HaConnectProblem.certificate, 'certificate'),
        (HaConnectProblem.badToken, 'bad_token'),
        (HaConnectProblem.notAdmin, 'not_admin'),
        (HaConnectProblem.noMqtt, 'no_mqtt'),
      ]) {
        final c = make(problem: problem);
        await c.connectWithToken('192.168.68.52', 'tok');
        expect((c.value as HaConnectAsk).problem, problem);
        expect((c.value as HaConnectAsk).address, '192.168.68.52');
        expect(adopted, isEmpty);
      }
    },
  );

  group('3.1.4: no silent sign-in, a way out', () {
    const ok = (accessToken: 'acc', refreshToken: 'ref', error: null);

    test('nothing answers: says so, the browser never opens', () async {
      final reached = <Uri>[];
      final c = make(
        signIn: ok,
        reach: (base) async {
          reached.add(base);
          return HaConnectProblem.unreachable;
        },
      );
      await c.signInAndConnect('homeassistant.local');
      expect(reached.single, Uri.parse('http://homeassistant.local:8123'));
      expect(browsers, 0);
      expect(c.value, isA<HaConnectAsk>());
      expect((c.value as HaConnectAsk).problem, HaConnectProblem.unreachable);
      expect((c.value as HaConnectAsk).address, 'homeassistant.local');
    });

    test('an untrusted certificate is named', () async {
      final c = make(
        signIn: ok,
        reach: (_) async => HaConnectProblem.certificate,
      );
      await c.signInAndConnect('https://ha.example');
      expect((c.value as HaConnectAsk).problem, HaConnectProblem.certificate);
    });

    test('Home Assistant answers: on to the browser as before', () async {
      final c = make(signIn: ok, reach: (_) async => null);
      await c.signInAndConnect('192.168.1.20');
      expect(browsers, 1);
      expect(c.value, isA<HaConnectDone>());
    });

    test(
      'cancel while checking: back to the address, nothing handed on',
      () async {
        final answer = Completer<HaConnectProblem?>();
        final c = make(slowProbe: () => answer.future);
        final going = c.connectWithToken('192.168.1.20', 'tok');
        expect(c.value, isA<HaConnectChecking>());
        c.cancel();
        expect(c.value, isA<HaConnectAsk>());
        expect((c.value as HaConnectAsk).address, '192.168.1.20');
        expect((c.value as HaConnectAsk).problem, isNull);
        answer.complete(null);
        await going;
        expect(adopted, isEmpty);
        expect(c.value, isA<HaConnectAsk>());
      },
    );

    test('leaving the screen mid-check stops the try', () async {
      final answer = Completer<HaConnectProblem?>();
      final c = make(slowProbe: () => answer.future);
      final going = c.connectWithToken('192.168.1.20', 'tok');
      c.dispose();
      answer.complete(null);
      await going;
      expect(adopted, isEmpty);
    });
  });

  group('3.1.8: finding Home Assistant', () {
    const home = HaFound(address: 'http://192.168.68.64:8123', name: 'Home');
    const signedIn = (accessToken: 'acc', refreshToken: 'ref', error: null);

    test('several, by name, none', () async {
      expect(await make(find: () async => [home, home]).look(), hasLength(2));

      await make(
        find: () async => [
          const HaFound(address: 'http://homeassistant:8123', byName: true),
        ],
      ).look();

      await make(find: () async => throw StateError('no nsd')).look();
    });

    test('no look without a finder', () async {
      final c = make();
      expect(await c.look(), isEmpty);
      expect(c.looked, isFalse);
    });

    test('signed in with nothing typed: waits for the look, uses it', () async {
      final done = Completer<List<HaFound>>();
      final c = make(signIn: signedIn, find: () => done.future);
      c.look();
      final signing = c.signInAndConnect('');
      expect(c.value, isA<HaConnectChecking>());
      done.complete([home]);
      await signing;
      expect(probed.single.$1, Uri.parse('http://192.168.68.64:8123'));
    });

    test('nothing typed, nothing found: asks for the address', () async {
      final c = make(signIn: signedIn, find: () async => []);
      c.look();
      await c.signInAndConnect('');
      expect(c.value, isA<HaConnectAsk>());
      expect((c.value as HaConnectAsk).problem, HaConnectProblem.noAddress);
      expect(browsers, 0);
    });

    test('a .local name goes to the one Home Assistant found', () async {
      final c = make(signIn: signedIn, find: () async => [home]);
      await c.look();
      await c.signInAndConnect('homeassistant.local:8123');
      expect(probed.single.$1, Uri.parse('http://192.168.68.64:8123'));
    });

    test('a typed address is kept, whatever was found', () async {
      final c = make(signIn: signedIn, find: () async => [home]);
      await c.look();
      await c.signInAndConnect('https://abc.ui.nabu.casa');
      expect(probed.single.$1, Uri.parse('https://abc.ui.nabu.casa'));
    });
  });

  group('3.1.12: the kind of address, never the address', () {
    const ok = (accessToken: 'acc', refreshToken: 'ref', error: null);

    test('an address on another network than the phone', () async {
      final c = make(
        signIn: ok,
        phoneIp: '192.168.68.40',
        reach: (_) async => HaConnectProblem.unreachable,
      );
      await c.signInAndConnect('192.168.1.20');
      final ask = c.value as HaConnectAsk;
      expect(ask.shape, HaAddressShape.otherNetwork);
      expect(c.phoneIp, '192.168.68.40');
    });
  });
}
