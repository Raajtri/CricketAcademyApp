import 'package:flutter/material.dart';

import '../core/models.dart';
import '../core/repo.dart';
import '../core/scoring.dart';
import '../core/ui.dart';
import 'attendance_history.dart';
import 'cricket.dart';

/// What a student sees after logging in: their own summary, fees and purchases,
/// attendance, and the cricket section (they can score matches too).
class StudentShell extends StatefulWidget {
  final AppUser me;
  const StudentShell({super.key, required this.me});
  @override
  State<StudentShell> createState() => _StudentShellState();
}

class _StudentShellState extends State<StudentShell> {
  int _i = 0;
  late final Stream<Student?> _student = Repo.i.student(widget.me.studentId);

  @override
  Widget build(BuildContext context) {
    if (widget.me.studentId.isEmpty) return const _NotLinked();
    return Live<Student?>(
      stream: _student,
      builder: (c, s) {
        if (s == null) return const _NotLinked();
        final tabs = <(String, IconData, Widget)>[
          ('Me', Icons.person_outline, _MeTab(student: s)),
          ('Fees', Icons.payments_outlined, _FeesTab(student: s)),
          ('Attendance', Icons.fact_check_outlined, _AttendanceTab(student: s)),
          ('Cricket', Icons.sports_cricket, CricketTab(me: widget.me)),
        ];
        return Scaffold(
          body: IndexedStack(index: _i, children: [for (final t in tabs) t.$3]),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _i,
            onDestinationSelected: (v) => setState(() => _i = v),
            destinations: [
              for (final t in tabs)
                NavigationDestination(icon: Icon(t.$2), label: t.$1),
            ],
          ),
        );
      },
    );
  }
}

class _NotLinked extends StatelessWidget {
  const _NotLinked();
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Cricket Academy')),
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Your login is not linked to a student record yet.\nPlease ask the academy.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: Repo.i.signOut,
              child: const Text('Sign out'),
            ),
          ],
        ),
      ),
    ),
  );
}

// ------------------------------------------------------------------ Me
class _MeTab extends StatefulWidget {
  final Student student;
  const _MeTab({required this.student});
  @override
  State<_MeTab> createState() => _MeTabState();
}

class _MeTabState extends State<_MeTab> {
  late final Stream<List<FeePayment>> _pays = Repo.i.paymentsFor(
    widget.student.id,
  );
  late final Stream<List<Sale>> _sales = Repo.i.salesFor(widget.student.id);
  late final Stream<List<Batch>> _batches = Repo.i.batches();
  late final Stream<Map<String, List<Ball>>> _balls = Repo.i.allBallsGrouped();

