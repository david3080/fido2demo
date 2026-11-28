import 'dpop_algorithm.dart';
import 'impl/es256_pointycastle.dart';

/// DPoP 用秘密鍵の抽象化。
///
/// 実装は [Es256DpopKey] (= pointycastle 版がデフォルト) や、追加で
/// `CryptographyEs256DpopKey` (= Flutter HW HSM 連携の足場) を選べる。
/// 将来: EdDSA / RS256 / Secure Enclave / Keystore 実装などを追加可能。
abstract class DpopKey {
  DpopAlgorithm get algorithm;

  /// 公開鍵を JWK (`Map<String, dynamic>`) 形式で返す (RFC 7517)。
  /// proof JWT header の `jwk` field に埋め込まれる。
  Future<Map<String, dynamic>> publicJwk();

  /// JWS で要求される raw signature (例: ES256 は r||s の 64 bytes) を返す。
  Future<List<int>> sign(List<int> signingInput);

  /// JWK Thumbprint (RFC 7638) を返す。
  /// access_token の `cnf.jkt` と比較する resource server で使う。
  Future<String> get jkt;
}

/// ES256 (ECDSA P-256 + SHA-256) の DpopKey 共通 interface。
///
/// 既定 factory `Es256DpopKey.generate()` は **pointycastle 実装** ([PointycastleEs256DpopKey])
/// を返す (Pure Dart で動くため Dart VM / Flutter / Web すべてで動作)。
///
/// Flutter HW HSM 連携が必要な場合は `CryptographyEs256DpopKey()` を直接 instantiate
/// するか、独自実装をアプリ側で注入する。
abstract class Es256DpopKey implements DpopKey {
  /// 新規 ES256 key pair を生成する。デフォルトは pointycastle 実装。
  static Future<Es256DpopKey> generate() => PointycastleEs256DpopKey.generate();

  /// 既存の seed (d) と公開鍵 (x, y) から復元する。
  static Future<Es256DpopKey> fromSeed({
    required List<int> d,
    required List<int> x,
    required List<int> y,
  }) =>
      PointycastleEs256DpopKey.fromSeed(d: d, x: x, y: y);
}
