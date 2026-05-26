/// Magic Link（Universal Link で受信）の URI から登録用 token を取り出す。
/// host=oidc.sonrisa.co.jp / path=/r / クエリ t が非空のときのみ token を返す。
/// 条件を満たさなければ null（無視）。
String? parseMagicLinkToken(Uri? uri) {
  if (uri == null) return null;
  if (uri.host != 'oidc.sonrisa.co.jp') return null;
  if (uri.path != '/r') return null;
  final t = uri.queryParameters['t'];
  if (t == null || t.isEmpty) return null;
  return t;
}
