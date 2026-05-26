import 'package:fido2demo/ciba_approval.dart';
import 'package:fido2demo/ciba_request.dart';
import 'package:fido2demo/providers.dart';
import 'package:fido2demo/widgets/home_page.dart';
import 'package:fido2demo/widgets/login_view.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:oidc/oidc.dart';

class _FakePasskey implements PasskeyPort {
  @override
  Future<Map<String, dynamic>> authenticate(String o) async => const {};
}

void main() {
  testWidgets('未ログインなら LoginView を表示する', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        httpClientProvider.overrideWithValue(MockClient((_) async => http.Response('', 200))),
        passkeyPortProvider.overrideWithValue(_FakePasskey()),
        authUserProvider.overrideWith((ref) => Stream<OidcUser?>.value(null)),
      ],
      child: const MyApp(),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byType(LoginView), findsOneWidget);
  });

  testWidgets('コールド起動の CIBA seed で承認ダイアログを開く', (tester) async {
    // runApp 前に sink へ入った値（initState post-frame で拾う）を模す。
    pendingApprovalSink.value = PendingApproval(
      authReqId: 'AR1',
      clientName: 'RP',
      scope: 'openid',
      bindingMessage: 'msg',
    );
    addTearDown(() => pendingApprovalSink.value = null);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        httpClientProvider.overrideWithValue(MockClient((_) async => http.Response('', 200))),
        passkeyPortProvider.overrideWithValue(_FakePasskey()),
        authUserProvider.overrideWith((ref) => Stream<OidcUser?>.value(null)),
      ],
      child: const MyApp(),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    // ログイン画面の上に承認ダイアログが出る。
    expect(find.text('ログイン承認'), findsOneWidget);
    expect(find.text('msg'), findsOneWidget);
  });
}
