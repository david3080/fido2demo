import 'dart:convert';
import 'package:http/http.dart' as http;

/// 解決済み CIBA 承認の1件（承認/拒否/期限切れ）。OP の /ciba/history 由来。
class CibaHistoryItem {
  CibaHistoryItem({
    required this.clientName,
    required this.scope,
    required this.bindingMessage,
    required this.outcome,
    required this.resolvedAt,
    this.authorizationDetails,
  });

  final String clientName;
  final String scope;
  final String bindingMessage;

  /// "approved" | "denied" | "expired"
  final String outcome;

  /// 解決時刻（epoch 秒）。
  final int resolvedAt;

  final List<Map<String, dynamic>>? authorizationDetails;

  static CibaHistoryItem? fromJson(Map<String, dynamic> j) {
    final outcome = j['outcome'] as String?;
    if (outcome == null) return null;
    List<Map<String, dynamic>>? ad;
    final raw = j['authorization_details'];
    if (raw is List) {
      ad = raw.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
    }
    return CibaHistoryItem(
      clientName: (j['client_id'] as String?) ?? '?',
      scope: (j['scope'] as String?) ?? '',
      bindingMessage: (j['binding_message'] as String?) ?? '',
      outcome: outcome,
      resolvedAt: (j['resolved_at'] as num?)?.toInt() ?? 0,
      authorizationDetails: ad,
    );
  }
}

/// 承認履歴を OP の `/ciba/history` から取得する（access token + DPoP）。
class CibaHistoryService {
  CibaHistoryService({required this.client, required this.endpoint});
  final http.Client client;
  final Uri endpoint;

  Future<List<CibaHistoryItem>> list(String accessToken) async {
    final res = await client.get(
      endpoint,
      headers: {'Authorization': 'Bearer $accessToken'},
    );
    if (res.statusCode != 200) return const [];
    final body = jsonDecode(res.body);
    if (body is! List) return const [];
    return body
        .whereType<Map>()
        .map((e) => CibaHistoryItem.fromJson(e.cast<String, dynamic>()))
        .whereType<CibaHistoryItem>()
        .toList();
  }
}
