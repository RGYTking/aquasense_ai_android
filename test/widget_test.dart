import 'package:flutter_test/flutter_test.dart';
import 'package:aquasense_ai_android/main.dart';

void main() {
  testWidgets('AquaSense AI app loads', (WidgetTester tester) async {
    await tester.pumpWidget(const AquaSenseAI());

    expect(find.text('AquaSense AI'), findsWidgets);
  });
}