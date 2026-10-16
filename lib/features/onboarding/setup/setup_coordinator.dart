import 'dart:async';

import '../../../mqtt/broker_config.dart';
import '../../connections/diagnostics/connect_diagnostics.dart';
import '../../connections/discovery/address_check.dart';
import '../../connections/discovery/broker_probe.dart';
import '../../connections/discovery/broker_scan_service.dart';
import '../../connections/discovery/hub_probe.dart';
import '../../discovery/models/z2m_device.dart';
import 'recommendation_policy.dart';
import 'setup_candidate.dart';
import 'setup_creator.dart';
import 'setup_error_guidance.dart';

/// The outcome of fetching the device list during verification: whether
/// Zigbee2MQTT topics verified on the endpoint at all, and the parsed devices.
class Z2mFetchResult {
  const Z2mFetchResult({required this.detected, required this.devices});

  /// True only after `$base/bridge/...` topics verified Zigbee2MQTT — the UI
  /// may not claim Z2M was found before this.
  final bool detected;
  final List<Z2mDevice> devices;
}

typedef DeviceIpProvider = Future<String?> Function();

/// Starts a scan; [hubs] are the hub kinds to look for when the phone's /24
/// has no broker (the user's platform answer adds the SMLIGHT pass).
typedef ScanRunFactory = ScanRun Function(String deviceIp, Set<HubKind> hubs);

/// Where the user says Zigbee2MQTT runs, asked while the scan runs (2.5).
/// Not an answer and [notSure] both mean the plain scan; the others add a
/// pass or change what the empty result says.
enum SetupPlatform { homeAssistant, smlight, piOrDocker, notSure }

/// The hub kinds a platform answer makes the scan look for, on top of the
/// default ones (Home Assistant and the Zigbee2MQTT frontend).
Set<HubKind> hubsForPlatform(SetupPlatform? platform) => {
  ...BrokerScanService.defaultHubs,
  if (platform == SetupPlatform.smlight) HubKind.smlight,
};

/// Names the machine at a host from its web pages; see [identifyHost].
typedef HubIdentifier = Future<HubKind?> Function(String host);

/// How far a scan has come, for the progress bar.
typedef ScanProgressValue = ({int checked, int total});

/// What a finished scan tried, for the empty result's analytics: whether it
/// widened, how many hosts it tried and how many answered at all (2.6.2).
typedef ScanTried = ({bool widened, int hostsTried, int aliveHosts});

/// The network the scan ran on, for the empty result's analytics (2.6.2):
/// the interface kind as Support details names it ("Wi-Fi", "Ethernet",
/// "other") and whether a VPN was up. Never an address.
typedef NetworkFacts = ({String? kind, bool vpn});
typedef NetworkFactsProvider = Future<NetworkFacts> Function();

/// How the address check (2.6.2) is going on the empty result, and the host
/// it was given, for the message. A broker outcome leaves this state (setup
/// verifies the broker); a hub outcome is also recorded in
/// [SetupScanEmpty.hubs].
enum AddressCheckStatus {
  checking,
  hub,
  nothing,
  notResolved,
  notLocal,
  invalid,
}

typedef AddressCheckState = ({AddressCheckStatus status, String host});
typedef DeviceListFetcher =
    Future<Z2mFetchResult> Function(
      BrokerConfig config,
      String password,
      String base,
    );

// --- States ---------------------------------------------------------------

sealed class SetupState {
  const SetupState();
}

/// The welcome screen — nothing running yet.
class SetupIdle extends SetupState {
  const SetupIdle();
}

/// Scanning the local network; [candidates] grow progressively and [done]
/// flips true when the scan completes. [hubs] are the hubs seen so far,
/// [progress] how far the scan is, [platform] the user's answer, [kinds]
/// what the candidates' machines are.
class SetupScanning extends SetupState {
  const SetupScanning(
    this.candidates, {
    this.done = false,
    this.hubs = const [],
    this.progress,
    this.platform,
    this.kinds = const {},
  });
  final List<SetupCandidate> candidates;
  final bool done;
  final List<HubFound> hubs;
  final ScanProgressValue? progress;
  final SetupPlatform? platform;

  /// What each candidate's machine is, by host, once the scan has found more
  /// than one broker and looked at their web pages (2.7.1).
  final Map<String, HubKind> kinds;
}

