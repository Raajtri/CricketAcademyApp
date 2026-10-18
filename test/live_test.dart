import 'package:cricket_academy/core/ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Live builds when the stream emits null (e.g. signed out)', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Live<String?>(
          stream: Stream.value(null),
          builder: (c, v) => Text(v == null ? 'signed out' : 'signed in'),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('signed out'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
}
