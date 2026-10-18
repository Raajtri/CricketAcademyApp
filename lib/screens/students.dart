import 'package:flutter/material.dart';

import '../core/models.dart';
import '../core/repo.dart';
import '../core/ui.dart';
import 'attendance_history.dart';
import 'fees.dart';
import 'shop.dart';

class StudentsTab extends StatefulWidget {
  final AppUser me;
  const StudentsTab({super.key, required this.me});
  @override
  State<StudentsTab> createState() => _StudentsTabState();
}

class _StudentsTabState extends State<StudentsTab> {
  String _q = '';
  String _batch = '';
  late final Stream<List<Student>> _students = Repo.i.students();
  late final Stream<List<Batch>> _batches = Repo.i.batches();
  late final Stream<List<FeePayment>> _payments = Repo.i.payments();
  late final Stream<List<AppUser>> _logins = Repo.i.staff();

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Students')),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const StudentForm()),
      ),
      icon: const Icon(Icons.person_add),
      label: const Text('Add student'),
    ),
    body: Live<List<Batch>>(
      stream: _batches,
      builder: (c, batches) => Live<List<Student>>(
        stream: _students,
        builder: (c, all) {
          final list = all
              .where((s) => _batch.isEmpty || s.batchId == _batch)
              .where((s) => s.name.toLowerCase().contains(_q.toLowerCase()))
              .toList();
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                child: TextField(
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Search students',
                  ),
                  onChanged: (v) => setState(() => _q = v),
                ),
              ),
              SizedBox(
                height: 48,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  children: [
                    _chip('All', '', all.length),
                    for (final b in batches)
                      _chip(
                        b.name,
                        b.id,
                        all.where((s) => s.batchId == b.id).length,
                      ),
                  ],
                ),
              ),
              Expanded(
                child: list.isEmpty
                    ? const EmptyState(
                        'No students found.\nTap "Add student" to enrol one.',
                      )
                    : widget.me.isAdmin
                    ? Live<List<FeePayment>>(
                        stream: _payments,
                        builder: (c, pays) => Live<List<AppUser>>(
                          stream: _logins,
                          builder: (c, users) => _list(
                            list,
                            batches,
                            pays,
                            users
                                .map((u) => u.studentId)
                                .where((id) => id.isNotEmpty)
                                .toSet(),
                          ),
                        ),
                      )
                    : _list(list, batches, null, null),
              ),
            ],
          );
        },
      ),
    ),
  );

  Widget _chip(String label, String id, int n) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
    child: ChoiceChip(
      label: Text('$label ($n)'),
      selected: _batch == id,
      onSelected: (_) => setState(() => _batch = id),
    ),
  );

  /// [hasLogin] holds the ids of students who already have a login (admin only, else null).
  Widget _list(
    List<Student> list,
    List<Batch> batches,
    List<FeePayment>? pays,
    Set<String>? hasLogin,
  ) => ListView.builder(
    padding: const EdgeInsets.only(bottom: 90),
    itemCount: list.length,
    itemBuilder: (c, i) {
      final s = list[i];
      final batch = batches.where((b) => b.id == s.batchId).firstOrNull;
      final due = pays == null ? 0.0 : feeSummary(s, pays).due;
      return Card(
        child: ListTile(
          leading: CircleAvatar(
            child: Text(s.name.isEmpty ? '?' : s.name[0].toUpperCase()),
          ),
          title: Text(s.name + (s.active ? '' : '  (inactive)')),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                [
                  batch?.name ?? 'No batch',
                  if (s.team.isNotEmpty) 'Team ${s.team}',
                ].join('  •  '),
              ),
              if (hasLogin != null)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      hasLogin.contains(s.id)
                          ? Icons.check_circle
                          : Icons.key_outlined,
                      size: 14,
                      color: hasLogin.contains(s.id)
                          ? Colors.green.shade700
                          : Theme.of(context).colorScheme.outline,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      hasLogin.contains(s.id)
                          ? 'Login created'
                          : 'No login yet. Tap to create',
                      style: TextStyle(
                        fontSize: 12,
                        color: hasLogin.contains(s.id)
                            ? Colors.green.shade700
                            : Theme.of(context).colorScheme.outline,
                      ),
                    ),
                  ],
                ),
            ],
          ),
          trailing: due > 0
              ? Chip(
                  label: Text('Due ${rupees(due)}'),
                  backgroundColor: Theme.of(context).colorScheme.errorContainer,
                  visualDensity: VisualDensity.compact,
                )
              : null,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => StudentDetail(studentId: s.id, me: widget.me),
            ),
          ),
        ),
      );
    },
  );
}

class StudentForm extends StatefulWidget {
  final Student? student;
  const StudentForm({super.key, this.student});
  @override
  State<StudentForm> createState() => _StudentFormState();
}

