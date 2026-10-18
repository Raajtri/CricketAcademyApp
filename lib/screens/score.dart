import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../core/repo.dart';
import '../core/scoring.dart';
import '../core/ui.dart';
import '../widgets/wagon_wheel.dart';
import 'match_detail.dart';

const _addNew = '\u0000add';

/// Live ball-by-ball scoring, laid out like CricHeroes: score header, batters,
/// bowler, this-over chips, then a run keypad with WD / NB / BYE / LB / OUT / UNDO.
class ScoreScreen extends StatefulWidget {
  final String matchId;
  const ScoreScreen({super.key, required this.matchId});
  @override
  State<ScoreScreen> createState() => _ScoreScreenState();
}

class _ScoreScreenState extends State<ScoreScreen> {
  late final Stream<CricketMatch?> _match = Repo.i.match(widget.matchId);
  late final Stream<List<Ball>> _balls = Repo.i.balls(widget.matchId);

  @override
  Widget build(BuildContext context) => Live<CricketMatch?>(
    stream: _match,
    builder: (c, m) {
      if (m == null) return const Scaffold(body: EmptyState('Match not found'));
      return Live<List<Ball>>(
        stream: _balls,
        builder: (c, balls) => _ScoreBody(match: m, allBalls: balls),
      );
    },
  );
}

class _Wkt {
  final String type;
  final String out;
  final String fielder;
  final int runs;
  _Wkt(this.type, this.out, this.fielder, this.runs);
}

class _ExtraPick {
  final int n;
  final bool wicket;
  _ExtraPick(this.n, this.wicket);
}

class _ScoreBody extends StatefulWidget {
  final CricketMatch match;
  final List<Ball> allBalls;
  const _ScoreBody({required this.match, required this.allBalls});
  @override
  State<_ScoreBody> createState() => _ScoreBodyState();
}

class _ScoreBodyState extends State<_ScoreBody> {
  String? _striker, _nonStriker, _bowler, _prevBowler;
  String _key = '';
  bool _declined = false;
  bool _dialogOpen = false;
  bool _shotOn = true;
  final Map<String, bool> _hand =
      {}; // batter -> bats left-handed (manual choice)

  /// Handedness of a batter: the manual choice, else what they were last scored as.
  bool _isLefty(String? name) {
    if (name == null) return false;
    final chosen = _hand[name];
    if (chosen != null) return chosen;
    for (final b in widget.allBalls.reversed) {
      if (b.striker == name) return b.lefty;
    }
    return false;
  }

  CricketMatch get m => widget.match;
  int get inn => m.currentInnings;

  /// Runs physically run by the batters on this ball (decides strike change).
  int _ran(Ball b) {
    switch (b.extra) {
      case 'wd':
        return b.extraRuns - 1;
      case 'b':
      case 'lb':
        return b.extraRuns;
      default:
        return b.runs;
    }
  }

  /// Re-derives who is at the crease whenever the ball list changes.
  void _sync(List<Ball> ib, InningsSummary sum) {
    final key = '$inn:${ib.length}:${ib.isEmpty ? '' : ib.last.id}';
    if (key == _key) return;
    _key = key;
    _declined = false;
    if (ib.isEmpty) {
      _striker = _nonStriker = _bowler = _prevBowler = null;
      return;
    }
    final l = ib.last;
    var s = l.striker, n = l.nonStriker;
    if (_ran(l).isOdd) {
      final t = s;
      s = n;
      n = t;
    }
    String? S = s, N = n;
    if (l.isWicket) {
      if (l.playerOut == S) {
        S = null;
      } else if (l.playerOut == N) {
        N = null;
      } else {
        S = null;
      }
    }
    String? B = l.bowler;
    if (l.isLegal && sum.legalBalls % 6 == 0) {
      final t = S;
      S = N;
      N = t;
      _prevBowler = l.bowler;
      B = null;
    } else {
      _prevBowler = null;
    }
    _striker = S;
    _nonStriker = N;
    _bowler = B;
  }

