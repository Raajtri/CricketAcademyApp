import 'package:flutter/material.dart';

import '../core/attendance.dart';
import '../core/models.dart';
import '../core/repo.dart';
import '../core/ui.dart';

/// A student's attendance across every month: overall numbers, a month picker,
/// a calendar for the chosen month and a month-by-month table. Used by the
/// student's own tab and by staff looking at a student.
class StudentAttendanceScreen extends StatelessWidget {
  final Student student;
  const StudentAttendanceScreen({super.key, required this.student});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text('${student.name}: attendance')),
    body: AttendanceHistory(student: student),
  );
}

Color statusColor(String s, ColorScheme cs) => s == 'P'
    ? Colors.green.shade100
    : (s == 'L' ? Colors.amber.shade200 : cs.errorContainer);

String statusName(String s) =>
    {'P': 'Present', 'L': 'Late', 'A': 'Absent'}[s] ?? s;

Color percentColor(double p, ColorScheme cs) => p >= 90
    ? Colors.green.shade700
    : (p >= 75 ? Colors.orange.shade800 : cs.error);

class AttendanceHistory extends StatefulWidget {
  final Student student;
  const AttendanceHistory({super.key, required this.student});
  @override
  State<AttendanceHistory> createState() => _AttendanceHistoryState();
}

class _AttendanceHistoryState extends State<AttendanceHistory> {
  late final Stream<List<Map<String, dynamic>>> _sheets = Repo.i
      .attendanceForBatchAll(widget.student.batchId);
  String? _month; // yyyy-MM, null = latest

  @override
  Widget build(BuildContext context) {
    final s = widget.student;
    if (s.batchId.isEmpty) {
      return const EmptyState('Not in a batch yet, so there is no attendance.');
    }
    final t = Theme.of(context);
    return Live<List<Map<String, dynamic>>>(
      stream: _sheets,
      builder: (c, sheets) {
        final days = attendanceDays(sheets, s.id);
        if (days.isEmpty) {
          return const EmptyState('No attendance has been marked yet.');
        }
        final stats = monthlyStats(days);
        final months = stats.keys.toList()
          ..sort((a, b) => b.compareTo(a)); // newest first
        final nowKey = monthKey(DateTime.now());
        final sel = (_month != null && stats.containsKey(_month))
            ? _month!
            : (stats.containsKey(nowKey) ? nowKey : months.first);
        final overall = statOf(days);
        final monthDays = days.where((d) => monthKey(d.date) == sel).toList();

        return ListView(
          padding: const EdgeInsets.all(12),
          children: [
            // All-time summary
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Overall', style: t.textTheme.labelLarge),
                    Text(
                      '${overall.percent.toStringAsFixed(0)}% attendance',
                      style: t.textTheme.headlineSmall?.copyWith(
                        color: percentColor(overall.percent, t.colorScheme),
                      ),
                    ),
                    const SizedBox(height: 4),
                    _counts(overall),
                  ],
                ),
              ),
            ),
            // Month picker
            SizedBox(
              height: 48,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final k in months)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 6,
                      ),
                      child: ChoiceChip(
                        label: Text(fmtMonth(k)),
                        selected: k == sel,
                        onSelected: (_) => setState(() => _month = k),
                      ),
                    ),
                ],
              ),
            ),
            // Chosen month
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            fmtMonth(sel),
                            style: t.textTheme.titleMedium,
                          ),
                        ),
                        Text(
                          '${stats[sel]!.percent.toStringAsFixed(0)}%',
                          style: t.textTheme.titleLarge?.copyWith(
                            color: percentColor(
                              stats[sel]!.percent,
                              t.colorScheme,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    _counts(stats[sel]!),
                    const SizedBox(height: 12),
                    _Calendar(month: sel, days: monthDays),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 12, 8, 4),
              child: Text('Month by month', style: t.textTheme.titleSmall),
            ),
            for (final k in months)
              Card(
                color: k == sel ? t.colorScheme.primaryContainer : null,
                child: ListTile(
                  dense: true,
                  title: Text(fmtMonth(k)),
                  subtitle: Text(
                    'Present ${stats[k]!.present}  •  Late ${stats[k]!.late}  •  Absent ${stats[k]!.absent}'
                    '  (${stats[k]!.held} sessions)',
                  ),
                  trailing: Text(
                    '${stats[k]!.percent.toStringAsFixed(0)}%',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: percentColor(stats[k]!.percent, t.colorScheme),
                    ),
                  ),
                  onTap: () => setState(() => _month = k),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _counts(MonthStat st) => Wrap(
    spacing: 8,
    runSpacing: 4,
    children: [
      _pill('Present ${st.present}', Colors.green.shade100),
      _pill('Late ${st.late}', Colors.amber.shade200),
      _pill(
        'Absent ${st.absent}',
        Theme.of(context).colorScheme.errorContainer,
      ),
    ],
  );

  Widget _pill(String text, Color bg) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text(
      text,
      style: const TextStyle(
        fontWeight: FontWeight.w600,
        color: Colors.black87,
      ),
    ),
  );
}

/// Month grid, Monday first. Marked days are coloured and carry their letter, so
/// the colour is never the only signal.
class _Calendar extends StatelessWidget {
  final String month; // yyyy-MM
  final List<AttDay> days;
  const _Calendar({required this.month, required this.days});

  @override
  Widget build(BuildContext context) {
    final p = month.split('-');
    final first = DateTime(int.parse(p[0]), int.parse(p[1]));
    final daysInMonth = DateTime(first.year, first.month + 1, 0).day;
    final offset = first.weekday - 1; // Monday = 0
    final byDay = {for (final d in days) d.date.day: d.status};
    final cs = Theme.of(context).colorScheme;
    const heads = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

    return Column(
      children: [
        Row(
          children: [
            for (final h in heads)
              Expanded(
                child: Center(
                  child: Text(h, style: Theme.of(context).textTheme.labelSmall),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        GridView.count(
          crossAxisCount: 7,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 4,
          crossAxisSpacing: 4,
          childAspectRatio: 1,
          children: [
            for (var i = 0; i < offset; i++) const SizedBox.shrink(),
            for (var d = 1; d <= daysInMonth; d++)
              Container(
                decoration: BoxDecoration(
                  color: byDay[d] == null
                      ? cs.surfaceContainerHighest.withValues(alpha: 0.5)
                      : statusColor(byDay[d]!, cs),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '$d',
                      style: TextStyle(
                        fontSize: 12,
                        color: byDay[d] == null ? cs.outline : Colors.black87,
                      ),
                    ),
                    if (byDay[d] != null)
                      Text(
                        byDay[d]!,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'P = Present   L = Late   A = Absent   Grey = no session',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}
