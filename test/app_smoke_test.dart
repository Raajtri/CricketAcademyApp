import 'package:cricket_academy/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows the setup screen until Firebase keys are added', (
    tester,
  ) async {
    await tester.pumpWidget(const AcademyApp(configured: false));
    expect(find.textContaining('Firebase is not set up yet'), findsOneWidget);
  });
}