class _StudentFormState extends State<StudentForm> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.student?.name ?? '');
  late final _phone = TextEditingController(text: widget.student?.phone ?? '');
  late final _parent = TextEditingController(
    text: widget.student?.parentName ?? '',
  );
  late final _fee = TextEditingController(
    text: (widget.student?.monthlyFee ?? 0) == 0
        ? ''
        : widget.student!.monthlyFee.toStringAsFixed(0),
  );
  late final _team = TextEditingController(text: widget.student?.team ?? '');
  late final _notes = TextEditingController(text: widget.student?.notes ?? '');
  late String _batchId = widget.student?.batchId ?? '';
  late DateTime _join = widget.student?.joinDate ?? DateTime.now();
  late bool _active = widget.student?.active ?? true;
  List<Batch> _batches = [];

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    await Repo.i.saveStudent(
      Student(
        id: widget.student?.id ?? '',
        name: _name.text.trim(),
        phone: _phone.text.trim(),
        parentName: _parent.text.trim(),
        batchId: _batchId,
        team: _team.text.trim(),
        monthlyFee: numOf(_fee),
        joinDate: _join,
        active: _active,
        notes: _notes.text.trim(),
      ),
    );
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.student == null ? 'Add student' : 'Edit student'),
    ),
    body: Live<List<Batch>>(
      stream: Repo.i.batches(),
      builder: (c, batches) {
        _batches = batches;
        return Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Field(_name, 'Student name', required: true),
              Field(_parent, 'Parent / guardian name'),
              Field(_phone, 'Parent phone', type: TextInputType.phone),
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: DropdownButtonFormField<String>(
                  initialValue: batches.any((b) => b.id == _batchId)
                      ? _batchId
                      : '',
                  decoration: const InputDecoration(labelText: 'Batch'),
                  items: [
                    const DropdownMenuItem(value: '', child: Text('No batch')),
                    for (final b in batches)
                      DropdownMenuItem(value: b.id, child: Text(b.name)),
                  ],
                  onChanged: (v) {
                    setState(() {
                      _batchId = v ?? '';
                      final b = _batches
                          .where((b) => b.id == _batchId)
                          .firstOrNull;
                      if (b != null && numOf(_fee) == 0 && b.fee > 0) {
                        _fee.text = b.fee.toStringAsFixed(0);
                      }
                    });
                  },
                ),
              ),
              Field(_team, 'Team name (optional, e.g. Lions)'),
              Field(_fee, 'Monthly fee (₹)', type: TextInputType.number),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Joining date'),
                subtitle: Text(fmtDate(_join)),
                trailing: const Icon(Icons.calendar_today),
                onTap: () async {
                  final d = await showDatePicker(
                    context: context,
                    initialDate: _join,
                    firstDate: DateTime(2015),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                  );
                  if (d != null) setState(() => _join = d);
                },
              ),
              Field(_notes, 'Notes'),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Active'),
                value: _active,
                onChanged: (v) => setState(() => _active = v),
              ),
              const SizedBox(height: 8),
              FilledButton(onPressed: _save, child: const Text('Save')),
            ],
          ),
        );
      },
    ),
  );
}

class StudentDetail extends StatelessWidget {
  final String studentId;
  final AppUser me;
  const StudentDetail({super.key, required this.studentId, required this.me});

  @override
  Widget build(BuildContext context) => Live<List<Student>>(
    stream: Repo.i.students(),
    builder: (c, all) {
      final s = all.where((e) => e.id == studentId).firstOrNull;
      if (s == null) {
        return const Scaffold(body: EmptyState('Student not found'));
      }
      return Scaffold(
        appBar: AppBar(
          title: Text(s.name),
          actions: [
            IconButton(
              icon: const Icon(Icons.edit),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => StudentForm(student: s)),
              ),
            ),
            if (me.isAdmin)
              IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: () async {
                  if (await confirm(
                    context,
                    'Delete ${s.name}?',
                    'Fee and sale history stays but is no longer linked.',
                  )) {
                    await Repo.i.deleteStudent(s.id);
                    if (context.mounted) Navigator.pop(context);
                  }
                },
              ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            if (me.isAdmin) _LoginCard(student: s),
            Card(
              child: ListTile(
                leading: const Icon(Icons.fact_check_outlined),
                title: const Text('Attendance history'),
                subtitle: const Text(
                  'Present, late and absent for every month',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => StudentAttendanceScreen(student: s),
                  ),
                ),
              ),
            ),
            Card(
              child: Column(
                children: [
                  if (s.parentName.isNotEmpty)
                    ListTile(
                      leading: const Icon(Icons.person),
                      title: Text(s.parentName),
                    ),
                  if (s.phone.isNotEmpty)
                    ListTile(
                      leading: const Icon(Icons.phone),
                      title: Text(s.phone),
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
                  if (s.notes.isNotEmpty)
                    ListTile(
                      leading: const Icon(Icons.notes),
                      title: Text(s.notes),
                    ),
                ],
              ),
            ),
            if (me.isAdmin) _Money(student: s),
          ],
        ),
      );
    },
  );
}

