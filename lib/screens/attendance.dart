import 'package:flutter/material.dart';

import '../core/attendance.dart';
import '../core/models.dart';
import '../core/repo.dart';
import '../core/ui.dart';
import 'attendance_history.dart';

class AttendanceTab extends StatelessWidget {
  const AttendanceTab({super.key});

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 2,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Attendance'),
        bottom: const TabBar(
          tabs: [
            Tab(text: 'Mark'),
            Tab(text: 'Monthly report'),
          ],
        ),
      ),
      body: const TabBarView(children: [_Mark(), _Report()]),
    ),
  );
}

class _Mark extends StatefulWidget {
  const _Mark();
  @override
  State<_Mark> createState() => _MarkState();
}

class _MarkState extends State<_Mark> {
  DateTime _day = DateTime.now();
  String _batchId = '';
  late final Stream<List<Batch>> _batches = Repo.i.batches();
  late final Stream<List<Student>> _students = Repo.i.students();

  @override
  Widget build(BuildContext context) => Live<List<Batch>>(
    stream: _batches,
    builder: (c, batches) {
      if (batches.isEmpty) {
        return const EmptyState(
          'Create a batch first (Home > menu > Batches).',
        );
      }
      if (!batches.any((b) => b.id == _batchId)) _batchId = batches.first.id;
      return Live<List<Student>>(
        stream: _students,
        builder: (c, all) {
          final list = all
              .where((s) => s.active && s.batchId == _batchId)
              .toList();
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.chevron_left),
                      onPressed: () => setState(
                        () => _day = _day.subtract(const Duration(days: 1)),
                      ),
                    ),
                    Expanded(
                      child: TextButton(
                        onPressed: () async {
                          final d = await showDatePicker(
                            context: context,
                            initialDate: _day,
                            firstDate: DateTime(2020),
                            lastDate: DateTime.now().add(
                              const Duration(days: 1),
                            ),
                          );
                          if (d != null) setState(() => _day = d);
                        },
                        child: Text(
                          fmtDate(_day),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.chevron_right),
                      onPressed: () => setState(
                        () => _day = _day.add(const Duration(days: 1)),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: DropdownButtonFormField<String>(
                  initialValue: _batchId,
                  decoration: const InputDecoration(labelText: 'Batch'),
                  items: [
                    for (final b in batches)
                      DropdownMenuItem(value: b.id, child: Text(b.name)),
                  ],
                  onChanged: (v) => setState(() => _batchId = v!),
                ),
              ),
              Expanded(
                child: list.isEmpty
                    ? const EmptyState('No students in this batch.')
                    : Live<Map<String, String>>(
                        key: ValueKey('$_batchId${dayKey(_day)}'),
                        stream: Repo.i.attendance(_day, _batchId),
                        builder: (c, rec) => _sheet(list, rec),
                      ),
              ),
            ],
          );
        },
      );
    },
  );

  Widget _sheet(List<Student> list, Map<String, String> rec) {
    final present = list.where((s) => rec[s.id] == 'P').length;
    final absent = list.where((s) => rec[s.id] == 'A').length;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Present $present  •  Absent $absent  •  Total ${list.length}',
                ),
              ),
              TextButton(
                onPressed: () async {
                  for (final s in list.where((s) => rec[s.id] == null)) {
                    await Repo.i.setAttendance(_day, _batchId, s.id, 'P');
                  }
                },
                child: const Text('Mark rest present'),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: list.length,
            itemBuilder: (c, i) {
              final s = list[i];
              final cur = rec[s.id];
              return Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          s.name,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      SegmentedButton<String>(
                        showSelectedIcon: false,
                        emptySelectionAllowed: true,
                        segments: const [
                          ButtonSegment(value: 'P', label: Text('P')),
                          ButtonSegment(value: 'L', label: Text('L')),
                          ButtonSegment(value: 'A', label: Text('A')),
                        ],
                        selected: cur == null ? {} : {cur},
                        onSelectionChanged: (v) => Repo.i.setAttendance(
                          _day,
                          _batchId,
                          s.id,
                          v.isEmpty ? null : v.first,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const Padding(
          padding: EdgeInsets.all(8),
          child: Text(
            'P = Present, L = Late, A = Absent',
            style: TextStyle(fontSize: 12),
          ),
        ),
      ],
    );
  }
}

class _Report extends StatefulWidget {
  const _Report();
  @override
  State<_Report> createState() => _ReportState();
}

