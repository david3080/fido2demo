import 'package:shared_preferences/shared_preferences.dart';

/// 接続先 OP のベース URL。SharedPreferences に永続化し、次回起動時に復元する。
/// 未設定時は本番を既定値にする。
const defaultOpBase = 'https://oidc.sonrisa.co.jp';

const _prefsKey = 'op_base_override';

Future<String> loadOpBase() async {
  final prefs = await SharedPreferences.getInstance();
  final saved = prefs.getString(_prefsKey);
  if (saved == null || saved.isEmpty) return defaultOpBase;
  return saved;
}

Future<void> saveOpBase(String value) async {
  final prefs = await SharedPreferences.getInstance();
  final trimmed = value.trim();
  if (trimmed.isEmpty || trimmed == defaultOpBase) {
    // 既定値と同じ、または空なら保存自体を消す（不要な override を残さない）。
    await prefs.remove(_prefsKey);
    return;
  }
  await prefs.setString(_prefsKey, trimmed);
}
