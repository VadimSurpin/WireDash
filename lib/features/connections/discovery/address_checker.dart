// Platform-conditional address check: DNS plus probes on `dart:io`
// platforms, a nothing-found stub on web.
export 'address_checker_stub.dart'
    if (dart.library.io) 'address_checker_io.dart';
