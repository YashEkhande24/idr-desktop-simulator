import 'package:flutter_test/flutter_test.dart';
import 'package:idr_bt_companion/main.dart';

void main() {
  testWidgets('IDR Ghost Beacon app smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const IdrCompanionApp());

    expect(find.text('IDR GHOST BEACON'), findsOneWidget);
    expect(find.text('HARDWARE SATELLITE FIX'), findsOneWidget);
    expect(find.text('TRANSMISSION RATE'), findsOneWidget);
  });
}
