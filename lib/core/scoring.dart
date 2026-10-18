import 'package:cloud_firestore/cloud_firestore.dart';

/// One delivery. Everything (scorecards, career stats, undo) is derived from
/// the ordered list of balls, so the only thing we ever store is this.
///
/// Conventions:
///  - [runs]       runs off the bat (0 for byes/leg-byes/wides)
///  - [extra]      '' | 'wd' | 'nb' | 'b' | 'lb'
///  - [extraRuns]  wd: 1 + runs run; nb: 1 (penalty only; bat runs in [runs]);
///                 b/lb: runs run
///  - [wicket]     '' or the dismissal type; [playerOut] the batter dismissed
class Ball {
  final String id;
  final int innings;
  final int seq;
  final String striker;
  final String nonStriker;
  final String bowler;
  final int runs;
  final String extra;
  final int extraRuns;
  final String wicket;
  final String playerOut;
  final String fielder; // catcher / stumper / run-out fielder, optional

  /// Striker bats left-handed. Only changes the off/leg side names on the wagon wheel.
  final bool lefty;

  /// Where the shot went, for the wagon wheel: position on the ground relative
  /// to the pitch centre, each in -1..1 (x: right, y: down the page, so the
  /// bowler's end is at the top). Null when the scorer did not mark it.
  final double? shotX;
  final double? shotY;

  Ball({
    this.id = '',
    required this.innings,
    required this.seq,
    required this.striker,
    required this.nonStriker,
    required this.bowler,
    this.runs = 0,
    this.extra = '',
    this.extraRuns = 0,
    this.wicket = '',
    this.playerOut = '',
    this.fielder = '',
    this.lefty = false,
    this.shotX,
    this.shotY,
  });

  bool get hasShot => shotX != null && shotY != null;

  bool get isLegal => extra != 'wd' && extra != 'nb';
  int get total => runs + extraRuns;
  bool get isWicket => wicket.isNotEmpty;

  /// Scorecard style: "c Rahul b Aman", "b Aman", "run out (Rahul)".
  String get dismissalText {
    final f = fielder.isEmpty ? '' : fielder;
    switch (wicket) {
      case 'Caught':
        return f.isEmpty
            ? 'c & b $bowler'
            : (f == bowler ? 'c & b $bowler' : 'c $f b $bowler');
      case 'Stumped':
        return f.isEmpty ? 'st b $bowler' : 'st $f b $bowler';
      case 'Run out':
        return f.isEmpty ? 'run out' : 'run out ($f)';
      case 'LBW':
        return 'lbw b $bowler';
      case 'Hit wicket':
        return 'hit wicket b $bowler';
      case 'Bowled':
        return 'b $bowler';
      default:
        return wicket;
    }
  }

  /// Run-outs are not credited to the bowler.
  bool get bowlerWicket =>
      isWicket && wicket != 'Run out' && wicket != 'Retired';

