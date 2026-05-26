import 'package:fido2demo/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('LoginView shows sign-in and register buttons', (tester) async {
    // build() は provider を読まない（アクション時のみ）ので override 不要で描画できる。
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: Scaffold(body: LoginView())),
      ),
    );
    expect(find.text('Passkey でサインイン'), findsOneWidget);
    expect(find.text('サインイン'), findsOneWidget);
    expect(find.text('新規登録 (メアドで)'), findsOneWidget);
  });
}
