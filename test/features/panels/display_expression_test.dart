import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:wiredash/data/database/tables/panels.dart';
import 'package:wiredash/features/panels/models/display_expression.dart';
import 'package:wiredash/features/panels/models/panel_config.dart';

void main() {
  late DisplayExpressionEvaluator evaluator;
  setUp(() => evaluator = DisplayExpressionEvaluator());

  test('blank expressions preserve scalar types and missing values', () {
    for (final value in [null, '0012', 12.5, false]) {
      final result = evaluator.evaluate('  ', value);
      expect(result.value, value);
      expect(result.applied, isFalse);
      expect(result.error, isNull);
    }
  });

  test(
    'real JavaScript scales values and preserves toFixed trailing zeroes',
    () {
      for (final value in [123400, '123400']) {
        final result = evaluator.evaluate(
          '(Number(value) / Math.pow(10, 4)).toFixed(2)',
          value,
        );
        expect(result.value, '12.34');
        expect(result.applied, isTrue);
        expect(result.error, isNull);
      }
      expect(
        evaluator.evaluate('Number(value).toFixed(3)', 12).value,
        '12.000',
      );
      expect(evaluator.evaluate('value / 10 ** 2', '1200').value, 12);
      expect(evaluator.evaluate('Math.round(Number(value))', 12.6).value, 13);
    },
  );

  test(
    'strings booleans null and object-valued inputs follow JavaScript semantics',
    () {
      expect(
        evaluator.evaluate('value === "ON" ? "Ready" : "Stopped"', 'ON').value,
        'Ready',
      );
      expect(
        evaluator.evaluate('value !== null && Number(value) > 0', 1).value,
        true,
      );
      expect(
        evaluator.evaluate('value === null ? null : value', null).value,
        null,
      );
      expect(
        evaluator.evaluate('value.power / 100', {'power': 1234}).value,
        12.34,
      );
      expect(
        evaluator.evaluate('value', '"; throw new Error("injected");').value,
        '"; throw new Error("injected");',
      );
    },
  );

  test(
    'invalid expressions and unsupported results fall back to the original value',
    () {
      for (final expression in [
        'value +',
        'missingVariable',
        'NaN',
        'Infinity',
        'value / 0',
        'undefined',
        '({value})',
        'Promise.resolve(value)',
      ]) {
        final result = evaluator.evaluate(expression, 42);
        expect(result.value, 42, reason: expression);
        expect(result.applied, isFalse, reason: expression);
        expect(result.error, isNotEmpty, reason: expression);
      }
      expect(evaluator.validate('value +'), isNotNull);
      expect(evaluator.validate('(Number(value) / 100).toFixed(2)'), isNull);
      expect(
        evaluator.validate('missingVariable'),
        isNull,
        reason: 'Compilation must not depend on the current sample value',
      );
    },
  );

  test('native execution and allocation limits stop bad expressions', () {
    final watch = Stopwatch()..start();
    expect(evaluator.validate('(() => { while (true) {} })()'), isNull);
    final loop = evaluator.evaluate(
      '(() => { while (true) {} })()',
      'original',
    );
    expect(loop.value, 'original');
    expect(loop.error, isNotEmpty);
    final memory = evaluator.evaluate('"x".repeat(1000000000)', 'original');
    expect(memory.value, 'original');
    expect(memory.error, isNotEmpty);
    expect(watch.elapsed, lessThan(const Duration(seconds: 3)));
  });

  test('display fields have no host APIs and cannot share modified globals', () {
    expect(
      evaluator
          .evaluate(
            'typeof fetch + "," + typeof setTimeout + "," + typeof setInterval',
            0,
          )
          .value,
      'undefined,undefined,undefined',
    );
    expect(
      evaluator.evaluate('(globalThis.customValue = 99, value)', 12).value,
      12,
    );
    expect(
      evaluator.evaluate('typeof globalThis.customValue', 12).value,
      'undefined',
    );
    expect(evaluator.evaluate('"x".repeat(20000)', 12).error, isNotEmpty);
    expect(evaluator.evaluate('x' * 4097, 12).error, isNotEmpty);
  });

  test(
    'expressions survive config JSON and empty expressions keep legacy configs unchanged',
    () {
      for (final type in [
        PanelType.toggle,
        PanelType.slider,
        PanelType.led,
        PanelType.nodeStatus,
        PanelType.progress,
        PanelType.combo,
        PanelType.radio,
        PanelType.multiState,
        PanelType.textLog,
        PanelType.reading,
      ]) {
        final original = PanelConfig.defaultFor(type);
        expect(original.toJson().containsKey('valueExpression'), isFalse);
        final json = {
          ...original.toJson(),
          'valueExpression': 'Number(value).toFixed(2)',
        };
        final configured = PanelConfig.decode(type, _encode(json));
        expect(configured.valueExpression, 'Number(value).toFixed(2)');
        expect(
          PanelConfig.decode(type, configured.encode()).valueExpression,
          configured.valueExpression,
        );
      }
      const display = DevicePanelDisplay(
        properties: ['K1'],
        labels: {'K1': 'Kitchen'},
        expressions: {'K1': 'Number(value) ? "Running" : "Stopped"'},
      );
      expect(
        DevicePanelDisplay.fromJson(display.toJson()).toJson(),
        display.toJson(),
      );
      expect(display.isDefault, isFalse);
      const reading = ReadingConfig(valueExpression: 'value / 100');
      expect(reading.copyWith(unit: 'V').valueExpression, 'value / 100');
    },
  );
}

String _encode(Map<String, dynamic> value) => jsonEncode(value);
