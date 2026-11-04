import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:wiredash/shortcuts/command_worker.dart';

CommandHandler _initialize(Object? configuration) {
  final events = configuration as SendPort;
  var count = 0;
  return (method, arguments) async {
    switch (method) {
      case 'busy':
        events.send('busy');
        final watch = Stopwatch()..start();
        while (watch.elapsedMilliseconds < 400) {
          // Model a synchronous SQLite query/configuration decode.
        }
        return ++count;
      case 'delayed':
        await Future<void>.delayed(const Duration(milliseconds: 50));
        return arguments['value'];
      case 'fail':
        throw StateError('Request rejected');
      case 'exit':
        Isolate.exit();
      default:
        return ++count;
    }
  };
}

CommandHandler _failInitialization(Object? _) =>
    throw StateError('No database');

void main() {
  test(
    'synchronous backend work leaves the calling isolate responsive',
    () async {
      final events = ReceivePort();
      addTearDown(events.close);
      final busy = events.first;
      final worker = await CommandWorker.start(_initialize, events.sendPort);
      addTearDown(worker.dispose);
      var completed = false;
      final request = worker.call('busy', {}).then((result) {
        completed = true;
        return result;
      });
      await busy;
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(
        completed,
        isFalse,
        reason: 'The UI timer runs while the worker is busy',
      );
      expect(await request, 1);
      expect(
        await worker.call('next', {}),
        2,
        reason: 'State stays in one worker',
      );
    },
  );

  test(
    'concurrent replies stay paired and a rejected command is not replayed',
    () async {
      final events = ReceivePort();
      addTearDown(events.close);
      final worker = await CommandWorker.start(_initialize, events.sendPort);
      addTearDown(worker.dispose);
      final delayed = worker.call('delayed', {'value': 'first'});
      expect(await worker.call('next', {}), 1);
      expect(await delayed, 'first');
      await expectLater(worker.call('fail', {}), throwsA(isA<RemoteError>()));
      expect(await worker.call('next', {}), 2);
    },
  );

  test(
    'worker death fails waiting and future requests without replay',
    () async {
      final events = ReceivePort();
      addTearDown(events.close);
      final worker = await CommandWorker.start(_initialize, events.sendPort);
      addTearDown(worker.dispose);
      final delayed = worker.call('delayed', {});
      final waiting = expectLater(delayed, throwsStateError);
      await expectLater(worker.call('exit', {}), throwsStateError);
      await waiting;
      await expectLater(worker.call('next', {}), throwsStateError);
    },
  );

  test(
    'initialization failure is reported instead of leaving startup hanging',
    () async {
      await expectLater(
        CommandWorker.start(_failInitialization, null),
        throwsStateError,
      );
    },
  );
}
