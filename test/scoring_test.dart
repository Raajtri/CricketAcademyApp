import 'package:cricket_academy/core/models.dart';
import 'package:cricket_academy/core/repo.dart';
import 'package:cricket_academy/core/scoring.dart';
import 'package:flutter_test/flutter_test.dart';

Ball b(
  int seq, {
  int runs = 0,
  String extra = '',
  int extraRuns = 0,
  String wicket = '',
  String out = '',
  String fielder = '',
  String striker = 'A',
  String bowler = 'X',
}) => Ball(
  innings: 1,
  seq: seq,
  striker: striker,
  nonStriker: 'B',
  bowler: bowler,
  runs: runs,
  extra: extra,
  extraRuns: extraRuns,
  wicket: wicket,
  playerOut: out,
  fielder: fielder,
);

void main() {
  test('runs, balls, overs and strike rate', () {
    final s = InningsSummary.build([
      b(1, runs: 4),
      b(2, runs: 1),
      b(3),
      b(4, runs: 6),
    ]);
    expect(s.runs, 11);
    expect(s.legalBalls, 4);
    expect(s.overs, '0.4');
    expect(s.batting['A']!.runs, 11);
    expect(s.batting['A']!.fours, 1);
    expect(s.batting['A']!.sixes, 1);
    expect(s.bowling['X']!.runs, 11);
  });

  test('wide and no-ball are not legal; wide is not a ball faced', () {
    final s = InningsSummary.build([
      b(1, extra: 'wd', extraRuns: 2), // wide + 1 run
      b(2, extra: 'nb', extraRuns: 1, runs: 4), // no ball, 4 off the bat
      b(3, runs: 1),
    ]);
    expect(s.runs, 2 + 5 + 1);
    expect(s.legalBalls, 1);
    expect(s.batting['A']!.balls, 2); // nb + legal, not the wide
    expect(s.batting['A']!.runs, 5);
    expect(s.bowling['X']!.runs, 8); // wide 2 + nb 1 + 4 + 1
    expect(s.extras, 3);
  });

  test('byes are team runs but not bowler or batter runs', () {
    final s = InningsSummary.build([
      b(1, extra: 'b', extraRuns: 2),
      b(2, extra: 'lb', extraRuns: 1),
    ]);
    expect(s.runs, 3);
    expect(s.bowling['X']!.runs, 0);
    expect(s.batting['A']!.runs, 0);
    expect(s.batting['A']!.balls, 2);
    expect(s.legalBalls, 2);
  });

  test('wickets: bowler credited except run out; dismissal text', () {
    final s = InningsSummary.build([
      b(1, wicket: 'Caught', out: 'A', fielder: 'F'),
      b(2, wicket: 'Run out', out: 'B', fielder: 'G', striker: 'C'),
    ]);
    expect(s.wickets, 2);
    expect(s.bowling['X']!.wickets, 1);
    expect(s.batting['A']!.out, 'c F b X');
    expect(s.batting['B']!.out, 'run out (G)');
    expect(s.fallOfWickets.length, 2);
  });

  test('career stats average counts dismissals only', () {
    final c = CareerStats.compute({
      'm1#1': [b(1, runs: 10), b(2, wicket: 'Bowled', out: 'A')],
      'm2#1': [b(1, runs: 20)],
    })['A']!;
    expect(c.runs, 30);
    expect(c.outs, 1);
    expect(c.average, 30);
    expect(c.highScore, 20);
    expect(c.innings, 2);
  });

  test('fees: months since joining minus payments', () {
    final s = Student(
      id: 's',
      name: 'Kid',
      monthlyFee: 1000,
      joinDate: DateTime(2026, 1, 10),
    );
    final pays = [
      FeePayment(
        id: 'p1',
        studentId: 's',
        month: '2026-01',
        amount: 1000,
        paidOn: DateTime(2026, 1, 12),
      ),
      FeePayment(
        id: 'p2',
        studentId: 's',
        month: '2026-02',
        amount: 400,
        paidOn: DateTime(2026, 2, 12),
      ),
    ];
    final f = feeSummary(s, pays, now: DateTime(2026, 3, 5));
    expect(f.billed, 3000);
    expect(f.paid, 1400);
    expect(f.due, 1600);
    expect(f.unpaidMonths, ['2026-02', '2026-03']);
  });
}
