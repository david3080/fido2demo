import 'package:fido2demo/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // 不正なメアドは _send がネットワークに行く前に弾く（provider/HTTP 不要でテスト可能）。
  testWidgets('shows validation error for malformed email', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: Scaffold(body: RegisterEmailDialog())),
      ),
    );
    await tester.enterText(find.byType(TextField), 'not-an-email');
    await tester.tap(find.text('送信'));
    await tester.pump();
    expect(find.textContaining('形式が正しくありません'), findsOneWidget);
  });

  testWidgets('shows error for empty email', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: Scaffold(body: RegisterEmailDialog())),
      ),
    );
    await tester.tap(find.text('送信'));
    await tester.pump();
    // 説明文 "…入力してください。確認メール…" と区別するため完全一致で検証。
    expect(find.text('メールアドレスを入力してください'), findsOneWidget);
  });
}
