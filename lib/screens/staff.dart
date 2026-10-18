import 'package:flutter/material.dart';

import '../core/models.dart';
import '../core/repo.dart';
import '../core/ui.dart';

class StaffScreen extends StatelessWidget {
  const StaffScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Logins: coaches & students')),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: () => _chooseType(context),
      icon: const Icon(Icons.person_add),
      label: const Text('Add login'),
    ),
    body: Live<List<AppUser>>(
      stream: Repo.i.staff(),
      builder: (c, list) => ListView(
        padding: const EdgeInsets.only(top: 8, bottom: 90),
        children: [
          for (final u in list)
            Card(
              child: ListTile(
                leading: Icon(
                  u.isAdmin
                      ? Icons.admin_panel_settings
                      : (u.isStudent ? Icons.school : Icons.sports),
                ),
                title: Text(u.name),
                subtitle: Text('${u.email}  •  ${u.roleLabel}'),
                trailing: u.isAdmin
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.delete_outline),
                        tooltip: 'Remove access',
                        onPressed: () async {
                          if (await confirm(
                            context,
                            'Remove ${u.name}?',
                            'They will no longer be able to use the app.',
                          )) {
                            await Repo.i.removeStaff(u.uid);
                          }
                        },
                      ),
              ),
            ),
        ],
      ),
    ),
  );

  Future<void> _chooseType(BuildContext context) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.sports),
              title: const Text('Coach login'),
              subtitle: const Text(
                'Marks attendance, manages students, scores matches',
              ),
              onTap: () => Navigator.pop(c, 'coach'),
            ),
            ListTile(
              leading: const Icon(Icons.school),
              title: const Text('Student login'),
              subtitle: const Text(
                'Sees own fees and attendance, scores matches',
              ),
              onTap: () => Navigator.pop(c, 'student'),
            ),
          ],
        ),
      ),
    );
    if (!context.mounted) return;
    if (choice == 'coach') {
      await _addCoach(context);
    } else if (choice == 'student') {
      await _addStudent(context);
    }
  }

  Future<void> _addStudent(BuildContext context) async {
    final students = (await Repo.i.students().first)
        .where((s) => s.active)
        .toList();
    final users = await Repo.i.staff().first;
    final taken = users
        .map((u) => u.studentId)
        .where((id) => id.isNotEmpty)
        .toSet();
    final free = students.where((s) => !taken.contains(s.id)).toList();
    if (!context.mounted) return;
    if (free.isEmpty) {
      toast(
        context,
        students.isEmpty
            ? 'Add a student first (Students tab), then create their login.'
            : 'Every student already has a login.',
      );
      return;
    }
    Student? who = free.first;
    final email = TextEditingController();
    final pass = TextEditingController();
    final form = GlobalKey<FormState>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: const Text('New student login'),
          content: SingleChildScrollView(
            child: Form(
              key: form,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<Student>(
                    initialValue: who,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Student'),
                    items: [
                      for (final s in free)
                        DropdownMenuItem(value: s, child: Text(s.name)),
                    ],
                    onChanged: (v) => set(() => who = v),
                  ),
                  const SizedBox(height: 12),
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
      ),
    );
    if (ok != true || who == null) return;
    try {
      await Repo.i.createLogin(
        name: who!.name,
        email: email.text,
        password: pass.text,
        role: 'student',
        studentId: who!.id,
      );
      if (context.mounted) toast(context, 'Login created for ${who!.name}');
    } catch (e) {
      if (context.mounted) toast(context, 'Could not create: $e');
    }
  }

  Future<void> _addCoach(BuildContext context) async {
    final name = TextEditingController();
    final email = TextEditingController();
    final pass = TextEditingController();
    final form = GlobalKey<FormState>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('New coach login'),
        content: SingleChildScrollView(
          child: Form(
            key: form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Field(name, 'Name', required: true),
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
        name: name.text,
        email: email.text,
        password: pass.text,
        role: 'coach',
      );
      if (context.mounted) toast(context, 'Coach account created');
    } catch (e) {
      if (context.mounted) toast(context, 'Could not create: $e');
    }
  }
}
