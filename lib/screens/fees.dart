import 'package:flutter/material.dart';

import '../core/models.dart';
import '../core/repo.dart';
import '../core/ui.dart';
import 'students.dart';

class FeesView extends StatefulWidget {
  const FeesView({super.key});
  @override
  State<FeesView> createState() => _FeesViewState();
}

class _FeesViewState extends State<FeesView> {
  String _filter = 'due'; // due | all
  late final Stream<List<Student>> _students = Repo.i.students();
  late final Stream<List<FeePayment>> _pays = Repo.i.payments();

  @override
  Widget build(BuildContext context) => Live<List<Student>>(
    stream: _students,
    builder: (c, all) => Live<List<FeePayment>>(
      stream: _pays,
      builder: (c, pays) {
        final active = all.where((s) => s.active).toList();
        final rows = [for (final s in active) (s, feeSummary(s, pays))];
        rows.sort((a, b) => b.$2.due.compareTo(a.$2.due));
        final shown = _filter == 'due'
            ? rows.where((r) => r.$2.due > 0).toList()
            : rows;
        final totalDue = rows.fold<double>(
          0,
          (a, r) => a + (r.$2.due > 0 ? r.$2.due : 0),
        );
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Total due: ${rupees(totalDue)}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'due', label: Text('Due')),
                      ButtonSegment(value: 'all', label: Text('All')),
                    ],
                    selected: {_filter},
                    onSelectionChanged: (s) =>
                        setState(() => _filter = s.first),
                  ),
                ],
              ),
            ),
            Expanded(
              child: shown.isEmpty
                  ? const EmptyState('No pending fees. 🎉')
                  : ListView.builder(
                      itemCount: shown.length,
                      itemBuilder: (c, i) {
                        final (s, f) = shown[i];
                        return Card(
                          child: ListTile(
                            title: Text(s.name),
                            subtitle: Text(
                              f.due > 0
                                  ? '${f.unpaidMonths.length} month(s) unpaid: ${f.unpaidMonths.take(3).map(fmtMonth).join(', ')}'
                                        '${f.unpaidMonths.length > 3 ? '…' : ''}'
                                  : 'Paid up',
                            ),
                            trailing: Text(
                              f.due > 0 ? rupees(f.due) : '✓',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: f.due > 0
                                    ? Theme.of(context).colorScheme.error
                                    : Colors.green,
                              ),
                            ),
                            onTap: () => collectFeeDialog(context, s, pays),
                            onLongPress: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => StudentDetail(
                                  studentId: s.id,
                                  me: AppUser(
                                    uid: '',
                                    name: '',
                                    email: '',
                                    role: 'admin',
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    ),
  );
}

Future<void> collectFeeDialog(
  BuildContext context,
  Student s,
  List<FeePayment> pays,
) async {
  final f = feeSummary(s, pays);
  final months = <String>[];
  var m = DateTime(s.joinDate.year, s.joinDate.month);
  final last = DateTime(DateTime.now().year, DateTime.now().month + 1);
  while (!m.isAfter(last)) {
    months.add(monthKey(m));
    m = DateTime(m.year, m.month + 1);
  }
  double paidFor(String k) => pays
      .where((p) => p.studentId == s.id && p.month == k)
      .fold(0.0, (a, p) => a + p.amount);
  var month = f.unpaidMonths.isNotEmpty
      ? f.unpaidMonths.first
      : monthKey(DateTime.now());
  var mode = 'Cash';
  String suggested() {
    final left = s.monthlyFee - paidFor(month);
    return (left > 0 ? left : s.monthlyFee).toStringAsFixed(0);
  }

  final amount = TextEditingController(text: suggested());
  final note = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, set) => AlertDialog(
        title: Text('Collect fee: ${s.name}'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: month,
                decoration: const InputDecoration(labelText: 'For month'),
                items: [
                  for (final k in months.reversed)
                    DropdownMenuItem(
                      value: k,
                      child: Text(
                        '${fmtMonth(k)}${paidFor(k) + 0.001 >= s.monthlyFee ? '  ✓' : ''}',
                      ),
                    ),
                ],
                onChanged: (v) => set(() {
                  month = v!;
                  amount.text = suggested();
                }),
              ),
              const SizedBox(height: 12),
              Field(amount, 'Amount (₹)', type: TextInputType.number),
              DropdownButtonFormField<String>(
                initialValue: mode,
                decoration: const InputDecoration(labelText: 'Payment mode'),
                items: [
                  for (final x in ['Cash', 'UPI', 'Card', 'Bank transfer'])
                    DropdownMenuItem(value: x, child: Text(x)),
                ],
                onChanged: (v) => set(() => mode = v!),
              ),
              const SizedBox(height: 12),
              Field(note, 'Note (optional)'),
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
            child: const Text('Save payment'),
          ),
        ],
      ),
    ),
  );
  if (ok == true && numOf(amount) > 0) {
    await Repo.i.addPayment(
      studentId: s.id,
      month: month,
      amount: numOf(amount),
      mode: mode,
      note: note.text.trim(),
    );
    if (context.mounted) {
      toast(context, 'Payment of ${rupees(numOf(amount))} saved');
    }
  }
}
