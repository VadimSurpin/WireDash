import 'dart:async';
import 'dart:isolate';

typedef CommandHandler =
    FutureOr<Object?> Function(String method, Map<String, Object?> arguments);
typedef CommandWorkerInitializer = FutureOr<CommandHandler> Function(Object?);

/// A persistent worker: the database, MQTT sockets and command state all stay
/// together, away from Android's UI/platform thread. Requests are never replayed.
class CommandWorker {
  CommandWorker._();

  final _replies = ReceivePort();
  final _errors = ReceivePort();
  final _exits = ReceivePort();
  final _ready = Completer<void>();
  final _pending = <int, Completer<Object?>>{};
  Isolate? _isolate;
  SendPort? _requests;
  Object? _failure;
  var _nextId = 0;

  static Future<CommandWorker> start(
    CommandWorkerInitializer initialize,
    Object? configuration, {
    bool Function(Object, StackTrace)? ignoreError,
  }) async {
    final worker = CommandWorker._();
    worker._replies.listen(worker._receive);
    worker._errors.listen(
      (_) => worker._fail(StateError('Command worker failed')),
    );
    worker._exits.listen(
      (_) => worker._fail(StateError('Command worker exited')),
    );
    try {
      worker._isolate = await Isolate.spawn(
        _serve,
        (worker._replies.sendPort, initialize, configuration, ignoreError),
        debugName: 'wiredash-commands',
        onError: worker._errors.sendPort,
        onExit: worker._exits.sendPort,
      );
      await worker._ready.future;
      return worker;
    } catch (_) {
      worker.dispose();
      rethrow;
    }
  }

  Future<Object?> call(String method, Map<String, Object?> arguments) {
    if (_failure != null) return Future.error(_failure!);
    final id = ++_nextId;
    final reply = Completer<Object?>();
    _pending[id] = reply;
    _requests!.send((id, method, arguments));
    return reply.future;
  }

  void _receive(dynamic message) {
    if (message is SendPort) {
      _requests = message;
      _ready.complete();
    } else if (message is (int, Object?, String?, String?)) {
      final (id, value, error, stack) = message;
      final reply = _pending.remove(id);
      if (error == null) {
        reply?.complete(value);
      } else {
        reply?.completeError(RemoteError(error, stack ?? ''));
      }
    }
  }

  void _fail(Object error) {
    if (_failure != null) return;
    _failure = error;
    if (!_ready.isCompleted) _ready.completeError(error);
    for (final reply in _pending.values) {
      reply.completeError(error);
    }
    _pending.clear();
    _replies.close();
    _errors.close();
    _exits.close();
    _isolate?.kill(priority: Isolate.immediate);
  }

  void dispose() => _fail(StateError('Command worker closed'));
}

void _serve(
  (
    SendPort,
    CommandWorkerInitializer,
    Object?,
    bool Function(Object, StackTrace)?,
  )
  setup,
) {
  final (replies, initialize, configuration, ignoreError) = setup;
  runZonedGuarded(
    () async {
      final handle = await initialize(configuration);
      final requests = ReceivePort();
      requests.listen((dynamic message) async {
        final (id, method, args) =
            message as (int, String, Map<String, Object?>);
        try {
          replies.send((id, await handle(method, args), null, null));
        } catch (error, stack) {
          replies.send((id, null, error.toString(), stack.toString()));
        }
      });
      replies.send(requests.sendPort);
    },
    (error, stack) {
      if (ignoreError?.call(error, stack) == true) return;
      // Let the isolate error port fail every waiting request, including startup.
      Zone.root.handleUncaughtError(error, stack);
    },
  );
}
