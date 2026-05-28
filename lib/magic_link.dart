/// Magic Link の URI から登録用 token を取り出す。受け付ける形式は2つ:
///  1. Universal Link:   https://oidc.sonrisa.co.jp/r?t={token}
///  2. カスタムスキーム: jp.co.sonrisa.fido2demo://magic?t={token}
/// （Safari 等から「アプリで開く」ボタンで起動された場合のフォールバック経路。
///  iOS は同サイト Safari からだと Universal Link を発火させないため、カスタム
///  スキームが現実的な手段になる。）
/// 条件を満たさなければ null（無視）。
String? parseMagicLinkToken(Uri? uri) {
  if (uri == null) return null;
  final viaUniversal = uri.scheme == 'https' &&
      uri.host == 'oidc.sonrisa.co.jp' &&
      uri.path == '/r';
  final viaCustom =
      uri.scheme == 'jp.co.sonrisa.fido2demo' && uri.host == 'magic';
  if (!viaUniversal && !viaCustom) return null;
  final t = uri.queryParameters['t'];
  if (t == null || t.isEmpty) return null;
  return t;
}
