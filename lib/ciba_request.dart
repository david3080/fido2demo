/// CIBA: Consumption Device からの保留中認証要求。FCM data 通知から復元する。
class PendingApproval {
  PendingApproval({
    required this.authReqId,
    required this.clientName,
    required this.scope,
    required this.bindingMessage,
  });

  final String authReqId;
  final String clientName;
  final String scope;
  final String bindingMessage;

  /// FCM data ペイロードから復元する。type が ciba_request で auth_req_id が
  /// あるときのみ生成。それ以外は null（無視）。
  static PendingApproval? fromFcmData(Map<String, dynamic> data) {
    if (data['type'] != 'ciba_request') return null;
    final authReqId = data['auth_req_id'] as String?;
    if (authReqId == null) return null;
    return PendingApproval(
      authReqId: authReqId,
      clientName: (data['client_name'] as String?) ?? '?',
      scope: (data['scope'] as String?) ?? '',
      bindingMessage: (data['binding_message'] as String?) ?? '',
    );
  }
}
