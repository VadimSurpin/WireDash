import 'package:flutter_test/flutter_test.dart';
import 'package:zigdash/features/discovery/models/z2m_device.dart';
import 'package:zigdash/features/ha_import/ha_client.dart';
import 'package:zigdash/features/ha_import/ha_import_apply.dart';
import 'package:zigdash/features/ha_import/ha_import_controller.dart';
import 'package:zigdash/features/ha_import/ha_registry.dart';

final _sensor = Z2mDevice(
  friendlyName: '0xa4c13836276df66f',
  type: 'EndDevice',
  ieeeAddress: '0xa4c13836276df66f',
  description: 'Motion sensor',
);

final _registry = HaRegistry.fromLists(
  devices: [
    {
      'id': 'd1',
      'identifiers': [
        ['mqtt', 'zigbee2mqtt_0xa4c13836276df66f'],
      ],
      'name_by_user': 'Living room motion',
      'area_id': 'living_room',
    },
  ],
  areas: [
    {'area_id': 'living_room', 'name': 'Living Room'},
  ],
);

void main() {
  late List<(Uri, String)> reads;
  late List<(bool, Set<String?>)> writes;

  HaImportController controller({
    HaReadResult? result,
    List<Z2mDevice>? devices = const [],
  }) {
    reads = [];
    writes = [];
    return HaImportController(
      address: '192.168.68.52',
      reader: (base, token) async {
        reads.add((base, token));
        return result ?? (registry: _registry, error: null);
      },
      devices: () async => devices == null ? null : [_sensor, ...devices],
      writer: (plan, {required makeDashboards, required skipRooms}) async {
        writes.add((makeDashboards, skipRooms));
        return const HaImportResult(renamed: 1, dashboardIds: ['b'], tiles: 1);
      },
    );
  }

  test('starts on the address, prefilled', () {
    final c = controller();
    expect((c.value as HaImportAsk).address, '192.168.68.52');
  });

  test('reads with the token, previews, applies', () async {
    final c = controller();
    await c.read(' 192.168.68.52 ', ' secret ');
    expect(reads.single.$1.toString(), 'http://192.168.68.52:8123');
    expect(reads.single.$2, 'secret');
    final preview = c.value as HaImportPreview;
    expect(preview.plan.matched, 1);
    c.toggleRoom('Living Room');
    c.setMakeDashboards(false);
    await c.apply();
    expect(writes.single.$1, isFalse);
    expect(writes.single.$2, {'Living Room'});
    expect((c.value as HaImportDone).result.renamed, 1);
  });

  test('the token is never kept in a state', () async {
    final c = controller();
    final seen = <HaImportState>[];
    c.addListener(() => seen.add(c.value));
    await c.read('192.168.68.52', 'secret-token-value');
    for (final s in seen) {
      expect(s.toString(), isNot(contains('secret-token-value')));
      if (s is HaImportAsk) expect(s.address, isNot(contains('secret')));
    }
  });

  test('a refused token goes back to the first step, saying so', () async {
    final c = controller(result: (registry: null, error: HaReadError.badToken));
    await c.read('192.168.68.52', 'wrong');
    final ask = c.value as HaImportAsk;
    expect(ask.problem, HaImportProblem.badToken);
    expect(ask.address, '192.168.68.52');
  });

  test('missing address or token, or a home not connected', () async {
    final c = controller();
    await c.read('', 'x');
    expect((c.value as HaImportAsk).problem, HaImportProblem.noAddress);
    await c.read('192.168.68.52', '  ');
    expect((c.value as HaImportAsk).problem, HaImportProblem.noToken);
    final offline = controller(devices: null);
    await offline.read('192.168.68.52', 'secret');
    expect((offline.value as HaImportAsk).problem, HaImportProblem.noDevices);
    expect(reads, isEmpty, reason: 'Home Assistant is not asked for nothing');
  });

  test('nothing to import cannot be applied', () async {
    final c = controller(
      result: (
        registry: HaRegistry.fromLists(devices: const [], areas: const []),
        error: null,
      ),
    );
    await c.read('192.168.68.52', 'secret');
    expect((c.value as HaImportPreview).empty, isTrue);
    await c.apply();
    expect(writes, isEmpty);
  });
}
