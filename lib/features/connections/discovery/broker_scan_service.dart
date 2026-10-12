import 'dart:async';

import 'broker_probe.dart';
import 'hub_probe.dart';
import 'subnet.dart';

/// What a finished (or cancelled) scan tried, for Support details.
typedef ScanStats = ({bool widened, int hostsTried, int brokersFound});

/// A scan in progress: its [events], and a way to add the answer-gated hub
/// pass while it runs. Cancelling the [events] subscription stops it.
class ScanRun {
  ScanRun({required this.events, required void Function(HubKind) addHub})
    : _addHub = addHub;

  final Stream<ScanEvent> events;
  final void Function(HubKind) _addHub;

  /// Also look for [kind]'s web page on the phone's `/24` (the SMLIGHT pass
  /// on port 80 runs only when the user said they have one). No effect once
  /// the scan has finished; start a new run with it instead.
  void addHub(HubKind kind) => _addHub(kind);
}

/// Scans the phone's `/24` for MQTT brokers, probing each candidate host on a
/// set of [ports] with bounded [concurrency]. Emits each confirmed broker as
/// it's found, deduped by `host:port`. If the `/24` has no broker, it goes on
/// to the rest of the surrounding `/22` ([widerCandidateHosts]), so a phone and
/// hub in different blocks of a mesh network still find each other; a normal
/// network that has a broker never pays for the wider pass.
///
/// [run] also looks for hubs (2.5): when the `/24` has no broker, it probes
/// the `/24` for Home Assistant and the Zigbee2MQTT frontend (and an SMLIGHT
/// hub when asked) before the wider pass, so the empty result can say what
/// was found. Hub hits never count as brokers and never stop the widening.
/// The stream closes when every candidate has been probed; cancelling the
/// subscription stops further probing.
class BrokerScanService {
  BrokerScanService({
    required this.prober,
    HubProber? hubProber,
    this.ports = const [1883, 8883],
    this.concurrency = 32,
  }) : hubProber = hubProber ?? const _NoHubs();

  final HostProber prober;
  final HubProber hubProber;
  final List<int> ports;
  final int concurrency;

  /// The hub kinds every run looks for; SMLIGHT only on request.
  static const defaultHubs = {HubKind.homeAssistant, HubKind.zigbee2mqtt};

  /// Brokers only, as the manual form's "Find brokers" sheet wants it.
  /// [onDone] runs once, when the scan finishes or is cancelled.
  Stream<ProbeResult> scan(
    String deviceIp, {
    void Function(ScanStats stats)? onDone,
  }) => run(
    deviceIp,
    hubs: const {},
    onDone: onDone,
  ).events.where((e) => e is BrokerFound).map((e) => (e as BrokerFound).broker);

  /// The full scan: brokers, hubs and progress. [hubs] are looked for after
  /// an empty `/24` broker pass; [ScanRun.addHub] adds one while running.
  ScanRun run(
    String deviceIp, {
    Set<HubKind> hubs = defaultHubs,
    void Function(ScanStats stats)? onDone,
  }) {
    final engine = _Engine(this, deviceIp, hubs.toSet(), onDone);
    return ScanRun(events: engine.stream, addHub: engine.addHub);
  }
}

class _NoHubs implements HubProber {
  const _NoHubs();
  @override
  Future<HubKind?> probe(String host, int port) async => null;
}

sealed class _Task {
  const _Task(this.host, this.port);
  final String host;
  final int port;
}

class _BrokerTask extends _Task {
  const _BrokerTask(super.host, super.port);
}

class _HubTask extends _Task {
  const _HubTask(super.host, super.port, this.kind);
  final HubKind kind;
}

/// One scan: a task queue pumped at the service's concurrency, in phases.
/// Phase A probes the `/24` for brokers. If none answered, phase B probes
/// the `/24` for hubs and phase C the rest of the `/22` for brokers.
class _Engine {
  _Engine(this.service, this.deviceIp, this.hubs, this.onDone) {
    final local = candidateHosts(deviceIp);
    _localHosts = local;
    _tasks.addAll(_brokerTasks(local));
    _phaseAEnd = _tasks.length;
    _wider = _brokerTasks(widerCandidateHosts(deviceIp));
    _total = _tasks.length + local.length * hubs.length + _wider.length;
    _controller = StreamController<ScanEvent>(
      onListen: _pump,
      onCancel: () {
        _cancelled = true;
        _report();
      },
    );
  }

