import 'package:flutter/material.dart';

import '../core/models.dart';
import '../core/repo.dart';
import '../core/scoring.dart';
import '../core/ui.dart';
import 'match_detail.dart';
import 'score.dart';

class CricketTab extends StatelessWidget {
  final AppUser me;
  const CricketTab({super.key, required this.me});

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 2,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Cricket'),
        bottom: const TabBar(
          tabs: [
            Tab(text: 'Matches'),
            Tab(text: 'Players'),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => NewMatchScreen(canPickStudents: !me.isStudent),
          ),
        ),
        icon: const Icon(Icons.add),
        label: const Text('New match'),
      ),
      body: TabBarView(
        children: [
          _MatchList(me: me),
          const _PlayerStats(),
        ],
      ),
    ),
  );
}

class _MatchList extends StatelessWidget {
  final AppUser me;
  const _MatchList({required this.me});

  @override
  Widget build(BuildContext context) => Live<List<CricketMatch>>(
    stream: Repo.i.matches(),
    builder: (c, matches) {
      if (matches.isEmpty) {
        return const EmptyState(
          'No matches yet.\nTap "New match" to start scoring.',
        );
      }
      return ListView.builder(
        padding: const EdgeInsets.only(bottom: 90, top: 8),
        itemCount: matches.length,
        itemBuilder: (c, i) {
          final m = matches[i];
          return Card(
            child: ListTile(
              leading: Icon(
                m.isLive ? Icons.sensors : Icons.emoji_events_outlined,
                color: m.isLive ? Colors.red : null,
              ),
              title: Text('${m.teamA} vs ${m.teamB}'),
              subtitle: Text(
                '${fmtDate(m.date)}  •  ${m.overs} overs\n'
                '${m.isLive ? 'LIVE (innings ${m.currentInnings})' : m.result}',
              ),
              isThreeLine: true,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => m.isLive
                      ? ScoreScreen(matchId: m.id)
                      : MatchDetailScreen(matchId: m.id),
                ),
              ),
              trailing: me.isAdmin
                  ? IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () async {
                        if (await confirm(
                          context,
                          'Delete this match?',
                          'All its scoring will be lost.',
                        )) {
                          await Repo.i.deleteMatch(m.id);
                        }
                      },
                    )
                  : null,
            ),
          );
        },
      );
    },
  );
}

class NewMatchScreen extends StatefulWidget {
  /// Students can't read other students' records, so only staff get the picker.
  final bool canPickStudents;
  const NewMatchScreen({super.key, this.canPickStudents = true});
  @override
  State<NewMatchScreen> createState() => _NewMatchScreenState();
}

class _NewMatchScreenState extends State<NewMatchScreen> {
  final _form = GlobalKey<FormState>();
  final _a = TextEditingController(text: 'Team A');
  final _b = TextEditingController(text: 'Team B');
  final _overs = TextEditingController(text: '20');
  final _pa = TextEditingController();
  final _pb = TextEditingController();
  String _battingFirst = 'A';
  bool _busy = false;

  List<String> _names(TextEditingController c) => c.text
      .split(RegExp(r'[\n,]'))
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toSet()
      .toList();

