/// リモート支援デモ: オペレータからの `type:'remote_cursor'` FCM data 通知で
/// 対象 widget にカーソル/ハイライトを出す。target はサーバ側 CURSOR_TARGETS と同じキー。
class CursorCommand {
  CursorCommand({required this.target, required this.label});
  final String target;
  final String label;
}

/// remote_cursor 通知の解釈結果。
sealed class RemoteCursorEvent {}

/// 関係ない通知 / 未知 target。何もしない。
class CursorIgnore extends RemoteCursorEvent {}

/// target='none' = 案内解除。表示中のカーソルを消す。
class CursorClear extends RemoteCursorEvent {}

/// 対象にカーソルを表示する。
class CursorShow extends RemoteCursorEvent {
  CursorShow(this.command);
  final CursorCommand command;
}

/// FCM data から remote_cursor イベントを解釈する。validTargets は表示先キー集合。
RemoteCursorEvent parseRemoteCursorEvent(
  Map<String, dynamic> data,
  Set<String> validTargets,
) {
  if (data['type'] != 'remote_cursor') return CursorIgnore();
  final target = data['target'] as String?;
  if (target == 'none') return CursorClear();
  if (target == null || !validTargets.contains(target)) return CursorIgnore();
  return CursorShow(
    CursorCommand(target: target, label: (data['label'] as String?) ?? ''),
  );
}
