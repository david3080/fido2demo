import 'dart:convert';
import 'package:cryptography/cryptography.dart';

/// DPoP 用の ES256 (P-256 + SHA-256) 鍵ペア。
///
/// 通常はアプリ起動時に [generate] で新規生成して in-memory 保持するか、
/// 既存の private key を [fromSeed] で復元する。
/// SecureStorage への永続化はライブラリでは扱わず、利用側で seed (private d) を
/// 取り出して保存・復元する設計にしている。
class DpopKey {
  final EcKeyPair keyPair;
  DpopKey._(this.keyPair);

  /// 新規 ES256 key pair を生成する。
  static Future<DpopKey> generate() async {
    final kp = await Ecdsa.p256(Sha256()).newKeyPair();
    return DpopKey._(kp);
  }

  /// 既存の [EcKeyPair] をラップする (テストや復元用)。
  factory DpopKey.fromKeyPair(EcKeyPair keyPair) => DpopKey._(keyPair);

  /// private key の seed (= d) を取り出して保存できるようにする。
  /// 復元する際は [restoreFromSeed] に渡す。
  Future<List<int>> exportSeed() async {
    final data = await keyPair.extract();
    return data.d;
  }

  /// 保存済みの seed (d) と公開鍵 (x, y) から key pair を復元する。
  /// seed が破損していたり P-256 として無効な場合は例外。
  static Future<DpopKey> restoreFromSeed({
    required List<int> d,
    required List<int> x,
    required List<int> y,
  }) async {
    final kp = EcKeyPairData(
      d: d,
      x: x,
      y: y,
      type: KeyPairType.p256,
    );
    return DpopKey._(kp);
  }

  /// 公開鍵を JWK (RFC 7517) 形式 (`Map<String, String>`) で取得。
  Future<Map<String, String>> publicJwk() async {
    final pk = await keyPair.extractPublicKey();
    return {
      'kty': 'EC',
      'crv': 'P-256',
      'x': _b64u(pk.x),
      'y': _b64u(pk.y),
    };
  }

  /// JWK Thumbprint (RFC 7638) を返す。
  /// access_token の `cnf.jkt` と一致するかを resource server で検証する際に使う。
  Future<String> jkt() async {
    final jwk = await publicJwk();
    // 正規化: lexicographic order, no whitespace
    final canonical =
        '{"crv":"${jwk['crv']}","kty":"${jwk['kty']}","x":"${jwk['x']}","y":"${jwk['y']}"}';
    final hash = await Sha256().hash(utf8.encode(canonical));
    return _b64u(hash.bytes);
  }
}

String _b64u(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');
