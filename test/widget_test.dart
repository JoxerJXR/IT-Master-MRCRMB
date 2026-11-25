import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:it_master/main.dart';

void main() {
  testWidgets('Главная панель отображает основные разделы', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: DashboardPage(onNavigate: (_) {}),
    ));
    expect(find.text('Добро пожаловать!'), findsOneWidget);
    expect(find.text('Картриджи'), findsOneWidget);
    expect(find.text('Заявки'), findsOneWidget);
    expect(find.text('Оборудование'), findsOneWidget);
  });
}
