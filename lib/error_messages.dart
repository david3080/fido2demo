/// 登録系 API（verify-email / passkey/options / passkey/verify）の HTTP エラーを
/// 利用者向けメッセージに変換する。サーバは 400 で "invalid or expired token" や
/// "challenge invalid/expired" 等を返すので、それを「期限切れ」と明示する。
String explainRegistrationHttpError(int code, String body) {
  final b = body.toLowerCase();
  final expiredLike = b.contains('expired') ||
      b.contains('invalid or') ||
      b.contains('challenge invalid');
  if (code == 401 || (code == 400 && expiredLike)) {
    return '登録の有効期限が切れたか、リンクが無効です（30分以内に完了してください）。\n'
        'ダイアログを閉じて、新規登録から再度メールを送信してください。';
  }
  if (code == 409) return '既に登録済みです。サインインしてください。';
  if (code >= 500) return 'サーバが一時的に利用できません。しばらくしてから再試行してください。';
  if (code == 400) return '登録に失敗しました: ${body.isEmpty ? "不明" : body}';
  return '予期しないエラー (HTTP $code) ${body.isEmpty ? "" : "— $body"}';
}

/// HTTP / ネットワーク例外を人間向けメッセージに変換する。
String humanizeError(Object e) {
  final msg = e.toString();
  if (msg.contains('TimeoutException')) {
    return 'タイムアウトしました。インターネット接続を確認してください。';
  }
  if (msg.contains('SocketException') || msg.contains('Failed host lookup')) {
    return 'ネットワークに接続できません。';
  }
  if (msg.contains('cancel') || msg.contains('Cancel')) {
    return 'キャンセルされました。';
  }
  return msg.replaceFirst('Exception: ', '');
}