  @override
  Widget build(BuildContext context) {
    final s = widget.student;
    final t = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cricket Academy'),
        actions: [
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout),
            onPressed: Repo.i.signOut,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Text('Hello, ${s.name}', style: t.textTheme.headlineSmall),
          const SizedBox(height: 8),
          Live<List<Batch>>(
            stream: _batches,
            builder: (c, batches) {
              final b = batches.where((x) => x.id == s.batchId).firstOrNull;
              return Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.schedule),
                      title: Text(b?.name ?? 'No batch yet'),
                      subtitle: Text(
                        [
                          if (b != null && b.timing.isNotEmpty) b.timing,
                          if (b != null && b.coach.isNotEmpty)
                            'Coach ${b.coach}',
                        ].join('  •  '),
                      ),
                    ),
                    if (s.team.isNotEmpty)
                      ListTile(
                        leading: const Icon(Icons.shield_outlined),
                        title: Text('Team ${s.team}'),
                      ),
                    ListTile(
                      leading: const Icon(Icons.event),
                      title: Text('Joined ${fmtDate(s.joinDate)}'),
                    ),
                  ],
                ),
              );
            },
          ),
          Live<List<FeePayment>>(
            stream: _pays,
            builder: (c, pays) {
              final f = feeSummary(s, pays);
              return Card(
                color: f.due > 0
                    ? t.colorScheme.errorContainer
                    : t.colorScheme.primaryContainer,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        f.due > 0 ? 'Fee due' : 'Fees are up to date',
                        style: t.textTheme.titleSmall,
                      ),
                      if (f.due > 0)
                        Text(rupees(f.due), style: t.textTheme.displaySmall),
                      if (f.unpaidMonths.isNotEmpty)
                        Text(
                          'Unpaid: ${f.unpaidMonths.map(fmtMonth).join(', ')}',
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
          Live<List<Sale>>(
            stream: _sales,
            builder: (c, sales) {
              final bal = sales.fold<double>(0, (a, x) => a + x.balance);
              if (sales.isEmpty) return const SizedBox.shrink();
              return Card(
                child: ListTile(
                  leading: const Icon(Icons.shopping_bag_outlined),
                  title: Text(
                    'Kit & clothes: ${sales.length} item${sales.length == 1 ? '' : 's'} bought',
                  ),
                  subtitle: Text(
                    bal > 0 ? 'Balance to pay ${rupees(bal)}' : 'All paid',
                  ),
                ),
              );
            },
          ),
          Live<Map<String, List<Ball>>>(
            stream: _balls,
            builder: (c, grouped) {
              final stats = CareerStats.compute(grouped);
              final mine = stats[s.name];
              if (mine == null) {
                return const Card(
                  child: ListTile(
                    leading: Icon(Icons.sports_cricket),
                    title: Text('My cricket stats'),
                    subtitle: Text(
                      'They appear after you play a scored match (use your name as the player name).',
                    ),
                  ),
                );
              }
              final balls = grouped.values
                  .expand((e) => e)
                  .where((b) => b.striker == s.name)
                  .toList();
              return Card(
                child: ListTile(
                  leading: const Icon(Icons.sports_cricket),
                  title: const Text('My cricket stats'),
                  subtitle: Text(
                    '${mine.runs} runs  •  Avg ${mine.average.toStringAsFixed(1)}  •  SR ${mine.strikeRate.toStringAsFixed(0)}  '
                    '•  ${mine.wickets} wkts\nTap for my wagon wheel',
                  ),
                  isThreeLine: true,
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => PlayerProfile(
                        name: s.name,
                        stats: mine,
                        balls: balls,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- Fees
class _FeesTab extends StatefulWidget {
  final Student student;
  const _FeesTab({required this.student});
  @override
  State<_FeesTab> createState() => _FeesTabState();
}

class _FeesTabState extends State<_FeesTab> {
  late final Stream<List<FeePayment>> _pays = Repo.i.paymentsFor(
    widget.student.id,
  );
  late final Stream<List<Sale>> _sales = Repo.i.salesFor(widget.student.id);

  @override
  Widget build(BuildContext context) {
    final s = widget.student;
    final t = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('My fees')),
      body: Live<List<FeePayment>>(
        stream: _pays,
        builder: (c, pays) {
          final f = feeSummary(s, pays);
          // Month by month from joining to now, newest first.
          final months = <String>[];
          var m = DateTime(s.joinDate.year, s.joinDate.month);
          final now = DateTime.now();
          while (!m.isAfter(DateTime(now.year, now.month))) {
            months.add(monthKey(m));
            m = DateTime(m.year, m.month + 1);
          }
          double paidFor(String k) =>
              pays.where((p) => p.month == k).fold(0.0, (a, p) => a + p.amount);
          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Monthly fee ${rupees(s.monthlyFee)}',
                        style: t.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Billed ${rupees(f.billed)}  •  Paid ${rupees(f.paid)}',
                      ),
                      Text(
                        f.due > 0 ? 'Due ${rupees(f.due)}' : 'Nothing due',
                        style: t.textTheme.titleLarge?.copyWith(
                          color: f.due > 0
                              ? t.colorScheme.error
                              : Colors.green.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 12, 8, 4),
                child: Text('Month by month', style: t.textTheme.titleSmall),
              ),
              for (final k in months.reversed)
                Builder(
                  builder: (_) {
                    final paid = paidFor(k);
                    final full = paid + 0.001 >= s.monthlyFee;
                    return Card(
                      child: ListTile(
                        dense: true,
                        title: Text(fmtMonth(k)),
                        subtitle: Text(
                          'Paid ${rupees(paid)} of ${rupees(s.monthlyFee)}',
                        ),
                        trailing: Chip(
                          visualDensity: VisualDensity.compact,
                          label: Text(
                            full ? 'Paid' : (paid > 0 ? 'Part paid' : 'Unpaid'),
                          ),
                          backgroundColor: full
                              ? Colors.green.shade100
                              : t.colorScheme.errorContainer,
                        ),
                      ),
                    );
                  },
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 16, 8, 4),
                child: Text('Payments made', style: t.textTheme.titleSmall),
              ),
              if (pays.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(8),
                  child: Text('No payments recorded yet.'),
                ),
              for (final p in pays)
                Card(
                  child: ListTile(
                    dense: true,
                    title: Text('${rupees(p.amount)} for ${fmtMonth(p.month)}'),
                    subtitle: Text('${fmtDate(p.paidOn)}  •  ${p.mode}'),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 16, 8, 4),
                child: Text('Kit & clothes', style: t.textTheme.titleSmall),
              ),
              Live<List<Sale>>(
                stream: _sales,
                builder: (c, sales) {
                  if (sales.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.all(8),
                      child: Text('Nothing bought yet.'),
                    );
                  }
                  return Column(
                    children: [
                      for (final x in sales)
                        Card(
                          child: ListTile(
                            dense: true,
                            title: Text('${x.itemLabel} × ${x.qty}'),
                            subtitle: Text(
                              '${fmtDate(x.date)}  •  Total ${rupees(x.total)}  •  Paid ${rupees(x.paid)}',
                            ),
                            trailing: x.balance > 0
                                ? Text(
                                    'Due ${rupees(x.balance)}',
                                    style: TextStyle(
                                      color: t.colorScheme.error,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  )
                                : const Icon(
                                    Icons.check_circle,
                                    color: Colors.green,
                                  ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------- Attendance
class _AttendanceTab extends StatelessWidget {
  final Student student;
  const _AttendanceTab({required this.student});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('My attendance')),
    body: AttendanceHistory(student: student),
  );
}