  final BrokerScanService service;
  final String deviceIp;
  final Set<HubKind> hubs;
  final void Function(ScanStats stats)? onDone;

  late final StreamController<ScanEvent> _controller;
  Stream<ScanEvent> get stream => _controller.stream;

  final _tasks = <_Task>[];
  late final List<String> _localHosts;
  late final List<_BrokerTask> _wider;
  late final int _phaseAEnd;
  late int _total;
  final _seen = <String>{};
  final _hubsSeen = <String>{};
  var _index = 0;
  var _active = 0;
  var _checked = 0;
  var _brokerTasksDone = 0;
  var _cancelled = false;
  var _closed = false;
  var _phaseAEmpty = false;
  var _widened = false;
  var _reported = false;

  List<_BrokerTask> _brokerTasks(List<String> hosts) => [
    for (final h in hosts)
      for (final p in service.ports) _BrokerTask(h, p),
  ];

  List<_HubTask> _hubTasks(HubKind kind) => [
    for (final h in _localHosts) _HubTask(h, hubPorts[kind]!, kind),
  ];

  void addHub(HubKind kind) {
    if (_closed || _cancelled || !hubs.add(kind)) return;
    if (_index < _phaseAEnd) return; // phase B, when it comes, includes it
    if (!_phaseAEmpty) return; // phase A found a broker: no hub passes at all
    // Mid-pass: run it next, ahead of what is left of the wider pass.
    final extra = _hubTasks(kind);
    _tasks.insertAll(_index, extra);
    _total += extra.length;
    scheduleMicrotask(_pump);
  }

  void _report() {
    if (_reported) return;
    _reported = true;
    onDone?.call((
      widened: _widened,
      hostsTried: _brokerTasksDone ~/ service.ports.length,
      brokersFound: _seen.length,
    ));
  }

  void _finishIfDone() {
    if (_closed || _active != 0 || (!_cancelled && _index < _tasks.length)) {
      return;
    }
    if (!_cancelled && !_phaseAEmpty && _seen.isEmpty) {
      // Phase A found nothing: hubs on the /24, then the rest of the /22.
      _phaseAEmpty = true;
      for (final kind in hubs) {
        _tasks.addAll(_hubTasks(kind));
      }
      if (_wider.isNotEmpty) {
        _widened = true;
        _tasks.addAll(_wider);
      }
      if (_index < _tasks.length) {
        scheduleMicrotask(_pump);
        return;
      }
    }
    _closed = true;
    _report();
    _controller.add(
      ScanTriedEvent(
        widened: _widened,
        hostsTried: _brokerTasksDone ~/ service.ports.length,
      ),
    );
    _controller.close();
  }

  void _pump() {
    while (!_cancelled &&
        _active < service.concurrency &&
        _index < _tasks.length) {
      final task = _tasks[_index++];
      _active++;
      _probe(task).catchError((_) {}).whenComplete(() {
        _active--;
        _checked++;
        if (task is _BrokerTask) _brokerTasksDone++;
        if (!_cancelled && !_closed) {
          _controller.add(ScanProgress(_checked, _total));
          _pump();
        }
        _finishIfDone();
      });
    }
    _finishIfDone();
  }

  Future<void> _probe(_Task task) async {
    switch (task) {
      case _BrokerTask():
        final res = await service.prober.probe(task.host, task.port);
        if (res != null && !_cancelled && _seen.add(res.key)) {
          _controller.add(BrokerFound(res));
        }
      case _HubTask():
        final kind = await service.hubProber.probe(task.host, task.port);
        if (kind == null || _cancelled) return;
        final hub = HubFound(kind: kind, host: task.host, port: task.port);
        if (_hubsSeen.add(hub.key)) _controller.add(HubSeen(hub));
    }
  }
}
