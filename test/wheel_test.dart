import 'dart:math' as math;

import 'package:cricket_academy/core/scoring.dart';
import 'package:cricket_academy/widgets/wagon_wheel.dart';
import 'package:flutter_test/flutter_test.dart';

/// A shot at [deg] degrees clockwise from straight down the ground, at [len] of the radius.
Ball shot(
  double deg, {
  int runs = 1,
  bool lefty = false,
  double len = 0.6,
  int innings = 1,
}) {
  final a = deg * math.pi / 180;
  return Ball(
    innings: innings,
    seq: 1,
    striker: 'A',
    nonStriker: 'B',
    bowler: 'X',
    runs: runs,
    lefty: lefty,
    shotX: math.sin(a) * len,
    shotY: -math.cos(a) * len,
  );
}

String zone(Ball b, bool left) =>
    zoneNames[zoneOfPoint(displayPoint(b, left), left)];

void main() {
  test('right-hander: off side is on the right of the page', () {
    expect(zone(shot(20), false), 'Long Off');
    expect(zone(shot(67), false), 'Cover');
    expect(zone(shot(110), false), 'Point');
    expect(zone(shot(157), false), 'Third Man');
    expect(zone(shot(200), false), 'Fine Leg');
    expect(zone(shot(250), false), 'Square Leg');
    expect(zone(shot(290), false), 'Mid Wicket');
    expect(zone(shot(340), false), 'Long On');
  });

  test('left-hander: the same spot on the ground is a leg-side zone', () {
    // 67 degrees (right of the page) is cover for a righty but mid-wicket for a lefty.
    final b = shot(67, lefty: true);
    expect(zone(b, true), 'Mid Wicket');
    // In a mixed-hand team wheel the lefty is mirrored onto the righty frame: same zone.
    expect(zone(b, false), 'Mid Wicket');
  });

  test('left-frame only when every shown shot is left-handed', () {
    expect(leftFrame([shot(10, lefty: true), shot(20, lefty: true)]), isTrue);
    expect(leftFrame([shot(10, lefty: true), shot(20)]), isFalse);
    expect(leftFrame([]), isFalse);
  });

  test('fours and sixes are drawn to the boundary, singles are not', () {
    expect(
      displayPoint(shot(90, runs: 6, len: 0.3), false).distance,
      closeTo(1.0, 1e-9),
    );
    expect(
      displayPoint(shot(90, runs: 4, len: 0.5), false).distance,
      closeTo(1.0, 1e-9),
    );
    expect(
      displayPoint(shot(90, runs: 2, len: 0.5), false).distance,
      closeTo(0.5, 1e-9),
    );
  });

  test('zone totals add runs and shots per zone', () {
    final t = zoneTotals([
      shot(67, runs: 4),
      shot(70, runs: 1),
      shot(200, runs: 6),
    ], false);
    expect(t[1].runs, 5); // Cover
    expect(t[1].shots, 2);
    expect(t[4].runs, 6); // Fine Leg
    expect(t.fold<int>(0, (a, z) => a + z.runs), 11);
  });

  test('balls without a recorded shot are ignored', () {
    final plain = Ball(
      innings: 1,
      seq: 1,
      striker: 'A',
      nonStriker: 'B',
      bowler: 'X',
      runs: 4,
    );
    expect(zoneTotals([plain], false).fold<int>(0, (a, z) => a + z.runs), 0);
  });
}
