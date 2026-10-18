import 'package:cricket_academy/core/attendance.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> sheet(String date, Map<String, String> records) => {
  'date': date,
  'batchId': 'b',
  'records': records,
};

void main() {
  final sheets = [
    sheet('2026-09-28', {'s1': 'P', 's2': 'A'}),
    sheet('2026-10-01', {'s1': 'P', 's2': 'P'}),
    sheet('2026-10-02', {'s1': 'L', 's2': 'A'}),
    sheet('2026-10-03', {'s1': 'A'}),
    sheet('2026-10-04', {'s2': 'P'}), // s1 not marked that day
    {
      'date': 'bad-date',
      'records': {'s1': 'P'},
    }, // ignored
  ];

  test(
    'days for one student, newest first, ignoring unmarked and invalid sheets',
    () {
      final d = attendanceDays(sheets, 's1');
      expect(d.map((x) => x.status), ['A', 'L', 'P', 'P']);
      expect(d.first.date, DateTime(2026, 10, 3));
    },
  );

  test('monthly stats count late as attended', () {
    final m = monthlyStats(attendanceDays(sheets, 's1'));
    expect(m.keys.toSet(), {'2026-09', '2026-10'});
    expect(m['2026-10']!.present, 1);
    expect(m['2026-10']!.late, 1);
    expect(m['2026-10']!.absent, 1);
    expect(m['2026-10']!.held, 3);
    expect(m['2026-10']!.percent, closeTo(66.67, 0.01));
    expect(m['2026-09']!.percent, 100);
  });

  test('overall stats and empty case', () {
    final all = statOf(attendanceDays(sheets, 's2'));
    expect(all.present, 2);
    expect(all.absent, 2);
    expect(all.percent, 50);
    expect(statOf(const []).percent, 0);
  });
}