  Future<void> _pickStudents(
    TextEditingController target,
    TextEditingController teamName,
  ) async {
    final students = (await Repo.i.students().first)
        .where((s) => s.active)
        .toList();
    if (!mounted) return;
    final chosen = <String>{..._names(target)};
    final teams =
        students.map((s) => s.team).where((t) => t.isNotEmpty).toSet().toList()
          ..sort();
    String? addedTeam;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: const Text('Pick players'),
          content: SizedBox(
            width: 320,
            height: 440,
            child: students.isEmpty
                ? const Text('No students added yet.')
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (teams.isNotEmpty) ...[
                        const Text('Add a whole team'),
                        Wrap(
                          spacing: 8,
                          children: [
                            for (final t in teams)
                              ActionChip(
                                avatar: const Icon(
                                  Icons.shield_outlined,
                                  size: 16,
                                ),
                                label: Text(t),
                                onPressed: () => set(() {
                                  chosen.addAll(
                                    students
                                        .where((s) => s.team == t)
                                        .map((s) => s.name),
                                  );
                                  addedTeam = t;
                                }),
                              ),
                          ],
                        ),
                        const Divider(),
                      ],
                      Expanded(
                        child: ListView(
                          children: [
                            for (final s in students)
                              CheckboxListTile(
                                dense: true,
                                title: Text(s.name),
                                subtitle: s.team.isEmpty
                                    ? null
                                    : Text('Team ${s.team}'),
                                value: chosen.contains(s.name),
                                onChanged: (v) => set(
                                  () => v!
                                      ? chosen.add(s.name)
                                      : chosen.remove(s.name),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    );
    if (ok == true) {
      target.text = chosen.join('\n');
      // Use the real team name when the field still has its placeholder.
      if (addedTeam != null &&
          RegExp(r'^Team [AB]$').hasMatch(teamName.text.trim())) {
        setState(() => teamName.text = addedTeam!);
      }
    }
  }

  Future<void> _start() async {
    if (!_form.currentState!.validate()) return;
    final pa = _names(_pa), pb = _names(_pb);
    if (pa.length < 2 || pb.length < 2) {
      toast(context, 'Each team needs at least 2 players');
      return;
    }
    setState(() => _busy = true);
    try {
      final id = await Repo.i.createMatch(
        teamA: _a.text.trim(),
        teamB: _b.text.trim(),
        playersA: pa,
        playersB: pb,
        overs: int.tryParse(_overs.text) ?? 20,
        battingFirst: _battingFirst,
      );
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => ScoreScreen(matchId: id)),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        toast(context, '$e');
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('New match')),
    body: Form(
      key: _form,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Field(_a, 'Team A name', required: true),
          Field(_b, 'Team B name', required: true),
          Field(
            _overs,
            'Overs per innings',
            type: TextInputType.number,
            required: true,
          ),
          const Text('Toss: who bats first?'),
          const SizedBox(height: 6),
          SegmentedButton<String>(
            segments: [
              ButtonSegment(
                value: 'A',
                label: Text(_a.text.isEmpty ? 'Team A' : _a.text),
              ),
              ButtonSegment(
                value: 'B',
                label: Text(_b.text.isEmpty ? 'Team B' : _b.text),
              ),
            ],
            selected: {_battingFirst},
            onSelectionChanged: (s) => setState(() => _battingFirst = s.first),
          ),
          const SizedBox(height: 16),
          _players('Team A players', _pa, _a),
          _players('Team B players', _pb, _b),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _busy ? null : _start,
            icon: const Icon(Icons.play_arrow),
            label: const Text('Start scoring'),
          ),
        ],
      ),
    ),
  );

  Widget _players(
    String label,
    TextEditingController c,
    TextEditingController teamName,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(label, style: Theme.of(context).textTheme.titleSmall),
            ),
            if (widget.canPickStudents)
              TextButton.icon(
                onPressed: () => _pickStudents(c, teamName),
                icon: const Icon(Icons.group_add_outlined),
                label: const Text('From students'),
              ),
          ],
        ),
        TextFormField(
          controller: c,
          minLines: 4,
          maxLines: 12,
          decoration: const InputDecoration(
            hintText: 'One name per line (or comma separated)',
          ),
        ),
      ],
    ),
  );
}

class _PlayerStats extends StatelessWidget {
  const _PlayerStats();

  @override
  Widget build(BuildContext context) => Live<Map<String, List<Ball>>>(
    stream: Repo.i.allBallsGrouped(),
    builder: (c, grouped) {
      final stats = CareerStats.compute(grouped);
      if (stats.isEmpty) {
        return const EmptyState(
          'Player stats appear after matches are scored.',
        );
      }
      final names = stats.keys.toList()
        ..sort((a, b) => stats[b]!.runs.compareTo(stats[a]!.runs));
      return ListView.builder(
        padding: const EdgeInsets.only(bottom: 90, top: 8),
        itemCount: names.length,
        itemBuilder: (c, i) {
          final n = names[i];
          final s = stats[n]!;
          return Card(
            child: ListTile(
              title: Text(n),
              subtitle: Text(
                '${s.runs} runs  •  Avg ${s.average.toStringAsFixed(1)}  •  SR ${s.strikeRate.toStringAsFixed(0)}  '
                '•  HS ${s.highScore}\n${s.wickets} wkts  •  Econ ${s.economy.toStringAsFixed(1)}',
              ),
              isThreeLine: true,
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                final all = grouped.values
                    .expand((e) => e)
                    .where((b) => b.striker == n)
                    .toList();
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        PlayerProfile(name: n, stats: s, balls: all),
                  ),
                );
              },
            ),
          );
        },
      );
    },
  );
}

/// Career numbers and the single-player wagon wheel across all matches.
class PlayerProfile extends StatelessWidget {
  final String name;
  final CareerStats stats;
  final List<Ball> balls;
  const PlayerProfile({
    super.key,
    required this.name,
    required this.stats,
    required this.balls,
  });

  @override
  Widget build(BuildContext context) {
    Widget tile(String k, String v) => Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            children: [
              Text(v, style: Theme.of(context).textTheme.titleLarge),
              Text(k, style: Theme.of(context).textTheme.labelSmall),
            ],
          ),
        ),
      ),
    );
    return Scaffold(
      appBar: AppBar(title: Text(name)),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Row(
            children: [
              tile('Innings', '${stats.innings}'),
              tile('Runs', '${stats.runs}'),
              tile('Avg', stats.average.toStringAsFixed(1)),
              tile('SR', stats.strikeRate.toStringAsFixed(0)),
            ],
          ),
          Row(
            children: [
              tile('HS', '${stats.highScore}'),
              tile('4s', '${stats.fours}'),
              tile('6s', '${stats.sixes}'),
              tile('Wkts', '${stats.wickets}'),
            ],
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              'Wagon wheel (all matches)',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          const SizedBox(height: 8),
          WheelPanel(balls: balls, lockedPlayer: name),
        ],
      ),
    );
  }
}
