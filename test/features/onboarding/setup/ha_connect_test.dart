import 'package:flutter_test/flutter_test.dart';
import 'package:zigdash/features/ha_import/ha_auth.dart';
import 'package:zigdash/features/onboarding/setup/ha_connect.dart';
import 'package:zigdash/mqtt/ha_token.dart';

void main() {
  late List<(Uri, String)> probed;
  late List<(Uri, String)> adopted;

  HaConnectController make({
    HaSignInResult? signIn,
    HaConnectProblem? problem,
    String address = '',
  }) {
    probed = [];
    adopted = [];
    return HaConnectController(
      address: address,
      adopt: (a, s) async => adopted.add((a, s)),
      probe: (base, stored) async {
        probed.add((base, stored));
        return problem;
      },
      signIn: signIn == null ? null : (_) async => signIn,
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
}