  @override
  Widget build(BuildContext context) {
    final ib = widget.allBalls.where((b) => b.innings == inn).toList()
      ..sort((a, b) => a.seq.compareTo(b.seq));
    final sum = InningsSummary.build(ib);
    _sync(ib, sum);

    final batters = m.battingPlayers(inn);
    final maxBalls = m.overs * 6;
    final allOut = sum.wickets >= (batters.length - 1).clamp(1, 99);
    final first = InningsSummary.build(
      widget.allBalls.where((b) => b.innings == 1).toList(),
    );
    final target = first.runs + 1;
    final chased = inn == 2 && sum.runs >= target;
    final inningsOver = sum.legalBalls >= maxBalls || allOut || chased;

    if (!inningsOver) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _ensurePlayers(sum));
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('${m.teamA} vs ${m.teamB}'),
        actions: [
          IconButton(
            tooltip: 'Scorecard & wagon wheel',
            icon: const Icon(Icons.table_chart_outlined),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => MatchDetailScreen(matchId: m.id),
              ),
            ),
          ),
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'end') await _endInnings(sum, first);
              if (v == 'swap') {
                setState(() {
                  final t = _striker;
                  _striker = _nonStriker;
                  _nonStriker = t;
                });
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'swap', child: Text('Swap batters')),
              PopupMenuItem(
                value: 'end',
                child: Text(inn == 1 ? 'End innings' : 'End match'),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(bottom: 8),
              children: [
                _header(sum, first, target, maxBalls),
                _battersCard(sum),
                _bowlerCard(sum),
                _overChips(ib),
              ],
            ),
          ),
          if (inningsOver) _endBanner(sum, first) else _keypad(ib),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------- header
  Widget _header(
    InningsSummary sum,
    InningsSummary first,
    int target,
    int maxBalls,
  ) {
    final t = Theme.of(context);
    String? chase;
    if (inn == 2) {
      final left = maxBalls - sum.legalBalls;
      final need = target - sum.runs;
      chase = need <= 0
          ? 'Target reached'
          : 'Target $target. Need $need from $left ball${left == 1 ? '' : 's'}'
                '${left > 0 ? '  •  RRR ${(need * 6 / left).toStringAsFixed(2)}' : ''}';
    }
    return Card(
      color: t.colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${m.battingTeam(inn)}  •  Innings $inn',
              style: t.textTheme.titleSmall,
            ),
            const SizedBox(height: 2),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${sum.runs}/${sum.wickets}',
                  style: t.textTheme.displayMedium,
                ),
                const SizedBox(width: 10),
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    '(${sum.overs}/${m.overs} ov)',
                    style: t.textTheme.titleMedium,
                  ),
                ),
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    'CRR ${sum.runRate.toStringAsFixed(2)}',
                    style: t.textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            if (chase != null) Text(chase, style: t.textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }

  Widget _battersCard(InningsSummary sum) {
    Widget row(String? name, bool onStrike, {required VoidCallback onTap}) {
      final st = name == null ? null : sum.batting[name];
      return InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
          child: Row(
            children: [
              Expanded(
                flex: 4,
                child: Text(
                  name == null
                      ? 'Select batter'
                      : (onStrike ? '$name *' : name),
                  style: TextStyle(
                    fontWeight: onStrike ? FontWeight.bold : FontWeight.normal,
                    color: name == null ? Colors.red : null,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (name != null) _handChip(name),
              _cell('${st?.runs ?? 0}', bold: true),
              _cell('${st?.balls ?? 0}'),
              _cell('${st?.fours ?? 0}'),
              _cell('${st?.sixes ?? 0}'),
              _cell(
                st == null || st.balls == 0
                    ? '-'
                    : st.strikeRate.toStringAsFixed(0),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
            child: Row(
              children: [
                const Expanded(
                  flex: 4,
                  child: Text(
                    'Batter',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                _cell('R', bold: true),
                _cell('B', bold: true),
                _cell('4s', bold: true),
                _cell('6s', bold: true),
                _cell('SR', bold: true),
              ],
            ),
          ),
          const Divider(height: 1),
          row(_striker, true, onTap: () => _replace('striker', sum)),
          row(_nonStriker, false, onTap: () => _replace('non-striker', sum)),
        ],
      ),
    );
  }

  /// Right / left-hand toggle. It decides the off and leg side names on the wagon wheel.
  Widget _handChip(String name) {
    final left = _isLefty(name);
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => setState(() => _hand[name] = !left),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            border: Border.all(color: Theme.of(context).colorScheme.outline),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            left ? 'LHB' : 'RHB',
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }

  Widget _bowlerCard(InningsSummary sum) {
    final st = _bowler == null ? null : sum.bowling[_bowler];
    return Card(
      child: InkWell(
        onTap: () => _replace('bowler', sum),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
          child: Row(
            children: [
              const Icon(Icons.sports_baseball, size: 18),
              const SizedBox(width: 8),
              Expanded(
                flex: 4,
                child: Text(
                  _bowler ?? 'Select bowler',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: _bowler == null ? Colors.red : null,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              _cell(st?.overs ?? '0.0'),
              _cell('${st?.runs ?? 0}'),
              _cell('${st?.wickets ?? 0}', bold: true),
              _cell(
                st == null || st.legalBalls == 0
                    ? '-'
                    : st.economy.toStringAsFixed(1),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _cell(String t, {bool bold = false}) => SizedBox(
    width: 40,
    child: Text(
      t,
      textAlign: TextAlign.right,
      style: TextStyle(fontWeight: bold ? FontWeight.w600 : FontWeight.normal),
    ),
  );

  Widget _overChips(List<Ball> ib) {
    // Balls of the over in progress (illegal deliveries stay attached to it).
    var cur = <Ball>[];
    var legal = 0;
    for (final b in ib) {
      cur.add(b);
      if (b.isLegal) legal++;
      if (b.isLegal && legal % 6 == 0) cur = [];
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(
        children: [
          const Text('This over  '),
          Expanded(
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [for (final b in cur) _chip(b)],
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(Ball b) {
    String t;
    Color bg = Colors.grey.shade300;
    Color fg = Colors.black87;
    if (b.isWicket) {
      t = b.total > 0 ? 'W+${b.total}' : 'W';
      bg = Colors.red.shade700;
      fg = Colors.white;
    } else if (b.extra == 'wd') {
      t = b.extraRuns > 1 ? 'Wd+${b.extraRuns - 1}' : 'Wd';
      bg = Colors.amber.shade300;
    } else if (b.extra == 'nb') {
      t = b.runs > 0 ? 'Nb+${b.runs}' : 'Nb';
      bg = Colors.amber.shade300;
    } else if (b.extra == 'b' || b.extra == 'lb') {
      t = '${b.extra == 'b' ? 'B' : 'Lb'}${b.extraRuns}';
      bg = Colors.amber.shade300;
    } else {
      t = b.runs == 0 ? '•' : '${b.runs}';
      if (b.runs == 4) {
        bg = Colors.orange.shade600;
        fg = Colors.white;
      } else if (b.runs >= 6) {
        bg = Colors.green.shade700;
        fg = Colors.white;
      }
    }
    return CircleAvatar(
      radius: 15,
      backgroundColor: bg,
      child: Text(
        t,
        style: TextStyle(
          color: fg,
          fontSize: t.length > 3 ? 9 : 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- keypad
  Widget _keypad(List<Ball> ib) {
    Widget k(String label, VoidCallback f, {Color? bg, Color? fg}) => Expanded(
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: SizedBox(
          height: 54,
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor:
                  bg ?? Theme.of(context).colorScheme.surfaceContainerHighest,
              foregroundColor: fg ?? Theme.of(context).colorScheme.onSurface,
              padding: EdgeInsets.zero,
            ),
            onPressed: f,
            child: Text(
              label,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ),
    );

    return Material(
      elevation: 8,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(6, 6, 6, 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  k('0', () => _bat(0)),
                  k('1', () => _bat(1)),
                  k('2', () => _bat(2)),
                  k('3', () => _bat(3)),
                ],
              ),
              Row(
                children: [
                  k(
                    '4',
                    () => _bat(4),
                    bg: Colors.orange.shade600,
                    fg: Colors.white,
                  ),
                  k('5', () => _bat(5)),
                  k(
                    '6',
                    () => _bat(6),
                    bg: Colors.green.shade700,
                    fg: Colors.white,
                  ),
                  k(
                    'UNDO',
                    () => _undo(ib),
                    bg: Colors.blueGrey.shade700,
                    fg: Colors.white,
                  ),
                ],
              ),
              Row(
                children: [
                  k('WD', () => _extra('wd')),
                  k('NB', () => _extra('nb')),
                  k('BYE', () => _extra('b')),
                  k('LB', () => _extra('lb')),
                ],
              ),
              Row(
                children: [
                  k('OUT', _out, bg: Colors.red.shade700, fg: Colors.white),
                  Expanded(
                    flex: 3,
                    child: SwitchListTile(
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                      title: const Text('Mark shot direction (wagon wheel)'),
                      value: _shotOn,
                      onChanged: (v) => setState(() => _shotOn = v),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _endBanner(InningsSummary sum, InningsSummary first) => Material(
    elevation: 8,
    child: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Expanded(
              child: Text(inn == 1 ? 'Innings complete' : 'Match complete'),
            ),
            FilledButton(
              onPressed: () => _endInnings(sum, first),
              child: Text(inn == 1 ? 'Start 2nd innings' : 'Finish match'),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: () {
                final ib =
                    widget.allBalls.where((b) => b.innings == inn).toList()
                      ..sort((a, b) => a.seq.compareTo(b.seq));
                _undo(ib);
              },
              child: const Text('Undo'),
            ),
          ],
        ),
      ),
    ),
  );

  // ------------------------------------------------------------ recording
  bool _ready() {
    if (_striker == null || _nonStriker == null || _bowler == null) {
      toast(context, 'Select batters and bowler first');
      setState(() => _declined = false);
      return false;
    }
    return true;
  }

  void _write(Ball b) {
    unawaited(
      Repo.i.addBall(m.id, b).catchError((Object e) {
        if (mounted) toast(context, 'Could not save ball: $e');
      }),
    );
  }

  int get _nextSeq => widget.allBalls.isEmpty
      ? 1
      : widget.allBalls.map((b) => b.seq).reduce((a, b) => a > b ? a : b) + 1;

  Ball _ball({
    int runs = 0,
    String extra = '',
    int extraRuns = 0,
    String wicket = '',
    String playerOut = '',
    String fielder = '',
    Offset? shot,
  }) => Ball(
    innings: inn,
    seq: _nextSeq,
    striker: _striker!,
    nonStriker: _nonStriker!,
    bowler: _bowler!,
    runs: runs,
    extra: extra,
    extraRuns: extraRuns,
    wicket: wicket,
    playerOut: playerOut,
    fielder: fielder,
    lefty: _isLefty(_striker),
    shotX: shot?.dx,
    shotY: shot?.dy,
  );

  Future<void> _bat(int runs) async {
    if (!_ready()) return;
    Offset? shot;
    if (_shotOn && runs > 0) {
      final r = await _askShot(runs);
      if (r == 'cancel') return;
      if (r is Offset) shot = r;
    }
    _write(_ball(runs: runs, shot: shot));
  }

  Future<void> _extra(String type) async {
    if (!_ready()) return;
    final pick = await _extraSheet(type);
    if (pick == null) return;
    int runs = 0, extraRuns = 0;
    switch (type) {
      case 'wd':
        extraRuns = 1 + pick.n;
        break;
      case 'nb':
        runs = pick.n;
        extraRuns = 1;
        break;
      default:
        extraRuns = pick.n;
    }
    if (pick.wicket) {
      final allowed = type == 'wd'
          ? ['Stumped', 'Run out', 'Hit wicket']
          : ['Run out'];
      final w = await _askWicket(allowed);
      if (w == null) return;
      // A run-out's completed runs are scored on top of the extra.
      if (type == 'nb') {
        runs = w.runs;
      } else if (type == 'wd') {
        extraRuns = 1 + w.runs;
      } else {
        extraRuns = w.runs;
      }
      _write(
        _ball(
          runs: runs,
          extra: type,
          extraRuns: extraRuns,
          wicket: w.type,
          playerOut: w.out,
          fielder: w.fielder,
        ),
      );
      return;
    }
    Offset? shot;
    if (type == 'nb' && runs > 0 && _shotOn) {
      final r = await _askShot(runs);
      if (r == 'cancel') return;
      if (r is Offset) shot = r;
    }
    _write(_ball(runs: runs, extra: type, extraRuns: extraRuns, shot: shot));
  }

  Future<void> _out() async {
    if (!_ready()) return;
    final w = await _askWicket([
      'Bowled',
      'Caught',
      'LBW',
      'Run out',
      'Stumped',
      'Hit wicket',
    ]);
    if (w == null) return;
    _write(
      _ball(runs: w.runs, wicket: w.type, playerOut: w.out, fielder: w.fielder),
    );
  }

  void _undo(List<Ball> ib) {
    if (ib.isEmpty) {
      toast(context, 'Nothing to undo');
      return;
    }
    unawaited(Repo.i.deleteBall(m.id, ib.last.id));
  }

  // -------------------------------------------------------------- dialogs
  Future<Object?> _askShot(int runs) => showDialog<Object>(
    context: context,
    barrierDismissible: false,
    builder: (c) => AlertDialog(
      title: Text('Where did the $runs go?'),
      contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ShotPicker(
              left: _isLefty(_striker),
              onPicked: (o) => Navigator.pop(c, o),
            ),
            const SizedBox(height: 6),
            const Text(
              'Tap the field. Bowler\'s end is at the top. Fours and sixes are drawn to the boundary.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(c, 'cancel'),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(c, 'skip'),
          child: const Text('Skip'),
        ),
      ],
    ),
  );

  Future<_ExtraPick?> _extraSheet(String type) {
    final title = {
      'wd': 'Wide',
      'nb': 'No ball',
      'b': 'Bye',
      'lb': 'Leg bye',
    }[type]!;
    final sub = {
      'wd': 'Extra runs run on the wide (the wide itself is +1)',
      'nb': 'Runs off the bat (the no ball itself is +1)',
      'b': 'Byes run',
      'lb': 'Leg byes run',
    }[type]!;
    final nums = type == 'wd'
        ? [0, 1, 2, 3, 4]
        : type == 'nb'
        ? [0, 1, 2, 3, 4, 5, 6]
        : [1, 2, 3, 4];
    return showModalBottomSheet<_ExtraPick>(
      context: context,
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(c).textTheme.titleLarge),
              Text(sub),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final n in nums)
                    SizedBox(
                      width: 56,
                      height: 52,
                      child: FilledButton.tonal(
                        onPressed: () => Navigator.pop(c, _ExtraPick(n, false)),
                        child: Text('$n', style: const TextStyle(fontSize: 18)),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => Navigator.pop(c, _ExtraPick(0, true)),
                icon: const Icon(Icons.close),
                label: const Text('Wicket on this ball'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<_Wkt?> _askWicket(List<String> types) {
    var type = types.first;
    var out = _striker!;
    String fielder = '';
    var runs = 0;
    final fielders = m.bowlingPlayers(inn);
    return showDialog<_Wkt>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) {
          final needsFielder =
              type == 'Caught' || type == 'Stumped' || type == 'Run out';
          return AlertDialog(
            title: const Text('Wicket'),
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      for (final t in types)
                        ChoiceChip(
                          label: Text(t),
                          selected: type == t,
                          onSelected: (_) => set(() {
                            type = t;
                            if (t != 'Run out') {
                              out = _striker!;
                              runs = 0;
                            }
                            fielder = '';
                          }),
                        ),
                    ],
                  ),
                  if (type == 'Run out') ...[
                    const SizedBox(height: 12),
                    const Text('Who is out?'),
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final p in [_striker!, _nonStriker!])
                          ChoiceChip(
                            label: Text(p),
                            selected: out == p,
                            onSelected: (_) => set(() => out = p),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Text('Runs completed'),
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final r in [0, 1, 2, 3])
                          ChoiceChip(
                            label: Text('$r'),
                            selected: runs == r,
                            onSelected: (_) => set(() => runs = r),
                          ),
                      ],
                    ),
                  ],
                  if (needsFielder) ...[
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: fielder.isEmpty ? null : fielder,
                      decoration: InputDecoration(
                        labelText: type == 'Caught'
                            ? 'Caught by (optional)'
                            : 'Fielder (optional)',
                      ),
                      items: [
                        for (final f in fielders)
                          DropdownMenuItem(value: f, child: Text(f)),
                      ],
                      onChanged: (v) => set(() => fielder = v ?? ''),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () =>
                    Navigator.pop(c, _Wkt(type, out, fielder, runs)),
                child: const Text('Out'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<String?> _pick(
    String title,
    List<String> options, {
    required bool batting,
  }) async {
    final r = await showDialog<String>(
      context: context,
      builder: (c) => SimpleDialog(
        title: Text(title),
        children: [
          for (final o in options)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(c, o),
              child: Text(o),
            ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(c, _addNew),
            child: const Text(
              '+ Add new player',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
    if (r == _addNew) return _addPlayer(batting);
    return r;
  }

  Future<String?> _addPlayer(bool batting) async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('New player'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, ctrl.text.trim()),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return null;
    final aBats = (m.battingFirst == 'A') == (inn == 1);
    final aSide = batting ? aBats : !aBats;
    unawaited(
      Repo.i.setMatch(m.id, {
        aSide ? 'playersA' : 'playersB': FieldValue.arrayUnion([name]),
      }),
    );
    return name;
  }

  List<String> _batterOptions(InningsSummary sum) => m
      .battingPlayers(inn)
      .where(
        (p) => !sum.batting.containsKey(p) && p != _striker && p != _nonStriker,
      )
      .toList();

  List<String> _bowlerOptions() =>
      m.bowlingPlayers(inn).where((p) => p != _prevBowler).toList();

  Future<void> _ensurePlayers(InningsSummary sum) async {
    if (_dialogOpen || _declined || !mounted) return;
    if (_striker != null && _nonStriker != null && _bowler != null) return;
    _dialogOpen = true;
    try {
      final opening = sum.batting.isEmpty;
      if (_striker == null) {
        final p = await _pick(
          opening ? 'Select striker' : 'New batter',
          _batterOptions(sum),
          batting: true,
        );
        if (p == null) {
          _declined = true;
          return;
        }
        _striker = p;
      }
      if (_nonStriker == null) {
        final p = await _pick(
          opening ? 'Select non-striker' : 'New batter',
          _batterOptions(sum),
          batting: true,
        );
        if (p == null) {
          _declined = true;
          return;
        }
        _nonStriker = p;
      }
      if (_bowler == null) {
        final p = await _pick(
          'Select bowler',
          _bowlerOptions(),
          batting: false,
        );
        if (p == null) {
          _declined = true;
          return;
        }
        _bowler = p;
      }
    } finally {
      _dialogOpen = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> _replace(String who, InningsSummary sum) async {
    if (who == 'bowler') {
      final p = await _pick('Select bowler', _bowlerOptions(), batting: false);
      if (p != null) setState(() => _bowler = p);
    } else {
      final p = await _pick('Select $who', _batterOptions(sum), batting: true);
      if (p == null) return;
      setState(() => who == 'striker' ? _striker = p : _nonStriker = p);
    }
  }

  // ---------------------------------------------------------- end of innings
  Future<void> _endInnings(InningsSummary sum, InningsSummary first) async {
    if (inn == 1) {
      if (!await confirm(
        context,
        'End first innings?',
        '${m.battingTeam(1)} finished on ${sum.runs}/${sum.wickets}. Start the second innings?',
      )) {
        return;
      }
      unawaited(Repo.i.setMatch(m.id, {'currentInnings': 2}));
    } else {
      if (!await confirm(context, 'Finish match?')) return;
      unawaited(
        Repo.i.setMatch(m.id, {
          'status': 'done',
          'result': _result(sum, first.runs),
        }),
      );
      if (mounted) Navigator.pop(context);
    }
  }

  String _result(InningsSummary s2, int firstRuns) {
    final chasing = m.battingTeam(2);
    final firstTeam = m.battingTeam(1);
    if (s2.runs > firstRuns) {
      final wl = (m.battingPlayers(2).length - 1) - s2.wickets;
      return '$chasing won by $wl wicket${wl == 1 ? '' : 's'}';
    }
    if (s2.runs == firstRuns) return 'Match tied';
    final by = firstRuns - s2.runs;
    return '$firstTeam won by $by run${by == 1 ? '' : 's'}';
  }
}