  factory Ball.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? {};
    return Ball(
      id: d.id,
      innings: (m['innings'] ?? 1).toInt(),
      seq: (m['seq'] ?? 0).toInt(),
      striker: m['striker'] ?? '',
      nonStriker: m['nonStriker'] ?? '',
      bowler: m['bowler'] ?? '',
      runs: (m['runs'] ?? 0).toInt(),
      extra: m['extra'] ?? '',
      extraRuns: (m['extraRuns'] ?? 0).toInt(),
      wicket: m['wicket'] ?? '',
      playerOut: m['playerOut'] ?? '',
      fielder: m['fielder'] ?? '',
      lefty: m['lefty'] ?? false,
      shotX: (m['shotX'] as num?)?.toDouble(),
      shotY: (m['shotY'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toMap() => {
    if (hasShot) 'shotX': shotX,
    if (hasShot) 'shotY': shotY,
    'innings': innings,
    'seq': seq,
    'striker': striker,
    'nonStriker': nonStriker,
    'bowler': bowler,
    'runs': runs,
    'extra': extra,
    'extraRuns': extraRuns,
    'wicket': wicket,
    'playerOut': playerOut,
    'fielder': fielder,
    'lefty': lefty,
  };
}

class CricketMatch {
  final String id;
  final String teamA;
  final String teamB;
  final List<String> playersA;
  final List<String> playersB;
  final int overs;
  final String battingFirst; // 'A' | 'B'
  final int currentInnings; // 1 | 2
  final String status; // 'live' | 'done'
  final String result;
  final DateTime date;

  CricketMatch({
    required this.id,
    required this.teamA,
    required this.teamB,
    required this.playersA,
    required this.playersB,
    required this.overs,
    required this.battingFirst,
    this.currentInnings = 1,
    this.status = 'live',
    this.result = '',
    required this.date,
  });

  bool get isLive => status == 'live';

  /// Team batting in the given innings (1 or 2).
  String battingTeam(int innings) {
    final firstIsA = battingFirst == 'A';
    final aBats = innings == 1 ? firstIsA : !firstIsA;
    return aBats ? teamA : teamB;
  }

  List<String> battingPlayers(int innings) {
    final firstIsA = battingFirst == 'A';
    final aBats = innings == 1 ? firstIsA : !firstIsA;
    return aBats ? playersA : playersB;
  }

  List<String> bowlingPlayers(int innings) {
    final firstIsA = battingFirst == 'A';
    final aBats = innings == 1 ? firstIsA : !firstIsA;
    return aBats ? playersB : playersA;
  }

  factory CricketMatch.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? {};
    List<String> l(dynamic v) =>
        (v as List? ?? []).map((e) => e.toString()).toList();
    return CricketMatch(
      id: d.id,
      teamA: m['teamA'] ?? 'Team A',
      teamB: m['teamB'] ?? 'Team B',
      playersA: l(m['playersA']),
      playersB: l(m['playersB']),
      overs: (m['overs'] ?? 20).toInt(),
      battingFirst: m['battingFirst'] ?? 'A',
      currentInnings: (m['currentInnings'] ?? 1).toInt(),
      status: m['status'] ?? 'live',
      result: m['result'] ?? '',
      date: m['date'] is Timestamp
          ? (m['date'] as Timestamp).toDate()
          : DateTime.now(),
    );
  }
}

class BatStat {
  int runs = 0, balls = 0, fours = 0, sixes = 0;
  String out = ''; // '' = not out / yet to bat handled by caller
  bool batted = false;
  double get strikeRate => balls == 0 ? 0 : runs * 100 / balls;
}

class BowlStat {
  int legalBalls = 0, runs = 0, wickets = 0;
  String get overs => '${legalBalls ~/ 6}.${legalBalls % 6}';
  double get economy => legalBalls == 0 ? 0 : runs * 6 / legalBalls;
}

class InningsSummary {
  int runs = 0, wickets = 0, legalBalls = 0, extras = 0;
  final Map<String, BatStat> batting = {};
  final Map<String, BowlStat> bowling = {};
  final List<String> fallOfWickets = [];

  String get overs => '${legalBalls ~/ 6}.${legalBalls % 6}';
  double get runRate => legalBalls == 0 ? 0 : runs * 6 / legalBalls;

  /// Replays [balls] (already filtered to one innings) in seq order.
  static InningsSummary build(List<Ball> balls) {
    final s = InningsSummary();
    final sorted = [...balls]..sort((a, b) => a.seq.compareTo(b.seq));
    for (final b in sorted) {
      final bat = s.batting.putIfAbsent(b.striker, () => BatStat())
        ..batted = true;
      s.batting.putIfAbsent(b.nonStriker, () => BatStat()).batted = true;
      final bowl = s.bowling.putIfAbsent(b.bowler, () => BowlStat());

      s.runs += b.total;
      if (b.extra.isNotEmpty) s.extras += b.extraRuns;
      if (b.isLegal) {
        s.legalBalls++;
        bowl.legalBalls++;
      }
      // Bat runs and balls faced (a wide is not a ball faced).
      if (b.extra != 'wd') {
        bat.balls++;
        if (b.extra != 'b' && b.extra != 'lb') {
          bat.runs += b.runs;
          if (b.runs == 4) bat.fours++;
          if (b.runs == 6) bat.sixes++;
        }
      }
      // Byes and leg-byes are not charged to the bowler.
      bowl.runs +=
          b.runs + ((b.extra == 'wd' || b.extra == 'nb') ? b.extraRuns : 0);
      if (b.isWicket) {
        s.wickets++;
        final out = b.playerOut.isEmpty ? b.striker : b.playerOut;
        final stat = s.batting.putIfAbsent(out, () => BatStat())..batted = true;
        stat.out = b.dismissalText;
        if (b.bowlerWicket) bowl.wickets++;
        s.fallOfWickets.add('${s.runs}-${s.wickets} ($out)');
      }
    }
    return s;
  }
}

/// Career stats for one player across many balls (all matches).
class CareerStats {
  int innings = 0, runs = 0, balls = 0, fours = 0, sixes = 0, outs = 0;
  int bowlBalls = 0, bowlRuns = 0, wickets = 0;
  int highScore = 0;
  double get average => outs == 0 ? runs.toDouble() : runs / outs;
  double get strikeRate => balls == 0 ? 0 : runs * 100 / balls;
  String get overs => '${bowlBalls ~/ 6}.${bowlBalls % 6}';
  double get economy => bowlBalls == 0 ? 0 : bowlRuns * 6 / bowlBalls;

  /// [ballsByMatchInnings]: key "matchId#innings" -> balls of that innings.
  static Map<String, CareerStats> compute(
    Map<String, List<Ball>> ballsByMatchInnings,
  ) {
    final out = <String, CareerStats>{};
    CareerStats of(String n) => out.putIfAbsent(n, () => CareerStats());
    for (final balls in ballsByMatchInnings.values) {
      final s = InningsSummary.build(balls);
      s.batting.forEach((name, b) {
        if (!b.batted) return;
        final c = of(name);
        c.innings++;
        c.runs += b.runs;
        c.balls += b.balls;
        c.fours += b.fours;
        c.sixes += b.sixes;
        if (b.out.isNotEmpty) c.outs++;
        if (b.runs > c.highScore) c.highScore = b.runs;
      });
      s.bowling.forEach((name, b) {
        final c = of(name);
        c.bowlBalls += b.legalBalls;
        c.bowlRuns += b.runs;
        c.wickets += b.wickets;
      });
    }
    return out;
  }
}
