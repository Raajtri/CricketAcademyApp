/// One marked session for one student: 'P' present, 'L' late, 'A' absent.
class AttDay {
  final DateTime date;
  final String status;
  const AttDay(this.date, this.status);
}

class MonthStat {
  int present = 0, late = 0, absent = 0;
  int get held => present + late + absent;

  /// Late still counts as attended.
  int get attended => present + late;
  double get percent => held == 0 ? 0 : attended * 100 / held;
}

String _monthOf(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}';

/// A student's marked sessions, newest first, from attendance sheets
/// (each sheet has a 'date' like 2026-10-05 and a 'records' map of studentId -> status).
List<AttDay> attendanceDays(
  Iterable<Map<String, dynamic>> sheets,
  String studentId,
) {
  final out = <AttDay>[];
  for (final sh in sheets) {
    final status = ((sh['records'] as Map?) ?? const {})[studentId];
    final date = DateTime.tryParse('${sh['date'] ?? ''}');
    if (status == null || date == null) continue;
    out.add(AttDay(date, status.toString()));
  }
  out.sort((a, b) => b.date.compareTo(a.date));
  return out;
}

MonthStat statOf(Iterable<AttDay> days) {
  final s = MonthStat();
  for (final d in days) {
    if (d.status == 'P') {
      s.present++;
    } else if (d.status == 'L') {
      s.late++;
    } else if (d.status == 'A') {
      s.absent++;
    }
  }
  return s;
}

/// 'yyyy-MM' -> stats for that month.
Map<String, MonthStat> monthlyStats(Iterable<AttDay> days) {
  final byMonth = <String, List<AttDay>>{};
  for (final d in days) {
    byMonth.putIfAbsent(_monthOf(d.date), () => []).add(d);
  }
  return {for (final e in byMonth.entries) e.key: statOf(e.value)};
}
