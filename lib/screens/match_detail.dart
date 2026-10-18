import 'package:flutter/material.dart';

import '../core/repo.dart';
import '../core/scoring.dart';
import '../core/ui.dart';
import '../widgets/wagon_wheel.dart';
import 'score.dart';

/// Scorecard and wagon wheel for any match (live or finished).
class MatchDetailScreen extends StatefulWidget {
  final String matchId;
  const MatchDetailScreen({super.key, required this.matchId});
  @override
  State<MatchDetailScreen> createState() => _MatchDetailScreenState();
}

class _MatchDetailScreenState extends State<MatchDetailScreen> {
  late final Stream<CricketMatch?> _match = Repo.i.match(widget.matchId);
  late final Stream<List<Ball>> _balls = Repo.i.balls(widget.matchId);

  @override
  Widget build(BuildContext context) => Live<CricketMatch?>(
    stream: _match,
    builder: (c, m) {
      if (m == null) return const Scaffold(body: EmptyState('Match not found'));
      return Live<List<Ball>>(
        stream: _balls,
        builder: (c, balls) => DefaultTabController(
          length: 2,
          child: Scaffold(
            appBar: AppBar(
              title: Text('${m.teamA} vs ${m.teamB}'),
              bottom: const TabBar(
                tabs: [
                  Tab(text: 'Scorecard'),
                  Tab(text: 'Wagon wheel'),
                ],
              ),
              actions: [
                if (m.isLive)
                  TextButton.icon(
                    onPressed: () => Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ScoreScreen(matchId: m.id),
                      ),
                    ),
                    icon: const Icon(Icons.edit),
                    label: const Text('Score'),
                  ),
              ],
            ),
            body: TabBarView(
              children: [
                _Scorecard(match: m, balls: balls),
                _MatchWheel(match: m, balls: balls),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class _Scorecard extends StatelessWidget {
  final CricketMatch match;
  final List<Ball> balls;
  const _Scorecard({required this.match, required this.balls});

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[
      Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          match.isLive
              ? 'LIVE'
              : (match.result.isEmpty ? 'Completed' : match.result),
          style: Theme.of(context).textTheme.titleLarge,
        ),
      ),
    ];
    for (var inn = 1; inn <= match.currentInnings; inn++) {
      final ib = balls.where((b) => b.innings == inn).toList();
      children.add(
        _InningsCard(match: match, inn: inn, sum: InningsSummary.build(ib)),
      );
    }
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: children,
    );
  }
}

class _InningsCard extends StatelessWidget {
  final CricketMatch match;
  final int inn;
  final InningsSummary sum;
  const _InningsCard({
    required this.match,
    required this.inn,
    required this.sum,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final batters = match.battingPlayers(inn);
    final batted = sum.batting.entries.where((e) => e.value.batted).toList();
    final yetToBat = batters.where((p) => !sum.batting.containsKey(p)).toList();
    Widget h(String s, {double w = 44}) => SizedBox(
      width: w,
      child: Text(
        s,
        textAlign: TextAlign.right,
        style: t.textTheme.labelMedium,
      ),
    );
    Widget v(String s, {bool bold = false, double w = 44}) => SizedBox(
      width: w,
      child: Text(
        s,
        textAlign: TextAlign.right,
        style: TextStyle(fontWeight: bold ? FontWeight.bold : null),
      ),
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    match.battingTeam(inn),
                    style: t.textTheme.titleMedium,
                  ),
                ),
                Text(
                  '${sum.runs}/${sum.wickets}  (${sum.overs} ov)',
                  style: t.textTheme.titleMedium,
                ),
              ],
            ),
            const Divider(),
            Row(
              children: [
                Expanded(child: Text('Batter', style: t.textTheme.labelMedium)),
                h('R'),
                h('B'),
                h('4s'),
                h('6s'),
                h('SR', w: 50),
              ],
            ),
            for (final e in batted)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            e.key,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          Text(
                            e.value.out.isEmpty ? 'not out' : e.value.out,
                            style: t.textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    v('${e.value.runs}', bold: true),
                    v('${e.value.balls}'),
                    v('${e.value.fours}'),
                    v('${e.value.sixes}'),
                    v(
                      e.value.balls == 0
                          ? '-'
                          : e.value.strikeRate.toStringAsFixed(1),
                      w: 50,
                    ),
                  ],
                ),
              ),
            if (yetToBat.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                'Did not bat: ${yetToBat.join(', ')}',
                style: t.textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 6),
            Text('Extras: ${sum.extras}', style: t.textTheme.bodyMedium),
            if (sum.fallOfWickets.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                'Fall of wickets: ${sum.fallOfWickets.join(', ')}',
                style: t.textTheme.bodySmall,
              ),
            ],
            const Divider(),
            Row(
              children: [
                Expanded(child: Text('Bowler', style: t.textTheme.labelMedium)),
                h('O'),
                h('R'),
                h('W'),
                h('Econ', w: 50),
              ],
            ),
            for (final e in sum.bowling.entries)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        e.key,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    v(e.value.overs),
                    v('${e.value.runs}'),
                    v('${e.value.wickets}', bold: true),
                    v(e.value.economy.toStringAsFixed(1), w: 50),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Wagon wheel for a match: pick a team, then the whole team or one player.
