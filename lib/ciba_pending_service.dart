import 'dart:convert';
import 'package:http/http.dart' as http;

import 'ciba_request.dart';

/// 自分宛の pending CIBA 承認要求を OP の `/ciba/pending` から取得する。
/// client は DPoP 付き http.Client（access token は呼び出し側が渡す）。
class CibaPendingService {
  CibaPendingService({required this.client, required this.endpoint});
  final http.Client client;
  final Uri endpoint;

  /// 200 以外・非配列は空リスト（受信箱は「無し」で表示できる）。
  Future<List<PendingApproval>> list(String accessToken) async {
    final res = await client.get(
      endpoint,
      headers: {'Authorization': 'Bearer $accessToken'},
    );
    if (res.statusCode != 200) return const [];
    final body = jsonDecode(res.body);
    if (body is! List) return const [];
    return body
        .whereType<Map>()
        .map((e) => PendingApproval.fromPendingJson(e.cast<String, dynamic>()))
        .whereType<PendingApproval>()
        .toList();
  }
}
