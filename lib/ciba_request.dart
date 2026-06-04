import 'dart:convert';

/// CIBA: Consumption Device からの保留中認証要求。FCM data 通知から復元する。
class PendingApproval {
  PendingApproval({
    required this.authReqId,
    required this.clientName,
    required this.scope,
    required this.bindingMessage,
    this.authorizationDetails,
  });

  final String authReqId;
  final String clientName;
  final String scope;
  final String bindingMessage;

  /// RFC 9396 authorization_details。RAR mandate（決済・ポイント等）が同意の中身。
  /// 構造はトップレベル type で分岐する（"payment", "points", ...）。
  final List<Map<String, dynamic>>? authorizationDetails;

  /// FCM data ペイロードから復元する。type が ciba_request で auth_req_id が
  /// あるときのみ生成。それ以外は null（無視）。
  /// authorization_details は string-only な FCM data 上では JSON 文字列で来るので parse する。
  static PendingApproval? fromFcmData(Map<String, dynamic> data) {
    if (data['type'] != 'ciba_request') return null;
    final authReqId = data['auth_req_id'] as String?;
    if (authReqId == null) return null;
    List<Map<String, dynamic>>? ad;
    final raw = data['authorization_details'];
    if (raw is String && raw.isNotEmpty) {
      try {
        final parsed = jsonDecode(raw);
        if (parsed is List) {
          ad = parsed
              .whereType<Map>()
              .map((e) => e.cast<String, dynamic>())
              .toList();
        }
      } catch (_) {
        // 壊れていれば無視。binding_message にフォールバックする。
      }
    }
    return PendingApproval(
      authReqId: authReqId,
      clientName: (data['client_name'] as String?) ?? '?',
      scope: (data['scope'] as String?) ?? '',
      bindingMessage: (data['binding_message'] as String?) ?? '',
      authorizationDetails: ad,
    );
  }
}
