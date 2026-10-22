import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jsf/jsf.dart';

class DisplayValue {
  const DisplayValue(this.value, {this.applied = false, this.error});
  final Object? value;
  final bool applied;
  final String? error;
  String get text => value?.toString() ?? '—';
}

/// Only presentation uses these results. MQTT state, stored histories and
/// outgoing commands retain their original values. Each evaluation has its own
/// bounded native realm, so one panel cannot change another panel's globals.
class DisplayExpressionEvaluator {
  static const maxExpressionLength = 4096;
  final _results = <(String, String), DisplayValue>{};

  JsRuntime _runtime() {
    if (kIsWeb) {
      throw UnsupportedError('Display expressions require a native app build');
    }
    return JsRuntime(
      options: const JsRuntimeOptions(
        memoryLimitBytes: 16 * 1024 * 1024,
        maxStackSizeBytes: 512 * 1024,
        timeout: Duration(milliseconds: 100),
        maxTimers: 1,
        maxCallbacks: 1,
        maxPendingFutures: 1,
      ),
    );
  }

  String? validate(String? expression) {
    if (expression == null || expression.trim().isEmpty) return null;
    if (expression.length > maxExpressionLength) {
      return 'Expression is too long';
    }
    JsRuntime? runtime;
    try {
      runtime = kIsWeb ? JsRuntime() : _runtime();
      if (!kIsWeb) runtime.setTimeout(const Duration(milliseconds: 15));
      runtime.eval(
        'new Function("value", ${jsonEncode('"use strict"; return (\n$expression\n);')}); null',
      );
      return null;
    } catch (error) {
      return error.toString();
    } finally {
      runtime?.dispose();
    }
  }

  DisplayValue evaluate(String? expression, Object? value) {
    if (expression == null || expression.trim().isEmpty) {
      return DisplayValue(value);
    }
    String input;
    try {
      input = jsonEncode(value);
    } catch (_) {
      return DisplayValue(value, error: 'Unsupported input value');
    }
    if (expression.length > maxExpressionLength || input.length > 65536) {
      return DisplayValue(value, error: 'Expression or input is too large');
    }
    final key = (expression, input);
    final cached = _results.remove(key);
    if (cached != null) {
      _results[key] = cached;
      return cached;
    }
    JsRuntime? runtime;
    DisplayValue result;
    try {
      runtime = _runtime();
      // The native realm has no application callbacks or networking. Do not
      // leave timer/job host APIs available to a synchronous display field.
      runtime.eval(
        'for (const n of ["setTimeout", "setInterval", "queueMicrotask", "fetch", "console"]) '
        'Object.defineProperty(globalThis, n, {value: undefined, writable: false, configurable: false});',
      );
      runtime.setTimeout(const Duration(milliseconds: 15));
      final output = runtime.eval('''
        (function(value) {
          "use strict";
          const result = (\n$expression\n);
          const type = typeof result;
          if (result !== null && type !== 'number' && type !== 'string' && type !== 'boolean')
            throw new TypeError('Return a number, string, boolean or null');
          if (type === 'number' && !Number.isFinite(result))
            throw new TypeError('Return a finite number');
          if (type === 'string' && result.length > 16384)
            throw new RangeError('Display result is too long');
          return result;
        })(JSON.parse(${jsonEncode(input)}))
      ''');
      result = DisplayValue(output, applied: true);
    } catch (error) {
      result = DisplayValue(value, error: error.toString());
    } finally {
      runtime?.dispose();
    }
    _results[key] = result;
    if (_results.length > 256) _results.remove(_results.keys.first);
    return result;
  }
}

final displayExpressionEvaluatorProvider = Provider(
  (ref) => DisplayExpressionEvaluator(),
);

DisplayValue displayValue(WidgetRef ref, String? expression, Object? value) =>
    expression == null || expression.trim().isEmpty
    ? DisplayValue(value)
    : ref.read(displayExpressionEvaluatorProvider).evaluate(expression, value);
