import 'package:fido2demo/ciba_approval.dart';
import 'package:fido2demo/ciba_request.dart';
import 'package:fido2demo/providers.dart';
import 'package:fido2demo/widgets/approval_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _FakePasskey implements PasskeyPort {
  _FakePasskey(this.result);
  final Map<String, dynamic> result;
  @override
  Future<Map<String, dynamic>> authenticate(String o) async => result;
}

PendingApproval _pending() => PendingApproval(
      authReqId: 'AR1',
      clientName: 'My RP',
      scope: 'openid profile',
      bindingMessage: '送金 1000円 を承認',
    );

Widget _host({required http.Client client, required PasskeyPort passkey}) {
  return ProviderScope(
    overrides: [
      httpClientProvider.overrideWithValue(client),
      passkeyPortProvider.overrideWithValue(passkey),
    ],
    child: MaterialApp(home: Scaffold(body: ApprovalDialog(pending: _pending()))),
  );
}

void main() {
  testWidgets('binding_message と scope を表示する', (tester) async {
    await tester.pumpWidget(_host(
      client: MockClient((_) async => http.Response('', 200)),
      passkey: _FakePasskey(const {}),
    ));
    expect(find.text('送金 1000円 を承認'), findsOneWidget);
    expect(find.textContaining('openid profile'), findsOneWidget);
    expect(find.text('My RP からの要求が届いています。'), findsOneWidget);
  });

  testWidgets('承認が失敗するとエラーと閉じるボタンを表示する', (tester) async {
    // options が 401 → CibaApprovalException。
    final client = MockClient((_) async => http.Response('login required', 401));
    await tester.pumpWidget(_host(
      client: client,
      passkey: _FakePasskey(const {'id': 'x', 'response': {}}),
    ));
    await tester.tap(find.text('承認 (Passkey)'));
    await tester.pump(); // _busy=true
    await tester.pump(); // await 完了後の setState
    expect(find.textContaining('options 401'), findsOneWidget);
    expect(find.text('閉じる'), findsOneWidget);
  });

  testWidgets('拒否が 204 で成功するとダイアログを閉じる', (tester) async {
    final client = MockClient((req) async {
      expect(req.url.path.endsWith('/reject'), true);
      return http.Response('', 204);
    });
    // showDialog 経由で出して pop を検証する。
    await tester.pumpWidget(ProviderScope(
      overrides: [
        httpClientProvider.overrideWithValue(client),
        passkeyPortProvider.overrideWithValue(_FakePasskey(const {})),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () => showDialog<void>(
                context: ctx,
                builder: (_) => ApprovalDialog(pending: _pending()),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('ログイン承認'), findsOneWidget); // ダイアログが開いた
    await tester.tap(find.text('拒否'));
    await tester.pumpAndSettle();
    expect(find.text('ログイン承認'), findsNothing); // 閉じた
  });
}
