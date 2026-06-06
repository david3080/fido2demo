import 'dart:convert';
import 'package:http/http.dart' as http;

import 'op_endpoints.dart';

/// HTTP ステータスを利用者向けの日本語メッセージに変換する例外。
class RegistrationException implements Exception {
  RegistrationException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// 新規登録: メアド宛に Magic Link 確認メールを送る (signup_email_challenge)。
class RegistrationService {
  RegistrationService({required this.client, required this.endpoints});
  final http.Client client;
  final OpEndpoints endpoints;

  /// 成功で正常終了(204)。429/5xx/その他は利用者向けメッセージの例外。
  Future<void> sendEmailChallenge(String email) async {
    final res = await client
        .post(
          endpoints.signupEmailChallenge,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'email': email}),
        )
        .timeout(const Duration(seconds: 30));
    if (res.statusCode == 429) {
      throw RegistrationException('リクエストが多すぎます。しばらくしてから再試行してください。');
    }
    if (res.statusCode >= 500) {
      throw RegistrationException('サーバが一時的に利用できません。しばらくしてから再試行してください。');
    }
    if (res.statusCode != 204) {
      throw RegistrationException('予期しないエラー (HTTP ${res.statusCode})');
    }
  }
}

/// OIDC ログインの「ユーザーがキャンセルした」例外かどうか。
/// キャンセルは失敗トーストを出さないために区別する。
bool isUserCancelledLogin(Object error) =>
    error.toString().contains('FlutterAppAuthUserCancelledException');