/// The scan finished without a single usable candidate. [hubs] are the hubs
/// it saw instead, [platform] the user's answer, [tried] what it covered,
/// [deviceIp] the phone's address and [network] what it ran on, for the
/// result screen and its analytics. [address] is the address check's state
/// once the user typed one (2.6.2).
class SetupScanEmpty extends SetupState {
  const SetupScanEmpty({
    this.hubs = const [],
    this.platform,
    this.tried,
    this.deviceIp,
    this.network,
    this.address,
  });
  final List<HubFound> hubs;
  final SetupPlatform? platform;
  final ScanTried? tried;
  final String? deviceIp;
  final NetworkFacts? network;
  final AddressCheckState? address;

  SetupScanEmpty copyWith({
    List<HubFound>? hubs,
    SetupPlatform? platform,
    AddressCheckState? address,
    bool clearAddress = false,
  }) => SetupScanEmpty(
    hubs: hubs ?? this.hubs,
    platform: platform ?? this.platform,
    tried: tried,
    deviceIp: deviceIp,
    network: network,
    address: clearAddress ? null : (address ?? this.address),
  );

  /// The hub the result speaks about: Home Assistant first (it hosts the
  /// broker), then the Zigbee2MQTT frontend, then an SMLIGHT hub.
  HubFound? get hub {
    for (final kind in HubKind.values) {
      for (final h in hubs) {
        if (h.kind == kind) return h;
      }
    }
    return null;
  }
}

/// Running the diagnostic ladder against [candidate].
class SetupVerifying extends SetupState {
  const SetupVerifying(this.candidate);
  final SetupCandidate candidate;
}

/// The broker requires credentials. [rejected] is true when credentials were
/// already tried and refused — the UI shows "wrong password" guidance instead
/// of the first-time prompt.
/// The broker refused anonymous access. [platform] is the user's answer so
/// far, so the prompt can say where that platform keeps its MQTT login.
class SetupNeedsAuth extends SetupState {
  const SetupNeedsAuth(this.candidate, {this.rejected = false, this.platform});
  final SetupCandidate candidate;
  final bool rejected;
  final SetupPlatform? platform;
}

/// A categorized failure. [failedAtCreation] marks save failures: retry then
/// resumes at creation instead of re-verifying.
class SetupFailed extends SetupState {
  const SetupFailed(this.kind, {this.candidate, this.failedAtCreation = false});
  final SetupErrorKind kind;
  final SetupCandidate? candidate;
  final bool failedAtCreation;
}

/// Devices verified — the user reviews the grouped, preselected rows.
class SetupReview extends SetupState {
  const SetupReview(this.candidate, this.rows);
  final SetupCandidate candidate;
  final List<ReviewRow> rows;

  int get selectedCount => rows.where((r) => r.selected).length;
}

/// Saving connection + dashboard + panels. Carries the [review] so the list
/// stays on screen with a busy button instead of a separate screen.
class SetupCreating extends SetupState {
  const SetupCreating(this.review);
  final SetupReview review;
}

/// Done — the dashboard is ready.
class SetupComplete extends SetupState {
  const SetupComplete(this.result);
  final SetupResult result;
}

// --- Coordinator ----------------------------------------------------------

/// Owns the discovery-first setup state machine:
///
///   idle → scanning → verifying → (needsAuth →) review → creating → complete
///
/// The UI renders [state] and sends intents; it never performs network work
/// or persists partial setup itself. Valid values (credentials, selections)
/// survive retries within the session; [cancel] releases scans and timers and
/// returns to a safe initial state.
class SetupCoordinator {
  SetupCoordinator({
    required ScanRunFactory scan,
    required DeviceIpProvider deviceIp,
    required ConnectDiagnostics diagnostics,
    required DeviceListFetcher fetchDevices,
    required SetupStore creator,
    AddressChecker? checkAddress,
    HubIdentifier? identifyHub,
    NetworkFactsProvider? networkFacts,
    String base = 'zigbee2mqtt',
    this.onCreated,
  }) : _base = base,
       _scan = scan,
       _deviceIp = deviceIp,
       _diagnostics = diagnostics,
       _fetchDevices = fetchDevices,
       _creator = creator,
       _checkAddress = checkAddress,
       _identifyHub = identifyHub,
       _networkFacts = networkFacts;

  final ScanRunFactory _scan;
  final DeviceIpProvider _deviceIp;
  final ConnectDiagnostics _diagnostics;
  final DeviceListFetcher _fetchDevices;
  final SetupStore _creator;

  /// The address check (2.6.2); null where the platform cannot probe (web),
  /// and then [checkAddress] reports nothing found.
  final AddressChecker? _checkAddress;