class _ReportState extends State<_Report> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  String _batch = '';
  bool _lowestFirst = false;
  late final Stream<List<Student>> _students = Repo.i.students();
  late final Stream<List<Batch>> _batches = Repo.i.batches();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Row(
            children: [
              IconButton(
                tooltip: 'Previous month',
                icon: const Icon(Icons.chevron_left),
                onPressed: () => setState(
                  () => _month = DateTime(_month.year, _month.month - 1),
                ),
              ),
              Expanded(
                child: TextButton(
                  onPressed: () async {
                    // Jump to any past month.
                    final d = await showDatePicker(
                      context: context,
                      initialDate: _month,
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now(),
                      helpText: 'Pick any day in the month',
                    );
                    if (d != null) {
                      setState(() => _month = DateTime(d.year, d.month));
                    }
                  },
                  child: Text(
                    fmtMonth(monthKey(_month)),
                    style: t.textTheme.titleMedium,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Next month',
                icon: const Icon(Icons.chevron_right),
                onPressed: () => setState(
                  () => _month = DateTime(_month.year, _month.month + 1),
                ),
              ),
            ],
          ),
        ),
        Live<List<Batch>>(
          stream: _batches,
          builder: (c, batches) => Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
            child: Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: batches.any((b) => b.id == _batch)
                        ? _batch
                        : '',
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Batch',
                      isDense: true,
                    ),
                    items: [
                      const DropdownMenuItem(
                        value: '',
                        child: Text('All batches'),
                      ),
                      for (final b in batches)
                        DropdownMenuItem(value: b.id, child: Text(b.name)),
                    ],
                    onChanged: (v) => setState(() => _batch = v ?? ''),
                  ),
                ),
                const SizedBox(width: 8),
                FilterChip(
                  label: const Text('Lowest first'),
                  selected: _lowestFirst,
                  onSelected: (v) => setState(() => _lowestFirst = v),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: Live<List<Student>>(
            stream: _students,
            builder: (c, all) => Live<List<Map<String, dynamic>>>(
              key: ValueKey(monthKey(_month)),
              stream: Repo.i.attendanceMonth(_month),
              builder: (c, sheets) {
                final students = all
                    .where(
                      (s) =>
                          s.active && (_batch.isEmpty || s.batchId == _batch),
                    )
                    .toList();
                final rows = [
                  for (final s in students)
                    (s, statOf(attendanceDays(sheets, s.id))),
                ];
                if (_lowestFirst) {
                  // Students with no sessions go last; the rest by lowest attendance.
                  rows.sort((a, b) {
                    if (a.$2.held == 0 && b.$2.held == 0) return 0;
                    if (a.$2.held == 0) return 1;
                    if (b.$2.held == 0) return -1;
                    return a.$2.percent.compareTo(b.$2.percent);
                  });
                }
                final marked = rows.where((r) => r.$2.held > 0).toList();
                if (marked.isEmpty) {
                  return const EmptyState(
                    'No attendance marked for this month.',
                  );
                }
                final avg =
                    marked.fold<double>(0, (a, r) => a + r.$2.percent) /
                    marked.length;
                final low = marked.where((r) => r.$2.percent < 75).length;
                return ListView(
                  padding: const EdgeInsets.only(top: 8, bottom: 24),
                  children: [
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Average attendance',
                                    style: t.textTheme.labelLarge,
                                  ),
                                  Text(
                                    '${avg.toStringAsFixed(0)}%',
                                    style: t.textTheme.headlineSmall?.copyWith(
                                      color: percentColor(avg, t.colorScheme),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              low == 0
                                  ? 'Everyone is above 75%'
                                  : '$low below 75%',
                              style: TextStyle(
                                color: low == 0
                                    ? Colors.green.shade700
                                    : t.colorScheme.error,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    for (final (s, st) in rows)
                      Card(
                        child: ListTile(
                          title: Text(s.name),
                          subtitle: st.held == 0
                              ? const Text('No sessions marked')
                              : Text(
                                  'Present ${st.present}  •  Late ${st.late}  •  Absent ${st.absent}  (${st.held} sessions)',
                                ),
                          trailing: Text(
                            st.held == 0
                                ? '-'
                                : '${st.percent.toStringAsFixed(0)}%',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: st.held == 0
                                  ? null
                                  : percentColor(st.percent, t.colorScheme),
                            ),
                          ),
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  StudentAttendanceScreen(student: s),
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}
