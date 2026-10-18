import 'package:flutter/material.dart';

import '../core/models.dart';
import '../core/repo.dart';
import '../core/ui.dart';
import 'attendance.dart';
import 'batches.dart';
import 'cricket.dart';
import 'fees.dart';
import 'shop.dart';
import 'staff.dart';
import 'student_home.dart';
import 'students.dart';

class HomeShell extends StatefulWidget {
  final AppUser me;
  const HomeShell({super.key, required this.me});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _i = 0;

  @override
  Widget build(BuildContext context) {
    final me = widget.me;
    if (me.isStudent) return StudentShell(me: me);
    final tabs = <(String, IconData, Widget)>[
      ('Home', Icons.dashboard_outlined, _Dashboard(me: me)),
      ('Students', Icons.groups_outlined, StudentsTab(me: me)),
      ('Attendance', Icons.fact_check_outlined, const AttendanceTab()),
      if (me.isAdmin) ('Money', Icons.payments_outlined, const MoneyTab()),
      ('Cricket', Icons.sports_cricket, CricketTab(me: me)),
    ];
    final index = _i.clamp(0, tabs.length - 1);
    return Scaffold(
      body: IndexedStack(index: index, children: [for (final t in tabs) t.$3]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (v) => setState(() => _i = v),
        destinations: [
          for (final t in tabs)
            NavigationDestination(icon: Icon(t.$2), label: t.$1),
        ],
      ),
    );
  }
}

class MoneyTab extends StatelessWidget {
  const MoneyTab({super.key});
  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 2,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Fees & Shop'),
        bottom: const TabBar(
          tabs: [
            Tab(text: 'Fees'),
            Tab(text: 'Shop'),
          ],
        ),
      ),
      body: const TabBarView(children: [FeesView(), ShopView()]),
    ),
  );
}

class _Dashboard extends StatelessWidget {
  final AppUser me;
  const _Dashboard({required this.me});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Cricket Academy'),
      actions: [
        PopupMenuButton<String>(
          onSelected: (v) {
            if (v == 'batches') {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const BatchesScreen()),
              );
            } else if (v == 'staff') {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const StaffScreen()),
              );
            } else {
              Repo.i.signOut();
            }
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'batches', child: Text('Batches')),
            if (me.isAdmin)
              const PopupMenuItem(
                value: 'staff',
                child: Text('Coaches & staff'),
              ),
            const PopupMenuItem(value: 'out', child: Text('Sign out')),
          ],
        ),
      ],
    ),
    body: ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Text(
          'Hello, ${me.name}',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        Text(me.isAdmin ? 'Admin' : 'Coach'),
        const SizedBox(height: 12),
        Live<List<Student>>(
          stream: Repo.i.students(),
          builder: (c, students) {
            final active = students.where((s) => s.active).toList();
            return Column(
              children: [
                Row(
                  children: [
                    _stat(
                      c,
                      'Active students',
                      '${active.length}',
                      Icons.groups,
                    ),
                    Live<List<Batch>>(
                      stream: Repo.i.batches(),
                      builder: (c, b) =>
                          _stat(c, 'Batches', '${b.length}', Icons.schedule),
                    ),
                  ],
                ),
                if (me.isAdmin) _adminStats(active),
              ],
            );
          },
        ),
      ],
    ),
  );

  Widget _adminStats(List<Student> active) => Live<List<FeePayment>>(
    stream: Repo.i.payments(),
    builder: (c, pays) {
      var due = 0.0;
      var owing = 0;
      for (final s in active) {
        final d = feeSummary(s, pays).due;
        if (d > 0) {
          due += d;
          owing++;
        }
      }
      final now = DateTime.now();
      final monthCollected = pays
          .where(
            (p) => p.paidOn.year == now.year && p.paidOn.month == now.month,
          )
          .fold<double>(0, (a, p) => a + p.amount);
      return Column(
        children: [
          Row(
            children: [
              _stat(
                c,
                'Fees due',
                rupees(due),
                Icons.warning_amber,
                sub: '$owing students',
              ),
              _stat(
                c,
                'Collected this month',
                rupees(monthCollected),
                Icons.account_balance_wallet,
              ),
            ],
          ),
          Live<List<Sale>>(
            stream: Repo.i.sales(),
            builder: (c, sales) {
              final pending = sales.fold<double>(0, (a, s) => a + s.balance);
              return Live<List<Item>>(
                stream: Repo.i.items(),
                builder: (c, items) {
                  final low = items.where((i) => i.stock <= 2).length;
                  return Row(
                    children: [
                      _stat(
                        c,
                        'Shop dues',
                        rupees(pending),
                        Icons.shopping_bag_outlined,
                      ),
                      _stat(
                        c,
                        'Low stock items',
                        '$low',
                        Icons.inventory_2_outlined,
                      ),
                    ],
                  );
                },
              );
            },
          ),
        ],
      );
    },
  );

  Widget _stat(
    BuildContext c,
    String label,
    String value,
    IconData icon, {
    String? sub,
  }) => Expanded(
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: Theme.of(c).colorScheme.primary),
            const SizedBox(height: 8),
            Text(value, style: Theme.of(c).textTheme.titleLarge),
            Text(label, style: Theme.of(c).textTheme.bodySmall),
            if (sub != null) Text(sub, style: Theme.of(c).textTheme.bodySmall),
          ],
        ),
      ),
    ),
  );
}
