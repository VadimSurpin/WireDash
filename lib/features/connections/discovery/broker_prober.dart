import 'broker_probe.dart';
import 'broker_prober_stub.dart'
    if (dart.library.io) 'broker_prober_io.dart'
    as impl;

/// Builds the platform's [HostProber] (real socket+MQTT prober on
/// mobile/desktop; a no-op on web).
HostProber createHostProber() => impl.createHostProber();

/// The same, waiting longer for each machine to answer (2.9.3).
HostProber createPatientHostProber() => impl.createPatientHostProber();