class _Money extends StatelessWidget {
  final Student student;
  const _Money({required this.student});

  @override
  Widget build(BuildContext context) => Live<List<FeePayment>>(
    stream: Repo.i.payments(),
    builder: (c, pays) {
      final f = feeSummary(student, pays);
      final mine = pays.where((p) => p.studentId == student.id).toList();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Fees', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 6),
                  Text(
                    'Monthly ${rupees(student.monthlyFee)}  •  Paid ${rupees(f.paid)}  •  Due ${rupees(f.due)}',
                  ),
                  if (f.unpaidMonths.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        'Unpaid: ${f.unpaidMonths.map(fmtMonth).join(', ')}',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: () => collectFeeDialog(context, student, pays),
                    icon: const Icon(Icons.payments),
                    label: const Text('Collect fee'),
                  ),
                  for (final p in mine.take(12))
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        '${rupees(p.amount)}  for ${fmtMonth(p.month)}',
                      ),
                      subtitle: Text('${fmtDate(p.paidOn)}  •  ${p.mode}'),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () async {
                          if (await confirm(context, 'Delete this payment?')) {
                            await Repo.i.deletePayment(p.id);
                          }
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Live<List<Sale>>(
                stream: Repo.i.sales(),
                builder: (c, sales) {
                  final mine = sales
                      .where((s) => s.studentId == student.id)
                      .toList();
                  final bal = mine.fold<double>(0, (a, s) => a + s.balance);
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Kit & clothes bought',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        mine.isEmpty
                            ? 'Nothing yet'
                            : 'Balance due ${rupees(bal)}',
                      ),
                      const SizedBox(height: 8),
                      FilledButton.tonalIcon(
                        onPressed: () =>
                            sellItemDialog(context, student: student),
                        icon: const Icon(Icons.shopping_cart_outlined),
                        label: const Text('Sell item'),
                      ),
                      for (final s in mine) saleTile(context, s),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      );
    },
  );
}

/// Admin: give a student their own login (fees, attendance, scoring), or take it away.
class _LoginCard extends StatelessWidget {
  final Student student;
  const _LoginCard({required this.student});

  @override
  Widget build(BuildContext context) => Live<List<AppUser>>(
    stream: Repo.i.staff(),
    builder: (c, users) {
      final login = users.where((u) => u.studentId == student.id).firstOrNull;
      return Card(
        color: login == null ? null : Colors.green.shade50,
        child: ListTile(
          leading: Icon(
            login == null ? Icons.key_outlined : Icons.check_circle,
            color: login == null ? null : Colors.green.shade700,
          ),
          title: Text(
            login == null
                ? 'Student login: not created'
                : 'Student login: created',
          ),
          subtitle: Text(
            login == null
                ? 'Create one so ${student.name} can see fees and attendance and score matches.'
                : 'Signs in with ${login.email}',
          ),
          trailing: login == null
              ? FilledButton.tonal(
                  onPressed: () => _create(context),
                  child: const Text('Create login'),
                )
              : TextButton(
                  onPressed: () async {
                    if (await confirm(
                      context,
                      'Remove ${student.name}\'s login?',
                      'They will no longer be able to sign in.',
                    )) {
                      await Repo.i.removeStaff(login.uid);
                    }
                  },
                  child: const Text('Remove'),
                ),
        ),
      );
    },
  );

  Future<void> _create(BuildContext context) async {
    final email = TextEditingController();
    final pass = TextEditingController();
    final form = GlobalKey<FormState>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Login for ${student.name}'),
        content: SingleChildScrollView(
          child: Form(
            key: form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Field(
                  email,
                  'Email',
                  type: TextInputType.emailAddress,
                  required: true,
                ),
                Field(
                  pass,
                  'Password (min 6 characters)',
                  obscure: true,
                  required: true,
                ),
                const Text(
                  'Share these with the student. They sign in on the same app or website.',
                  style: TextStyle(fontSize: 12),
                ),
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
            child: const Text('Create'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await Repo.i.createLogin(
        name: student.name,
        email: email.text,
        password: pass.text,
        role: 'student',
        studentId: student.id,
      );
      if (context.mounted) toast(context, 'Login created for ${student.name}');
    } catch (e) {
      if (context.mounted) toast(context, 'Could not create: $e');
    }
  }
}
