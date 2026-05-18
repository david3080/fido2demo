import 'dart:convert';
import 'package:cryptography/cryptography.dart';

import 'dpop_algorithm.dart';

/// DPoP 用秘密鍵の抽象化。
///
/// 実装例:
/// - [Es256DpopKey]: pure Dart (cryptography パッケージ) ES256
/// - 将来: SecureEnclaveDpopKey (iOS Secure Enclave 連携)、KeystoreDpopKey (Android)
///
/// アルゴリズム + 公開鍵 JWK + 署名 + JKT thumbprint を提供する。
abstract class DpopKey {
  DpopAlgorithm get algorithm;

  /// 公開鍵を JWK (`Map<String, dynamic>`) 形式で返す (RFC 7517)。
  /// header の `jwk` field に埋め込まれる。
  Future<Map<String, dynamic>> publicJwk();

  /// JWS で要求される raw signature (例: ES256 は r||s の 64 bytes) を返す。
  Future<List<int>> sign(List<int> signingInput);

  /// JWK Thumbprint (RFC 7638) を返す。
  /// 公開鍵を canonical JSON にして SHA-256 + base64url。
  Future<String> get jkt;
}

/// ES256 (ECDSA P-256 + SHA-256) の DpopKey 実装。
class Es256DpopKey implements DpopKey {
  final EcKeyPair _keyPair;
  Es256DpopKey._(this._keyPair);

  /// 新規 ES256 key pair を生成する。
  static Future<Es256DpopKey> generate() async {
    final kp = await Ecdsa.p256(Sha256()).newKeyPair();
    return Es256DpopKey._(kp);
  }

  /// 既存の seed (private d) と公開鍵 (x, y) から復元する。
  /// 永続化された key の復元に使う。
  static Future<Es256DpopKey> fromSeed({
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
    return Es256DpopKey._(kp);
  }

  /// 既存の [EcKeyPair] をラップする (テスト用)。
  factory Es256DpopKey.fromKeyPair(EcKeyPair keyPair) =>
      Es256DpopKey._(keyPair);

  /// private/public 全要素を取り出す。永続化のために [DpopKeyStore] が呼び出す。
  Future<EcKeyPairData> extract() => _keyPair.extract();

  @override
  DpopAlgorithm get algorithm => DpopAlgorithm.es256;

  @override
  Future<Map<String, dynamic>> publicJwk() async {
    final pk = await _keyPair.extractPublicKey();
    return {
      'kty': 'EC',
      'crv': 'P-256',
      'x': _b64u(pk.x),
      'y': _b64u(pk.y),
    };
  }

  @override
  Future<List<int>> sign(List<int> signingInput) async {
    final sig =
        await Ecdsa.p256(Sha256()).sign(signingInput, keyPair: _keyPair);
    // cryptography パッケージは ECDSA signature を raw r||s (64 bytes) 形式で返す。
    // JOSE / JWS の ES256 はこれを期待するので DER 変換は不要。
    return sig.bytes;
  }

  @override
  Future<String> get jkt async {
    final jwk = await publicJwk();
    // canonical JSON: lexicographic key order, no whitespace (RFC 7638)
    final canonical =
        '{"crv":"${jwk['crv']}","kty":"${jwk['kty']}","x":"${jwk['x']}","y":"${jwk['y']}"}';
    final hash = await Sha256().hash(utf8.encode(canonical));
    return _b64u(hash.bytes);
  }
}

String _b64u(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');
