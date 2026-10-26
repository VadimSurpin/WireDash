import 'package:flutter_test/flutter_test.dart';
import 'package:wiredash/remote/remote_home.dart';
import 'package:wiredash/remote/remote_pairing.dart';
import 'package:wiredash/remote/remote_seal.dart';

void main() {
  final home = RemoteHome(homeId: 'a1b2', url: 'wss://relay.example/mqtt', username: 'phone-a1b2-ff', password: 'secret', key: RemoteSeal.newKey());

  test('a pairing link carries the whole login and opens as a deep link', () {
    final link = RemotePairing.link(home);
    expect(link, startsWith('wiredash://remote/pair-phone?c='));
    final code = Uri.parse(link).queryParameters['c'];
    final back = RemotePairing.fromCode(code)!;
    expect(back.toJson(), home.toJson());
    expect(RemotePairing.fromCode('garbage'), isNull);
    expect(RemotePairing.fromCode(code!.substring(0, 20)), isNull, reason: 'a cut-off code');
  });

  test('a key backup opens only with its passphrase', () {
    final file = RemotePairing.backup(home, 'correct horse');
    expect(file, isNot(contains('secret')), reason: 'nothing readable in the file');
    expect(RemotePairing.isBackup(file), isTrue);
    expect(RemotePairing.restore(file, 'correct horse')!.toJson(), home.toJson());
    expect(RemotePairing.restore(file, 'wrong horse'), isNull);
    expect(RemotePairing.isBackup('{"dashboards":[]}'), isFalse);
  });
}
