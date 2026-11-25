import 'package:flutter_test/flutter_test.dart';
import 'package:it_master/main.dart';

void main() {
  testWidgets('IT-Мастер открывает главный экран', (tester) async {
    await tester.pumpWidget(const ITMasterApp());
    await tester.pumpAndSettle();
    expect(find.text('Добро пожаловать!'), findsOneWidget);
  });
}