import 'package:fido2demo/op_endpoints.dart';
import 'package:fido2demo/registration_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

final _endpoints = OpEndpoints(
  signupEmailChallenge: Uri.parse('https://op/oidc/signup/email-challenge'),
  signupVerifyEmail: Uri.parse('https://op/oidc/signup/verify-email'),
  signupPasskeyOptions: Uri.parse('https://op/oidc/signup/passkey/options'),
  signupPasskeyVerify: Uri.parse('https://op/oidc/signup/passkey/verify'),
  profile: Uri.parse('https://op/oidc/me/profile'),
  fcmToken: Uri.parse('https://op/oidc/ciba/fcm-tokens'),
  mandateConsume: Uri.parse('https://op/oidc/oauth/mandate/consume'),
);

RegistrationService _svc(int status) => RegistrationService(
      client: MockClient((req) async => http.Response('', status)),
      endpoints: _endpoints,
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
