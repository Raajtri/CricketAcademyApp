import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/scoring.dart';

const _c123 = Color(0xFF1E6FD9);
const _c4 = Color(0xFFF29100);
const _c6 = Color(0xFFC62828);
const _cDot = Color(0xFF9E9E9E);

Color shotColor(int runs) {
  if (runs >= 6) return _c6;
  if (runs == 4) return _c4;
  if (runs > 0) return _c123;
  return _cDot;
}

/// Fours and sixes are drawn all the way to the rope, however far in the
/// scorer tapped.
bool isBoundary(int runs) => runs == 4 || runs >= 6;

/// Field zones in order, clockwise from straight down the ground, for a
/// right-hand batter (off side on the right of the page, bowler at the top).
const zoneNames = [
  'Long Off',
  'Cover',
  'Point',
  'Third Man',
  'Fine Leg',
  'Square Leg',
  'Mid Wicket',
  'Long On',
];

/// True when every shown shot is from a left-hander. The wheel is then drawn
/// as that batter sees it (zone names mirrored). Otherwise left-handers are
/// mirrored onto a right-hander's wheel so off and leg side line up.
bool leftFrame(List<Ball> balls) {
  final shots = balls.where((b) => b.hasShot && b.runs > 0).toList();
  return shots.isNotEmpty && shots.every((b) => b.lefty);
}

/// Where a shot sits on the wheel in the chosen frame.
Offset displayPoint(Ball b, bool leftFrame) {
  var x = b.shotX!;
  if (!leftFrame && b.lefty) x = -x;
  var p = Offset(x, b.shotY!);
  if (isBoundary(b.runs) && p.distance > 0) p = p / p.distance;
  return p;
}

/// Zone index (0-7, into [zoneNames]) for a position on the wheel.
int zoneOfPoint(Offset p, bool leftFrame) {
  final x = leftFrame ? -p.dx : p.dx;
  var a = math.atan2(x, -p.dy); // 0 = straight, clockwise
  if (a < 0) a += 2 * math.pi;
  return (a / (math.pi / 4)).floor() % 8;
}

class ZoneTotal {
  int runs = 0;
  int shots = 0;
}

List<ZoneTotal> zoneTotals(List<Ball> balls, bool leftFrame) {
  final out = List.generate(8, (_) => ZoneTotal());
  for (final b in balls) {
    if (!b.hasShot || b.runs == 0) continue;
    final z = out[zoneOfPoint(displayPoint(b, leftFrame), leftFrame)];
    z.runs += b.runs;
    z.shots++;
  }
  return out;
}

void _text(
  Canvas canvas,
  String s,
  Offset center,
  double size,
  Color color, {
  bool bold = false,
}) {
  final tp = TextPainter(
    text: TextSpan(
      text: s,
      style: TextStyle(
        color: color,
        fontSize: size,
        fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
      ),
    ),
    textAlign: TextAlign.center,
    textDirection: TextDirection.ltr,
  )..layout();
  tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
}

void _paintGround(
  Canvas canvas,
  Size size, {
  required bool left,
  List<ZoneTotal>? totals,
}) {
  final c = size.center(Offset.zero);
  final r = size.shortestSide / 2 - 2;
  canvas.drawCircle(c, r, Paint()..color = const Color(0xFF2E8B4A));
  // Zone dividers.
  final divider = Paint()
    ..color = Colors.white30
    ..strokeWidth = 1;
  for (var i = 0; i < 8; i++) {
    final a = i * math.pi / 4;
    final d = Offset(math.sin(a), -math.cos(a));
    canvas.drawLine(c + d * r * 0.12, c + d * r, divider);
  }
  canvas.drawCircle(
    c,
    r * 0.55,
    Paint()
      ..color = Colors.white54
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2,
  );
  canvas.drawCircle(
    c,
    r,
    Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5,
  );
  // Pitch strip, bowler's end at the top.
  canvas.drawRect(
    Rect.fromCenter(center: c, width: r * 0.10, height: r * 0.34),
    Paint()..color = const Color(0xFFD9C08A),
  );
  // Zone names (and run totals when given).
  final fs = math.max(9.0, r * 0.055);
  for (var i = 0; i < 8; i++) {
    final mid = (i + 0.5) * math.pi / 4 * (left ? -1 : 1);
    final pos = c + Offset(math.sin(mid), -math.cos(mid)) * r * 0.80;
    final t = totals?[i];
    _text(
      canvas,
      zoneNames[i],
      pos - Offset(0, t == null ? 0 : fs * 0.6),
      fs,
      Colors.white70,
    );
    if (t != null) {
      _text(
        canvas,
        '${t.runs}',
        pos + Offset(0, fs * 0.75),
        fs * 1.25,
        Colors.white,
        bold: true,
      );
    }
  }
}

