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
