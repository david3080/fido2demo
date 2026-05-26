import 'dart:convert';
import 'package:http/http.dart' as http;

class ProfileException implements Exception {
  ProfileException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// プロフィール編集対象のフィールド。サーバの profile JSON と相互変換する。
class ProfileData {
  ProfileData({this.name = '', this.nickname = '', this.gender = '', this.birthdate = ''});
  final String name;
  final String nickname;
  final String gender;
  final String birthdate;

  factory ProfileData.fromProfileJson(Map<String, dynamic> p) => ProfileData(
        name: (p['name'] as String?) ?? '',
        nickname: (p['nickname'] as String?) ?? '',
        gender: (p['gender'] as String?) ?? '',
        birthdate: (p['birthdate'] as String?) ?? '',
      );

  Map<String, dynamic> toJson() => {
        'name': name.trim(),
        'nickname': nickname.trim(),
        'gender': gender,
        'birthdate': birthdate.trim(),
      };
}

/// プロフィール取得/保存と FCM token 登録。client は DPoP 付き http.Client を注入する
/// （access token は呼び出し側が渡す）。
class ProfileService {
  ProfileService({required this.client, required this.opBase});
  final http.Client client;
  final String opBase;

  Uri get _profile => Uri.parse('$opBase/oidc/profile');

  /// 取得。200 以外は null（空で編集開始できる）。
  Future<ProfileData?> load(String accessToken) async {
    final res = await client.get(_profile, headers: {'Authorization': 'Bearer $accessToken'});
    if (res.statusCode != 200) return null;
    final m = jsonDecode(res.body) as Map<String, dynamic>;
    final p = (m['profile'] as Map?)?.cast<String, dynamic>() ?? const {};
    return ProfileData.fromProfileJson(p);
  }

  /// 保存。200 以外は例外。
  Future<void> save(String accessToken, ProfileData data) async {
    final res = await client.put(
      _profile,
      headers: {'Authorization': 'Bearer $accessToken', 'Content-Type': 'application/json'},
      body: jsonEncode(data.toJson()),
    );
    if (res.statusCode != 200) {
      throw ProfileException('保存に失敗しました (HTTP ${res.statusCode})');
    }
  }

  /// CIBA 通知の宛先になる FCM token を登録。失敗は呼び出し側でベストエフォート扱い。
  Future<void> registerFcmToken(String accessToken, String fcmToken) async {
    await client.post(
      Uri.parse('$opBase/oidc/me/fcm-tokens'),
      headers: {'Authorization': 'Bearer $accessToken', 'Content-Type': 'application/json'},
      body: jsonEncode({'token': fcmToken, 'platform': 'ios'}),
    );
  }
}
