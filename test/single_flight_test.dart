import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/core/single_flight.dart';

void main() {
  test('SingleFlight shares one in-flight action across callers', () async {
    final singleFlight = SingleFlight<int>();
    final completer = Completer<int>();
    var calls = 0;

    Future<int> action() {
      calls++;
      return completer.future;
    }

    final first = singleFlight.run(action);
    final second = singleFlight.run(action);

    expect(calls, 1);

    completer.complete(42);

    await expectLater(first, completion(42));
    await expectLater(second, completion(42));
  });

  test('SingleFlight clears after completion and after failure', () async {
    final singleFlight = SingleFlight<int>();
    var calls = 0;

    try {
      await singleFlight.run(() {
        calls++;
        return Future<int>.delayed(
          Duration.zero,
          () => throw StateError('boom'),
        );
      });
      fail('expected StateError');
    } catch (error) {
      expect(error, isA<StateError>());
    }

    await expectLater(
      singleFlight.run(() async {
        calls++;
        return 7;
      }),
      completion(7),
    );

    expect(calls, 2);
  });
}