class _MatchWheel extends StatefulWidget {
  final CricketMatch match;
  final List<Ball> balls;
  const _MatchWheel({required this.match, required this.balls});
  @override
  State<_MatchWheel> createState() => _MatchWheelState();
}

class _MatchWheelState extends State<_MatchWheel> {
  int _inn = 1;

  @override
  Widget build(BuildContext context) {
    final m = widget.match;
    final inningsBalls = widget.balls.where((b) => b.innings == _inn).toList();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SegmentedButton<int>(
          segments: [
            for (var i = 1; i <= m.currentInnings; i++)
              ButtonSegment(value: i, label: Text(m.battingTeam(i))),
          ],
          selected: {_inn.clamp(1, m.currentInnings)},
          onSelectionChanged: (s) => setState(() => _inn = s.first),
        ),
        const SizedBox(height: 12),
        WheelPanel(
          key: ValueKey('wheel$_inn'),
          balls: inningsBalls,
          teamLabel: m.battingTeam(_inn),
        ),
      ],
    );
  }
}

/// Wheel with a "Whole team / single player" chooser, run-type, bowler and
/// innings filters, a legend and per-zone totals.
/// Pass [lockedPlayer] to show one player only (used on the player profile).
class WheelPanel extends StatefulWidget {
  final List<Ball> balls;
  final String teamLabel;
  final String? lockedPlayer;
  const WheelPanel({
    super.key,
    required this.balls,
    this.teamLabel = 'Whole team',
    this.lockedPlayer,
  });
  @override
  State<WheelPanel> createState() => _WheelPanelState();
}

class _WheelPanelState extends State<WheelPanel> {
  String? _player; // null = whole team
  String? _bowler; // null = all bowlers
  int _innings = 0; // 0 = both
  bool _show13 = true, _show4 = true, _show6 = true;

  bool _runsAllowed(int r) => r == 4 ? _show4 : (r >= 6 ? _show6 : _show13);

