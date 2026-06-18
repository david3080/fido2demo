import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:passkeys/authenticator.dart';
import 'package:passkeys/types.dart';
import 'ciba_request.dart';

/// パスキー認証のポート。本番は iOS ネイティブ、テストはフェイクに差し替える。
/// options(JSON文字列) を受け、{id, response:{...}} 形式の assertion を返す。
abstract class PasskeyPort {
  Future<Map<String, dynamic>> authenticate(String optionsJson);
}

class NativePasskey implements PasskeyPort {
  const NativePasskey();
  @override
  Future<Map<String, dynamic>> authenticate(String optionsJson) async {
    final req = AuthenticateRequestType.fromJsonString(optionsJson);
    final resp = await PasskeyAuthenticator().authenticate(req);
    return jsonDecode(resp.toJsonString()) as Map<String, dynamic>;
  }
}

class CibaApprovalException implements Exception {
  CibaApprovalException(this.message, {this.stale = false});
  final String message;

  /// 要求が期限切れ/処理済み（404/409/410）で、もう操作できないことを示す。
  /// UI は承認・拒否で一貫した「期限切れ（または処理済み）」表示にする。
  final bool stale;

  @override
  String toString() => message;
}

/// 期限切れ/処理済みを示す HTTP ステータスか。
bool _isStale(int status) => status == 404 || status == 409 || status == 410;

/// CIBA 承認/拒否のオーケストレーション。承認はパスキー assertion 自体が本人性を
/// 証明するためログイン(access token)不要。エンドポイントは公開なので素の HTTP で呼ぶ。
class CibaApprovalService {
  CibaApprovalService({required this.client, required this.passkey, required this.opBase});
  final http.Client client;
  final PasskeyPort passkey;
  final String opBase;

  Uri _u(String authReqId, String action) =>
      Uri.parse('$opBase/oidc/ciba/$authReqId/$action');

  /// 承認: options 取得 → パスキー認証(UV 必須) → assertion を approve に送る。
  Future<void> approve(PendingApproval pending) async {
    final optsRes = await client.post(
      _u(pending.authReqId, 'passkey-options'),
      headers: {'Content-Type': 'application/json'},
      body: '{}',
    );
    if (optsRes.statusCode != 200) {
      // 期限切れ/処理済みなら Face ID を出す前にここで止まる（404）。
      throw CibaApprovalException('options ${optsRes.statusCode}: ${optsRes.body}',
          stale: _isStale(optsRes.statusCode));
    }
    final assertion = await passkey.authenticate(optsRes.body);
    final apprRes = await client.post(
      _u(pending.authReqId, 'approve'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'id': assertion['id'], 'response': assertion['response']}),
    );
    if (apprRes.statusCode != 200) {
      throw CibaApprovalException('approve ${apprRes.statusCode}: ${apprRes.body}',
          stale: _isStale(apprRes.statusCode));
    }
  }

  /// 拒否: ログイン不要の fail-safe 操作。拒否成立は 204。
  /// 期限切れ/処理済みは 409（偽成功にしない）。
  Future<void> reject(PendingApproval pending) async {
    final res = await client.post(_u(pending.authReqId, 'reject'));
    if (res.statusCode == 204) return;
    throw CibaApprovalException('reject ${res.statusCode}: ${res.body}',
        stale: _isStale(res.statusCode));
  }
}
