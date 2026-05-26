import 'package:fido2demo/registration_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

RegistrationService _svc(int status) => RegistrationService(
      client: MockClient((req) async => http.Response('', status)),
      opBase: 'https://op',
    );

void main() {
  test('sendEmailChallenge: 204 で成功', () async {
    await _svc(204).sendEmailChallenge('a@example.com'); // 例外が出なければ成功
  });

  test('sendEmailChallenge: 429 はレート制限メッセージ', () async {
    expect(
      () => _svc(429).sendEmailChallenge('a@example.com'),
      throwsA(predicate((e) => e.toString().contains('多すぎます'))),
    );
  });

  test('sendEmailChallenge: 5xx はサーバ一時障害メッセージ', () async {
    expect(
      () => _svc(503).sendEmailChallenge('a@example.com'),
      throwsA(predicate((e) => e.toString().contains('一時的に利用できません'))),
    );
  });

  test('sendEmailChallenge: その他は予期しないエラー', () async {
    expect(
      () => _svc(400).sendEmailChallenge('a@example.com'),
      throwsA(predicate((e) => e.toString().contains('予期しないエラー'))),
    );
  });

  test('isUserCancelledLogin: キャンセル例外のみ true', () {
    expect(isUserCancelledLogin(Exception('FlutterAppAuthUserCancelledException: x')), true);
    expect(isUserCancelledLogin(Exception('network error')), false);
  });
}
