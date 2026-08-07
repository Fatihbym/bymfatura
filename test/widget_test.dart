import 'package:flutter_test/flutter_test.dart';
import 'package:bymfatura/main.dart';
import 'package:bymfatura/services/deep_link_service.dart';

void main() {
  testWidgets('Login screen smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(MyApp(deepLinkService: DeepLinkService()));

    expect(find.text('Giriş Yap'), findsOneWidget);
  });
}
