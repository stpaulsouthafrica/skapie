import 'package:flutter_test/flutter_test.dart';
import 'package:skapie/canvas/cable_layer.dart';

void main() {
  test('a left-to-right drag keeps the cable and flashes toward the input', () {
    final arrival = connectArrival(
      sawDrag: true,
      dragFrameId: 'left',
      sourceId: 'left',
      targetFrameId: 'right',
    );

    expect(arrival.grow, isFalse);
    expect(arrival.towardSource, isFalse);
    expect(arrival.draw(0), 1);
    expect(arrival.flash(0), 0);
    expect(arrival.flash(1), 1);
  });

  test('a right-to-left drag keeps the cable and flashes back toward the output', () {
    final arrival = connectArrival(
      sawDrag: true,
      dragFrameId: 'right',
      sourceId: 'left',
      targetFrameId: 'right',
    );

    expect(arrival.grow, isFalse);
    expect(arrival.towardSource, isTrue);
    expect(arrival.draw(0), 1);
    expect(arrival.flash(0), 1);
    expect(arrival.flash(0.25), closeTo(0.75, 0.001));
    expect(arrival.flash(1), 0);
  });

  test('a cable that appears without a drag still grows from the output', () {
    final arrival = connectArrival(
      sawDrag: false,
      dragFrameId: 'right',
      sourceId: 'left',
      targetFrameId: 'right',
    );

    expect(arrival.grow, isTrue);
    expect(arrival.towardSource, isFalse);
    expect(arrival.draw(0), 0);
    expect(arrival.draw(1), 1);
    expect(arrival.flash(0), 0);
    expect(arrival.flash(1), 1);
  });
}
