import 'package:flutter/material.dart';

import '../core/repo.dart';
import '../core/ui.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _pass = TextEditingController();
  bool _firstTime = false;
  bool _busy = false;

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      if (_firstTime) {
        await Repo.i.createFirstAdmin(_name.text, _email.text, _pass.text);
      } else {
        await Repo.i.signIn(_email.text, _pass.text);
      }
    } catch (e) {
      if (mounted) toast(context, _friendly(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _friendly(Object e) {
    final s = e.toString();
    if (s.contains('invalid-credential') ||
        s.contains('wrong-password') ||
        s.contains('user-not-found')) {
      return 'Wrong email or password';
    }
    if (s.contains('email-already-in-use')) {
      return 'That email already has an account';
    }
    if (s.contains('weak-password')) {
      return 'Password must be at least 6 characters';
    }
    if (s.contains('permission-denied')) {
      return 'Setup is already done. Ask the admin for a login.';
    }
    return s;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.sports_cricket,
                  size: 64,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 8),
                Text(
                  'Cricket Academy',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 4),
                Text(_firstTime ? 'Create the admin account' : 'Staff sign in'),
                const SizedBox(height: 24),
                if (_firstTime) Field(_name, 'Your name', required: true),
                Field(
                  _email,
                  'Email',
                  type: TextInputType.emailAddress,
                  required: true,
                ),
                Field(_pass, 'Password', obscure: true, required: true),
                const SizedBox(height: 4),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _busy ? null : _submit,
                    child: Text(_firstTime ? 'Create admin' : 'Sign in'),
                  ),
                ),
                TextButton(
                  onPressed: () => setState(() => _firstTime = !_firstTime),
                  child: Text(
                    _firstTime
                        ? 'Back to sign in'
                        : 'First time setup (admin only)',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