  /// Names the machine behind each broker when the scan finds several, so
  /// the cards say "Home Assistant" instead of two identical "Possible
  /// connection found" (2.7.1). Null where the platform cannot probe.
  final HubIdentifier? _identifyHub;
  final NetworkFactsProvider? _networkFacts;

  /// Runs once after a successful setup, before [SetupComplete] is emitted
  /// (the app clears demo mode, finishes first run and remembers the new
  /// dashboard). Its failures never undo the saved setup.
  final Future<void> Function(SetupResult result)? onCreated;

  /// The Zigbee2MQTT base topic for this session; [retryWithBase] changes it.
  String get base => _base;
  String _base;

  final _states = StreamController<SetupState>.broadcast();
  SetupState _state = const SetupIdle();

  StreamSubscription<ScanEvent>? _scanSub;
  ScanRun? _run;
  SetupPlatform? _platform;
  String? _username;
  String? _password;
  List<ReviewRow>? _rows;
  var _op = 0;

  SetupState get state => _state;
  Stream<SetupState> get states => _states.stream;

  /// The user's platform answer, kept for the session.
  SetupPlatform? get platform => _platform;

  void _emit(SetupState s) {
    _state = s;
    if (!_states.isClosed) _states.add(s);
  }

  // --- Intents ---

  Future<void> startScan() async {
    final op = ++_op;
    _cancelScan();
    _emit(SetupScanning(const [], platform: _platform));
    final ip = await _deviceIp();
    if (op != _op) return;
    if (ip == null) {
      _emit(const SetupFailed(SetupErrorKind.scanFailed));
      return;
    }
    NetworkFacts? network;
    try {
      network = await _networkFacts?.call();
    } catch (_) {
      // Diagnostics only; the scan runs without them.
    }
    if (op != _op) return;
    final buffer = <ProbeResult>[];
    final hubs = <HubFound>[];
    ScanProgressValue? progress;
    ScanTried? tried;
    final run = _scan(ip, hubsForPlatform(_platform));
    _run = run;
    void emitScanning({bool done = false}) => _emit(
      SetupScanning(
        mergeCandidates(buffer),
        done: done,
        hubs: List.unmodifiable(hubs),
        progress: progress,
        platform: _platform,
      ),
    );
    _scanSub = run.events.listen(
      (event) {
        if (_state is! SetupScanning) return;
        switch (event) {
          case BrokerFound(:final broker):
            buffer.add(broker);
            emitScanning();
          case HubSeen(:final hub):
            hubs.add(hub);
            emitScanning();
          case ScanProgress(:final checked, :final total):
            progress = (checked: checked, total: total);
            // Coarse steps keep the UI from rebuilding a thousand times.
            if (checked == total || checked % 16 == 0) emitScanning();
          case ScanTriedEvent(
            :final widened,
            :final hostsTried,
            :final aliveHosts,
          ):
            tried = (
              widened: widened,
              hostsTried: hostsTried,
              aliveHosts: aliveHosts,
            );
        }
      },
      onDone: () {
        if (_state is! SetupScanning) return;
        final merged = mergeCandidates(buffer);
        if (merged.isEmpty) {
          _emit(
            SetupScanEmpty(
              hubs: List.unmodifiable(hubs),
              platform: _platform,
              tried: tried,
              deviceIp: ip,
              network: network,
            ),
          );
        } else if (merged.length == 1) {
          // One broker found: continue without asking the user to pick it.
          unawaited(_verify(merged.single));
        } else {
          emitScanning(done: true);
          unawaited(_nameCandidates(merged, op));
        }
      },
      onError: (_) {
        if (_state is SetupScanning) {
          _emit(
            SetupScanEmpty(
              hubs: List.unmodifiable(hubs),
              platform: _platform,
              deviceIp: ip,
              network: network,
            ),
          );
        }
      },
    );
  }

  Future<void> _nameCandidates(List<SetupCandidate> found, int op) async {
    final identify = _identifyHub;
    if (identify == null) return;
    final kinds = <String, HubKind>{};
    await Future.wait([
      for (final host in {for (final c in found) c.host})
        identify(host).then((kind) {
          if (kind != null) kinds[host] = kind;
        }, onError: (_) {}),
    ]);
    final s = _state;
    if (op != _op || s is! SetupScanning || kinds.isEmpty) return;
    _emit(
      SetupScanning(
        s.candidates,
        done: s.done,
        hubs: s.hubs,
        progress: s.progress,
        platform: s.platform,
        kinds: Map.unmodifiable(kinds),
      ),
    );
  }

