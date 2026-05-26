import 'dart:convert';
import 'package:fido2demo/ciba_approval.dart';
import 'package:fido2demo/ciba_request.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

PendingApproval _pending() => PendingApproval(
      authReqId: 'AR1',
      clientName: 'RP',
      scope: 'openid',
      bindingMessage: 'msg',
    );

class _FakePasskey implements PasskeyPort {
  _FakePasskey(this.result, {this.error});
  final Map<String, dynamic>? result;
  final Object? error;
  @override
  Future<Map<String, dynamic>> authenticate(String optionsJson) async {
    if (error != null) throw error!;
    return result!;
  }
}

void main() {
  test('approve: options→passkey→approve の順に呼び、assertion を送る', () async {
    final calls = <String>[];
    final client = MockClient((req) async {
      calls.add('${req.method} ${req.url.path}');
      if (req.url.path.endsWith('/passkey-options')) {
        return http.Response('{"challenge":"c"}', 200);
      }
      if (req.url.path.endsWith('/approve')) {
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        expect(body['id'], 'CID');
        expect(body['response'], {'x': 1});
        return http.Response('{"ok":true}', 200);
      }
      return http.Response('unexpected', 404);
    });
    final svc = CibaApprovalService(
      client: client,
      passkey: _FakePasskey({'id': 'CID', 'response': {'x': 1}}),
      opBase: 'https://op',
    );
    await svc.approve(_pending());
    expect(calls, [
      'POST /oidc/ciba/AR1/passkey-options',
      'POST /oidc/ciba/AR1/approve',
    ]);
  });

  test('approve: options が 200 以外なら例外、passkey は呼ばれない', () async {
    var passkeyCalled = false;
    final client = MockClient((req) async => http.Response('login required', 401));
    final svc = CibaApprovalService(
      client: client,
      passkey: _FakePasskey(null, error: StateError('should not be called')),
      opBase: 'https://op',
    );
    expect(() => svc.approve(_pending()), throwsA(isA<CibaApprovalException>()));
    expect(passkeyCalled, false);
  });

  test('approve: passkey キャンセル(例外)はそのまま伝播する', () async {
    final client = MockClient((req) async => http.Response('{}', 200));
    final svc = CibaApprovalService(
      client: client,
      passkey: _FakePasskey(null, error: Exception('user cancelled')),
      opBase: 'https://op',
    );
    expect(() => svc.approve(_pending()), throwsA(isA<Exception>()));
  });

  test('approve: 後発が 409 already handled のとき例外(先勝ち負け)', () async {
    final client = MockClient((req) async {
      if (req.url.path.endsWith('/passkey-options')) return http.Response('{}', 200);
      return http.Response('already handled', 409);
    });
    final svc = CibaApprovalService(
      client: client,
      passkey: _FakePasskey({'id': 'x', 'response': {}}),
      opBase: 'https://op',
    );
    expect(
      () => svc.approve(_pending()),
      throwsA(predicate((e) => e.toString().contains('409'))),
    );
  });

  test('reject: 204 で成功', () async {
    final client = MockClient((req) async {
      expect(req.url.path, '/oidc/ciba/AR1/reject');
      return http.Response('', 204);
    });
    final svc = CibaApprovalService(
      client: client,
      passkey: _FakePasskey(const {}),
      opBase: 'https://op',
    );
    await svc.reject(_pending());
  });

  test('reject: 204 以外は例外', () async {
    final client = MockClient((req) async => http.Response('err', 500));
    final svc = CibaApprovalService(
      client: client,
      passkey: _FakePasskey(const {}),
      opBase: 'https://op',
    );
    expect(() => svc.reject(_pending()), throwsA(isA<CibaApprovalException>()));
  });
}
