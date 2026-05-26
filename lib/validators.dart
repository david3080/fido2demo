/// メアド簡易形式チェック（RFC 完全準拠ではなく実用範囲）。
final RegExp _emailRegex = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

bool isValidEmail(String s) => s.length <= 254 && _emailRegex.hasMatch(s);