/// Draws every ball that has a recorded shot as a line from the pitch centre.
class WagonWheel extends StatelessWidget {
  final List<Ball> balls;
  const WagonWheel({super.key, required this.balls});

  @override
  Widget build(BuildContext context) {
    final left = leftFrame(balls);
    return AspectRatio(
      aspectRatio: 1,
      child: CustomPaint(
        painter: _WheelPainter(
          balls.where((b) => b.hasShot && b.runs > 0).toList(),
          left,
          zoneTotals(balls, left),
        ),
      ),
    );
  }
}

class _WheelPainter extends CustomPainter {
  final List<Ball> shots;
  final bool left;
  final List<ZoneTotal> totals;
  _WheelPainter(this.shots, this.left, this.totals);

  @override
  void paint(Canvas canvas, Size size) {
    _paintGround(canvas, size, left: left, totals: totals);
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2 - 2;
    // Lower runs first so boundaries stay visible on top.
    final sorted = [...shots]..sort((a, b) => a.runs.compareTo(b.runs));
    for (final b in sorted) {
      final p = c + displayPoint(b, left) * r;
      canvas.drawLine(
        c,
        p,
        Paint()
          ..color = shotColor(b.runs)
          ..strokeWidth = b.runs >= 4 ? 2.6 : 1.8
          ..strokeCap = StrokeCap.round,
      );
      canvas.drawCircle(p, 3, Paint()..color = shotColor(b.runs));
    }
  }

  @override
  bool shouldRepaint(_WheelPainter old) => true;
}

class WheelLegend extends StatelessWidget {
  const WheelLegend({super.key});
  @override
  Widget build(BuildContext context) {
    Widget dot(Color c, String t) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: c, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(t),
      ],
    );
    return Wrap(
      spacing: 16,
      runSpacing: 4,
      alignment: WrapAlignment.center,
      children: [dot(_c123, '1-3 runs'), dot(_c4, 'Four'), dot(_c6, 'Six')],
    );
  }
}

/// Tap where the ball went. Used while scoring; calls [onPicked] with the
/// position as -1..1 relative to the pitch centre (x right, y down). Zone names
/// follow the batter's hand ([left]).
class ShotPicker extends StatelessWidget {
  final bool left;
  final ValueChanged<Offset> onPicked;
  const ShotPicker({super.key, this.left = false, required this.onPicked});

  @override
  Widget build(BuildContext context) => AspectRatio(
    aspectRatio: 1,
    child: LayoutBuilder(
      builder: (context, box) {
        final size = Size(box.maxWidth, box.maxHeight);
        return GestureDetector(
          onTapDown: (d) => onPicked(_normalise(d.localPosition, size)),
          child: CustomPaint(painter: _PickerPainter(left)),
        );
      },
    ),
  );

  Offset _normalise(Offset local, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2 - 2;
    var o = (local - c) / r;
    final len = o.distance;
    if (len > 1) o = o / len; // clamp to the boundary
    return o;
  }
}

class _PickerPainter extends CustomPainter {
  final bool left;
  _PickerPainter(this.left);

  @override
  void paint(Canvas canvas, Size size) =>
      _paintGround(canvas, size, left: left);

  @override
  bool shouldRepaint(_PickerPainter old) => old.left != left;
}