  /// The user's answer to "where does Zigbee2MQTT run?". While scanning, an
  /// SMLIGHT answer adds that pass to the running scan; on the empty result
  /// the answer retags it (Try again scans with it).
  void setPlatform(SetupPlatform? platform) {
    _platform = platform;
    final s = _state;
    if (s is SetupScanning) {
      if (platform == SetupPlatform.smlight) _run?.addHub(HubKind.smlight);
      _emit(
        SetupScanning(
          s.candidates,
          done: s.done,
          hubs: s.hubs,
          progress: s.progress,
          platform: platform,
          kinds: s.kinds,
        ),
      );
    } else if (s is SetupScanEmpty) {
      // Not copyWith: deselecting a chip sets the answer back to null.
      _emit(
        SetupScanEmpty(
          hubs: s.hubs,
          platform: platform,
          tried: s.tried,
          deviceIp: s.deviceIp,
          network: s.network,
          address: s.address,
        ),
      );
    }
  }

  /// The address check (2.6.2): from the empty result, check the one
  /// machine the user named. A broker there goes straight to verification
  /// (and the login step if it asks); a hub page without a broker becomes
  /// the "found X, but no broker" result; anything else is said on the
  /// field. The typed address never leaves the coordinator.
  Future<void> checkAddress(String input) async {
    final s = _state;
    if (s is! SetupScanEmpty) return;
    final parsed = hostFromAddressInput(input);
    if (parsed == null) {
      _emit(
        s.copyWith(address: (status: AddressCheckStatus.invalid, host: '')),
      );
      return;
    }
    final op = ++_op;
    _emit(
      s.copyWith(
        address: (status: AddressCheckStatus.checking, host: parsed.host),
      ),
    );
    AddressCheckResult result;
    try {
      result =
          await _checkAddress?.call(parsed.host, parsed.port) ??
          const AddressCheckResult.nothing();
    } catch (_) {
      result = const AddressCheckResult.nothing();
    }
    if (op != _op || _state is! SetupScanEmpty) return;
    final current = _state as SetupScanEmpty;
    switch (result.outcome) {
      case AddressOutcome.broker:
        final candidate = SetupCandidate.fromProbe(result.broker!);
        // Leave the empty result through a verifying state even when the
        // broker asks for a login first, so the check is counted as found
        // before the login step is.
        _emit(SetupVerifying(candidate));
        await _verify(candidate);
      case AddressOutcome.hub:
        _emit(
          current.copyWith(
            hubs: [result.hub!],
            address: (status: AddressCheckStatus.hub, host: parsed.host),
          ),
        );
      case AddressOutcome.nothing:
      case AddressOutcome.notResolved:
      case AddressOutcome.notLocal:
      case AddressOutcome.invalid:
        _emit(
          current.copyWith(
            address: (
              status: switch (result.outcome) {
                AddressOutcome.notResolved => AddressCheckStatus.notResolved,
                AddressOutcome.notLocal => AddressCheckStatus.notLocal,
                AddressOutcome.invalid => AddressCheckStatus.invalid,
                _ => AddressCheckStatus.nothing,
              },
              host: parsed.host,
            ),
          ),
        );
    }
  }

  Future<void> selectCandidate(SetupCandidate candidate) async {
    // A card the scan named answers "where does Zigbee2MQTT run?" when the
    // user has not, so the login step's hint fits (2.7.1).
    final s = _state;
    if (_platform == null && s is SetupScanning) {
      _platform = switch (s.kinds[candidate.host]) {
        HubKind.homeAssistant => SetupPlatform.homeAssistant,
        HubKind.smlight => SetupPlatform.smlight,
        _ => null,
      };
    }
    _cancelScan();
    await _verify(candidate);
  }

  Future<void> submitCredentials(String username, String password) async {
    final s = _state;
    if (s is! SetupNeedsAuth) return;
    _username = username.isEmpty ? null : username;
    _password = password;
    await _verify(s.candidate);
  }

  void toggleDevice(String friendlyName) {
    final s = _state;
    if (s is! SetupReview) return;
    final rows = [
      for (final r in s.rows)
        r.device.friendlyName == friendlyName && r.selectable
            ? r.copyWith(selected: !r.selected)
            : r,
    ];
    _rows = rows;
    _emit(SetupReview(s.candidate, rows));
  }

