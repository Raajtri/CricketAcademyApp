import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

final _money = NumberFormat.currency(
  locale: 'en_IN',
  symbol: '₹',
  decimalDigits: 0,
);
String rupees(num v) => _money.format(v);
String fmtDate(DateTime d) => DateFormat('d MMM y').format(d);
String fmtMonth(String yyyyMm) {
  final p = yyyyMm.split('-');
  return DateFormat('MMM y').format(DateTime(int.parse(p[0]), int.parse(p[1])));
}

ThemeData buildTheme() => ThemeData(
  useMaterial3: true,
  colorSchemeSeed: const Color(0xFF1B7F3B),
  inputDecorationTheme: const InputDecorationTheme(
    border: OutlineInputBorder(),
  ),
  cardTheme: const CardThemeData(
    margin: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
  ),
);

void toast(BuildContext c, String msg) =>
    ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(msg)));

Future<bool> confirm(BuildContext c, String title, [String body = '']) async {
  final r = await showDialog<bool>(
    context: c,
    builder: (_) => AlertDialog(
      title: Text(title),
      content: body.isEmpty ? null : Text(body),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(c, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(c, true),
          child: const Text('Yes'),
        ),
      ],
    ),
  );
  return r ?? false;
}

/// StreamBuilder with loading and error states handled once.
class Live<T> extends StatelessWidget {
  final Stream<T> stream;
  final Widget Function(BuildContext, T) builder;
  const Live({super.key, required this.stream, required this.builder});

  @override
  Widget build(BuildContext context) => StreamBuilder<T>(
    stream: stream,
    builder: (c, snap) {
      if (snap.hasError) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Could not load data.\n${snap.error}',
              textAlign: TextAlign.center,
            ),
          ),
        );
      }
      // A null value (e.g. "signed out") is still a real answer, so wait on the
      // connection state rather than on hasData.
      if (snap.connectionState == ConnectionState.waiting) {
        return const Center(child: CircularProgressIndicator());
      }
      return builder(c, snap.data as T);
    },
  );
}

class EmptyState extends StatelessWidget {
  final String text;
  const EmptyState(this.text, {super.key});
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodyLarge,
      ),
    ),
  );
}

class Field extends StatelessWidget {
  final TextEditingController c;
  final String label;
  final TextInputType? type;
  final bool obscure;
  final bool required;
  const Field(
    this.c,
    this.label, {
    super.key,
    this.type,
    this.obscure = false,
    this.required = false,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextFormField(
      controller: c,
      keyboardType: type,
      obscureText: obscure,
      decoration: InputDecoration(labelText: label),
      validator: required
          ? (v) => (v == null || v.trim().isEmpty) ? 'Required' : null
          : null,
    ),
  );
}

double numOf(TextEditingController c) => double.tryParse(c.text.trim()) ?? 0;
