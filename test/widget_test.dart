import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openprx_mobile/app.dart';

void main() {
  testWidgets('OpenPRX app renders bottom navigation', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: OpenPrxApp()),
    );

    expect(find.text('Chat'), findsWidgets);
    expect(find.text('Models'), findsWidgets);
    expect(find.text('Docs'), findsWidgets);
    expect(find.text('Settings'), findsWidgets);
  });
}