  @override
  Widget build(BuildContext context) {
    final locked = widget.lockedPlayer;
    final withShots = widget.balls
        .where((b) => b.hasShot && b.runs > 0)
        .toList();
    final players = withShots.map((b) => b.striker).toSet().toList()..sort();
    final bowlers = withShots.map((b) => b.bowler).toSet().toList()..sort();
    final inningsSeen = withShots.map((b) => b.innings).toSet().toList()
      ..sort();
    if (_player != null && !players.contains(_player)) _player = null;
    if (_bowler != null && !bowlers.contains(_bowler)) _bowler = null;
    if (_innings != 0 && !inningsSeen.contains(_innings)) _innings = 0;

    final who = locked ?? _player;
    final shown = withShots
        .where((b) => who == null || b.striker == who)
        .where((b) => _bowler == null || b.bowler == _bowler)
        .where((b) => _innings == 0 || b.innings == _innings)
        .where((b) => _runsAllowed(b.runs))
        .toList();
    final runs = shown.fold<int>(0, (a, b) => a + b.runs);
    final fours = shown.where((b) => b.runs == 4).length;
    final sixes = shown.where((b) => b.runs >= 6).length;
    final left = leftFrame(shown);
    final totals = zoneTotals(shown, left);
    final zones =
        [for (var i = 0; i < 8; i++) i]
            .where((i) => totals[i].runs > 0)
            .toList()
          ..sort((a, b) => totals[b].runs.compareTo(totals[a].runs));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (locked == null)
          DropdownButtonFormField<String?>(
            initialValue: _player,
            decoration: const InputDecoration(labelText: 'Show'),
            items: [
              DropdownMenuItem<String?>(
                value: null,
                child: Text('Whole team (${widget.teamLabel})'),
              ),
              for (final p in players)
                DropdownMenuItem<String?>(value: p, child: Text(p)),
            ],
            onChanged: (v) => setState(() => _player = v),
          ),
        if (bowlers.length > 1) ...[
          const SizedBox(height: 12),
          DropdownButtonFormField<String?>(
            initialValue: _bowler,
            decoration: const InputDecoration(labelText: 'Against bowler'),
            items: [
              const DropdownMenuItem<String?>(
                value: null,
                child: Text('All bowlers'),
              ),
              for (final b in bowlers)
                DropdownMenuItem<String?>(value: b, child: Text(b)),
            ],
            onChanged: (v) => setState(() => _bowler = v),
          ),
        ],
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            FilterChip(
              label: const Text('1-3 runs'),
              selected: _show13,
              onSelected: (v) => setState(() => _show13 = v),
            ),
            FilterChip(
              label: const Text('Fours'),
              selected: _show4,
              onSelected: (v) => setState(() => _show4 = v),
            ),
            FilterChip(
              label: const Text('Sixes'),
              selected: _show6,
              onSelected: (v) => setState(() => _show6 = v),
            ),
            if (inningsSeen.length > 1) ...[
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('Both innings'),
                selected: _innings == 0,
                onSelected: (_) => setState(() => _innings = 0),
              ),
              for (final i in inningsSeen)
                ChoiceChip(
                  label: Text(i == 1 ? '1st innings' : '2nd innings'),
                  selected: _innings == i,
                  onSelected: (_) => setState(() => _innings = i),
                ),
            ],
          ],
        ),
        const SizedBox(height: 12),
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: WagonWheel(balls: shown),
          ),
        ),
        const SizedBox(height: 8),
        const WheelLegend(),
        const SizedBox(height: 4),
        Center(
          child: Text(
            shown.isEmpty
                ? ''
                : left
                ? 'Left-hand batter: off side is on the left'
                : (shown.any((b) => b.lefty)
                      ? 'Left-handers are mirrored so the off side is always on the right'
                      : 'Off side is on the right'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        const SizedBox(height: 8),
        Center(
          child: Text(
            shown.isEmpty
                ? 'No shot directions to show.\nTurn on "Mark shot direction" while scoring, or relax the filters.'
                : '${shown.length} scoring shots  •  $runs runs  •  $fours fours  •  $sixes sixes',
            textAlign: TextAlign.center,
          ),
        ),
        if (zones.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text('Runs by zone', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final i in zones)
                Chip(
                  visualDensity: VisualDensity.compact,
                  label: Text(
                    '${zoneNames[i]}  ${totals[i].runs} (${totals[i].shots})',
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}