  Future<void> createDashboard() async {
    final rows = _rows;
    final candidate = _candidate;
    if (rows == null || candidate == null) return;
    final op = ++_op;
    _emit(SetupCreating(SetupReview(candidate, rows)));
    try {
      final result = await _creator.create(
        host: candidate.host,
        port: candidate.port,
        protocol: candidate.protocol,
        username: _username,
        password: _password,
        base: base,
        selected: rows.where((r) => r.selected).toList(),
        notSelected: rows.where((r) => !r.selected).toList(),
      );
      if (op != _op) return;
      try {
        await onCreated?.call(result);
      } catch (_) {
        // The connection and dashboard are saved; follow-up bookkeeping
        // failing must not turn a working setup into an error.
      }
      if (op != _op) return;
      _emit(SetupComplete(result));
    } catch (_) {
      if (op != _op) return;
      _emit(
        SetupFailed(
          SetupErrorKind.saveFailed,
          candidate: candidate,
          failedAtCreation: true,
        ),
      );
    }
  }

  /// Resumes at the failed stage: rescan, re-verify, or re-create — never
  /// restarts successful work.
  Future<void> retry() async {
    final s = _state;
    if (s is SetupScanEmpty) {
      await startScan();
    } else if (s is SetupFailed) {
      if (s.failedAtCreation) {
        await createDashboard();
      } else if (s.kind == SetupErrorKind.scanFailed) {
        await startScan();
      } else if (s.candidate != null) {
        await _verify(s.candidate!);
      }
    }
  }

  /// From "broker found, no Zigbee2MQTT": check [newBase] on the same broker.
  /// Blank input keeps the current base topic.
  Future<void> retryWithBase(String newBase) async {
    final s = _state;
    if (s is! SetupFailed || s.candidate == null) return;
    final trimmed = newBase.trim();
    if (trimmed.isNotEmpty) _base = trimmed;
    await _verify(s.candidate!);
  }

  /// Leaves setup: cancels the scan and every in-flight operation, drops the
  /// session's preserved values, and returns to a safe initial state.
  Future<void> cancel() async {
    _op++;
    _cancelScan();
    _username = null;
    _password = null;
    _rows = null;
    _platform = null;
    _emit(const SetupIdle());
  }

  Future<void> dispose() async {
    _op++;
    _cancelScan();
    await _states.close();
  }

  /// Cancels the active scan without awaiting the subscription teardown —
  /// awaiting it can stall behind a still-open stream, and the listener
  /// already drops events once the state leaves [SetupScanning].
  void _cancelScan() {
    unawaited(_scanSub?.cancel());
    _scanSub = null;
    _run = null;
  }

  // --- Internals ---

  SetupCandidate? get _candidate => switch (_state) {
    SetupVerifying(:final candidate) => candidate,
    SetupNeedsAuth(:final candidate) => candidate,
    SetupFailed(:final candidate) => candidate,
    SetupReview(:final candidate) => candidate,
    _ => null,
  };

  Future<void> _verify(SetupCandidate candidate) async {
    if (candidate.needsAuth && _username == null) {
      _emit(SetupNeedsAuth(candidate, platform: _platform));
      return;
    }
    final op = ++_op;
    _emit(SetupVerifying(candidate));
    final config = BrokerConfig(
      id: 'setup-${DateTime.now().microsecondsSinceEpoch}',
      host: candidate.host,
      port: candidate.port,
      protocol: candidate.protocol,
      username: _username,
    );
    final DiagnosticsReport report;
    try {
      report = await _diagnostics.run(
        config: config,
        password: _password ?? '',
        base: base,
      );
    } catch (_) {
      if (op != _op) return;
      _emit(SetupFailed(SetupErrorKind.unknown, candidate: candidate));
      return;
    }
    if (op != _op) return;

    if (!report.connected) {
      final kind = mapLadderFailure(report);
      if (kind == SetupErrorKind.authRejected) {
        // No credentials yet → first-time prompt; tried already → rejected.
        _emit(
          SetupNeedsAuth(
            candidate,
            rejected: _username != null,
            platform: _platform,
          ),
        );
        return;
      }
      _emit(SetupFailed(kind, candidate: candidate));
      return;
    }

    final Z2mFetchResult fetch;
    try {
      fetch = await _fetchDevices(config, _password ?? '', base);
    } catch (_) {
      if (op != _op) return;
      _emit(SetupFailed(SetupErrorKind.notZigbee2Mqtt, candidate: candidate));
      return;
    }
    if (op != _op) return;
    if (!fetch.detected) {
      _emit(SetupFailed(SetupErrorKind.notZigbee2Mqtt, candidate: candidate));
      return;
    }
    if (fetch.devices.isEmpty) {
      _emit(SetupFailed(SetupErrorKind.noDevices, candidate: candidate));
      return;
    }
    final rows = recommendDevices(fetch.devices, base: base);
    _rows = rows;
    _emit(SetupReview(candidate, rows));
  }
}
