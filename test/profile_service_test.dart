import 'dart:convert';
import 'package:fido2demo/op_endpoints.dart';
import 'package:fido2demo/profile_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

final testEndpoints = OpEndpoints(
  signupEmailChallenge: Uri.parse('https://op/oidc/signup/email-challenge'),
  signupVerifyEmail: Uri.parse('https://op/oidc/signup/verify-email'),
  signupPasskeyOptions: Uri.parse('https://op/oidc/signup/passkey/options'),
  signupPasskeyVerify: Uri.parse('https://op/oidc/signup/passkey/verify'),
  profile: Uri.parse('https://op/oidc/me/profile'),
  fcmToken: Uri.parse('https://op/oidc/ciba/fcm-tokens'),
  mandateConsume: Uri.parse('https://op/oidc/oauth/mandate/consume'),
);

void main() {
  test('load: 200 の profile をパースする', () async {
    final client = MockClient((req) async {
      expect(req.method, 'GET');
      expect(req.url, testEndpoints.profile);
      expect(req.headers['Authorization'], 'Bearer AT');
      return http.Response(
        jsonEncode({
          'sub': 'u',
          'profile': {'name': '太郎', 'nickname': 't', 'gender': 'male', 'birthdate': '2000-01-01'},
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    final p = await ProfileService(client: client, endpoints: testEndpoints).load('AT');
    expect(p, isNotNull);
    expect(p!.name, '太郎');
    expect(p.nickname, 't');
    expect(p.gender, 'male');
    expect(p.birthdate, '2000-01-01');
  });

  test('load: 200 以外は null（空で編集開始）', () async {
    final client = MockClient((req) async => http.Response('nope', 401));
    final p = await ProfileService(client: client, endpoints: testEndpoints).load('AT');
    expect(p, isNull);
  });

  test('save: 200 で成功し、JSON を PUT する', () async {
    final client = MockClient((req) async {
      expect(req.method, 'PUT');
      final body = jsonDecode(req.body) as Map<String, dynamic>;
      expect(body['name'], '花子'); // trim される
      expect(body['gender'], 'female');
      return http.Response('{}', 200);
    });
    await ProfileService(client: client, endpoints: testEndpoints).save(
      'AT',
      ProfileData(name: ' 花子 ', gender: 'female'),
    );
  });

  test('save: 200 以外は ProfileException', () async {
    final client = MockClient((req) async => http.Response('err', 500));
    expect(
      () => ProfileService(client: client, endpoints: testEndpoints).save('AT', ProfileData()),
      throwsA(isA<ProfileException>()),
    );
  });

  test('registerFcmToken: token と platform を POST する', () async {
    var posted = false;
    final client = MockClient((req) async {
      posted = true;
      expect(req.url, testEndpoints.fcmToken);
      final body = jsonDecode(req.body) as Map<String, dynamic>;
      expect(body['token'], 'FCM');
      expect(body['platform'], 'ios');
      return http.Response('', 204);
    });
    await ProfileService(client: client, endpoints: testEndpoints).registerFcmToken('AT', 'FCM');
    expect(posted, true);
  });
}
