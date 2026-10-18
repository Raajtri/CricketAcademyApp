import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'core/models.dart';
import 'core/repo.dart';
import 'core/ui.dart';
import 'firebase_options.dart';
import 'screens/home.dart';
import 'screens/login.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final opts = DefaultFirebaseOptions.currentPlatform;
  final configured = !opts.apiKey.startsWith('YOUR_');
  if (configured) {
    await Firebase.initializeApp(options: opts);
  }
  runApp(AcademyApp(configured: configured));
}

class AcademyApp extends StatelessWidget {
  final bool configured;
  const AcademyApp({super.key, required this.configured});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Cricket Academy',
    debugShowCheckedModeBanner: false,
    theme: buildTheme(),
    home: configured ? const AuthGate() : const SetupNeeded(),
  );
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) => Live<User?>(
    stream: Repo.i.authChanges,
    builder: (c, user) {
      if (user == null) return const LoginScreen();
      return Live<AppUser?>(
        stream: Repo.i.profile(user.uid),
        builder: (c, me) => me == null ? const NoAccess() : HomeShell(me: me),
      );
    },
  );
}

class NoAccess extends StatelessWidget {
  const NoAccess({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('No access')),
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'This login is not registered with the academy.\nAsk the admin to create your account.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: Repo.i.signOut,
              child: const Text('Sign out'),
            ),
          ],
        ),
      ),
    ),
  );
}

class SetupNeeded extends StatelessWidget {
  const SetupNeeded({super.key});
  @override
  Widget build(BuildContext context) => const Scaffold(
    body: Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          'Firebase is not set up yet.\n\nFollow SETUP.md, then paste your Firebase keys into '
          'lib/firebase_options.dart and run the app again.',
          textAlign: TextAlign.center,
        ),
      ),
    ),
  );
}
