import 'package:flutter/material.dart';

import '../core/models.dart';
import '../core/repo.dart';
import '../core/ui.dart';

class BatchesScreen extends StatelessWidget {
  const BatchesScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Batches')),
    floatingActionButton: FloatingActionButton(
      onPressed: () => _edit(context, null),
      child: const Icon(Icons.add),
    ),
    body: Live<List<Batch>>(
      stream: Repo.i.batches(),
      builder: (c, list) {
        if (list.isEmpty) {
          return const EmptyState(
            'No batches yet.\nAdd one, e.g. "Under-14 Morning".',
          );
        }
        return ListView(
          padding: const EdgeInsets.only(top: 8, bottom: 90),
          children: [
            for (final b in list)
              Card(
                child: ListTile(
                  title: Text(b.name),
                  subtitle: Text(
                    [
                      if (b.timing.isNotEmpty) b.timing,
                      if (b.coach.isNotEmpty) 'Coach: ${b.coach}',
                      if (b.fee > 0) 'Fee ${rupees(b.fee)}/month',
                    ].join('  •  '),
                  ),
                  onTap: () => _edit(context, b),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () async {
                      if (await confirm(
                        context,
                        'Delete ${b.name}?',
                        'Students stay, but lose this batch.',
                      )) {
                        await Repo.i.deleteBatch(b.id);
                      }
                    },
                  ),
                ),
              ),
          ],
        );
      },
    ),
  );

  Future<void> _edit(BuildContext context, Batch? b) async {
    final name = TextEditingController(text: b?.name ?? '');
    final timing = TextEditingController(text: b?.timing ?? '');
    final coach = TextEditingController(text: b?.coach ?? '');
    final fee = TextEditingController(
      text: b == null || b.fee == 0 ? '' : b.fee.toStringAsFixed(0),
    );
    final form = GlobalKey<FormState>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(b == null ? 'New batch' : 'Edit batch'),
        content: SingleChildScrollView(
          child: Form(
            key: form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Field(name, 'Batch name', required: true),
                Field(timing, 'Timing (e.g. 6-8 AM, Mon-Sat)'),
                Field(coach, 'Coach'),
                Field(fee, 'Default monthly fee', type: TextInputType.number),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (form.currentState!.validate()) Navigator.pop(c, true);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await Repo.i.saveBatch(
        Batch(
          id: b?.id ?? '',
          name: name.text.trim(),
          timing: timing.text.trim(),
          coach: coach.text.trim(),
          fee: numOf(fee),
        ),
      );
    }
  }
}
