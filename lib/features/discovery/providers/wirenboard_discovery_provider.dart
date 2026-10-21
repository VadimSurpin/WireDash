import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../mqtt/mqtt_manager.dart';
import '../../../mqtt/providers/mqtt_manager_provider.dart';
import '../models/wirenboard_device.dart';

/// A live list: retained metadata arrives across many topics, followed by
/// changes. Subscribe only to metadata; never probe or publish to the broker.
final wirenBoardDevicesProvider = StreamProvider.autoDispose
    .family<List<WirenBoardDevice>, String>((ref, connectionId) async* {
      final mgr = await ref.read(mqttManagerProvider(connectionId).future);
      final discovery = WirenBoardDiscovery();
      final output = StreamController<List<WirenBoardDevice>>();
      final subscriptions = <StreamSubscription<MqttRxMessage>>[];
      const patterns = ['/devices/+/meta/#', '/devices/+/controls/+/meta/#'];
      Timer? flush;
      void schedule(Duration delay) {
        flush ??= Timer(delay, () {
          flush = null;
          output.add(discovery.devices);
        });
      }

      // Let the initial retained batch arrive before showing an empty list.
      schedule(const Duration(seconds: 1));
      for (final pattern in patterns) {
        subscriptions.add(
          mgr.subscribe(pattern).listen((message) {
            if (discovery.apply(message.topic, message.payload)) {
              schedule(const Duration(milliseconds: 100));
            }
          }, onError: output.addError),
        );
      }
      // Wildcard subscriptions do not replay all topics when shared/revisited.
      for (final message in mgr.latestUnder('/devices/')) {
        discovery.apply(message.topic, message.payload);
      }
      ref.onDispose(() {
        flush?.cancel();
        for (final subscription in subscriptions) {
          unawaited(subscription.cancel());
        }
        for (final pattern in patterns) {
          mgr.unsubscribe(pattern);
        }
        unawaited(output.close());
      });
      yield* output.stream;
    });
