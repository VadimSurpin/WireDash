import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'command_confirmations.dart';
import 'review_prompt_controller.dart';

/// Invisible widget that reports a successful session to
/// [ReviewPromptController] while a dashboard is on screen: when a command
/// sent on [connectionId] is confirmed by the device's state update, or
/// (2.8.1) when a device reports, so the dashboard shows live data. Being
/// connected alone does not count.
///
/// Uses `listenManual` from `initState` so the subscription is created once,
/// not on every rebuild.
class ReviewPromptTrigger extends ConsumerStatefulWidget {
  const ReviewPromptTrigger({super.key, required this.connectionId});

  final String connectionId;

  @override
  ConsumerState<ReviewPromptTrigger> createState() =>
      _ReviewPromptTriggerState();
}

class _ReviewPromptTriggerState extends ConsumerState<ReviewPromptTrigger> {
  @override
  void initState() {
    super.initState();
    // Only a fresh value; not a loading or error state that still carries
    // an earlier one.
    void counted(AsyncValue<DateTime>? _, AsyncValue<DateTime> next) {
      if (next is AsyncData<DateTime>) {
        ref.read(reviewPromptControllerProvider).recordSuccessfulSession();
      }
    }

    ref.listenManual(commandConfirmedProvider(widget.connectionId), counted);
    // 2.8.1: live data on the dashboard counts too (sensor-only homes).
    ref.listenManual(deviceReportedProvider(widget.connectionId), counted);
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
