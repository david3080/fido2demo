/// OP の独自エンドポイント（OIDC 標準外）。
///
/// discovery (.well-known/openid-configuration) のベンダー名前空間
/// `custom_endpoints` から URL を取得し、アプリ内にパスをハードコードしない。
/// これにより OP 側でパスを改名してもアプリは無改修で追従できる。
///
/// 標準 OIDC エンドポイント（/authorize, /token, /userinfo, /jwks 等）は
/// oidc パッケージが discovery から自動解決するため、ここでは扱わない。
class OpEndpoints {
  const OpEndpoints({
    required this.signupEmailChallenge,
    required this.signupVerifyEmail,
    required this.signupPasskeyOptions,
    required this.signupPasskeyVerify,
    required this.profile,
    required this.fcmToken,
    required this.mandateConsume,
    this.cibaPending,
  });

  final Uri signupEmailChallenge;
  final Uri signupVerifyEmail;
  final Uri signupPasskeyOptions;
  final Uri signupPasskeyVerify;
  final Uri profile;
  final Uri fcmToken;
  final Uri mandateConsume;

  /// 承認インボックスが自分宛の pending CIBA を取得する URL。
  /// 旧 OP（discovery 未広告）でもアプリが落ちないよう任意扱い（null なら受信箱はプッシュのみ）。
  final Uri? cibaPending;

  /// discovery の生 JSON（OidcProviderMetadata.src）から構築する。
  /// 必要なフィールドが欠けていれば起動時に例外で落とす（fail-closed）。
  /// 誤ったパスへ DPoP リクエストを投げて静かに失敗するより、即座に気付けるようにする。
  factory OpEndpoints.fromDiscoverySrc(Map<String, dynamic> src) {
    final raw = src['custom_endpoints'];
    if (raw is! Map) {
      throw StateError(
        'discovery に custom_endpoints がありません（OP が古い可能性）。',
      );
    }
    Uri pick(String key) {
      final v = raw[key];
      if (v is! String || v.isEmpty) {
        throw StateError('discovery の custom_endpoints.$key がありません。');
      }
      return Uri.parse(v);
    }

    Uri? pickOptional(String key) {
      final v = raw[key];
      if (v is! String || v.isEmpty) return null;
      return Uri.parse(v);
    }

    return OpEndpoints(
      signupEmailChallenge: pick('signup_email_challenge'),
      signupVerifyEmail: pick('signup_verify_email'),
      signupPasskeyOptions: pick('signup_passkey_options'),
      signupPasskeyVerify: pick('signup_passkey_verify'),
      profile: pick('profile'),
      fcmToken: pick('fcm_token'),
      mandateConsume: pick('mandate_consume'),
      cibaPending: pickOptional('ciba_pending'),
    );
  }
}
