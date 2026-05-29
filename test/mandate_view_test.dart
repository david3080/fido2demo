import 'package:fido2demo/widgets/mandate_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget w) =>
    MaterialApp(home: Scaffold(body: SingleChildScrollView(child: w)));

void main() {
  group('MandateView - points', () {
    testWidgets('points: program / amount / merchant / PT 単位を表示する', (tester) async {
      await tester.pumpWidget(_host(MandateView(details: const [
        {
          'type': 'points',
          'actions': ['redeem'],
          'amount': '500',
          'program': 'リーサ',
          'merchant': 'Sakura Cafe',
        }
      ])));
      // 数値部分は別 Widget で表示するのでそれぞれ検証
      expect(find.text('500'), findsOneWidget);
      expect(find.text('PT'), findsOneWidget);
      expect(find.textContaining('リーサ'), findsOneWidget);
      expect(find.textContaining('Sakura Cafe'), findsOneWidget);
      expect(find.textContaining('redeem'), findsOneWidget);
    });

    testWidgets('points: amount が int でも表示できる（フェイルセーフ）', (tester) async {
      await tester.pumpWidget(_host(MandateView(details: const [
        {'type': 'points', 'amount': 500, 'program': 'リーサ', 'merchant': 'X'}
      ])));
      expect(find.text('500'), findsOneWidget);
    });
  });

  group('MandateView - payment', () {
    testWidgets('payment: currency と amount を表示する', (tester) async {
      await tester.pumpWidget(_host(MandateView(details: const [
        {
          'type': 'payment',
          'actions': ['create'],
          'amount': '1500',
          'currency': 'JPY',
          'merchant': 'example-shop',
        }
      ])));
      expect(find.text('1500'), findsOneWidget);
      expect(find.text('JPY'), findsOneWidget);
      expect(find.textContaining('example-shop'), findsOneWidget);
    });
  });

  group('MandateView - unknown type', () {
    testWidgets('未知 type は key:value の fallback 表示', (tester) async {
      await tester.pumpWidget(_host(MandateView(details: const [
        {'type': 'unknown_kind', 'foo': 'bar', 'qux': 42}
      ])));
      expect(find.text('type: unknown_kind'), findsOneWidget);
      expect(find.text('foo: bar'), findsOneWidget);
      expect(find.text('qux: 42'), findsOneWidget);
    });
  });

  group('MandateView - multi entry', () {
    testWidgets('複数 entry を順番に並べる', (tester) async {
      await tester.pumpWidget(_host(MandateView(details: const [
        {'type': 'points', 'amount': '300', 'program': 'リーサ', 'merchant': 'A'},
        {'type': 'payment', 'amount': '200', 'currency': 'JPY', 'merchant': 'B'},
      ])));
      expect(find.text('300'), findsOneWidget);
      expect(find.text('PT'), findsOneWidget);
      expect(find.text('200'), findsOneWidget);
      expect(find.text('JPY'), findsOneWidget);
    });
  });
}
