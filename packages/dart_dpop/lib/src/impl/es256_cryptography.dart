import 'dart:convert';

import 'package:cryptography/cryptography.dart';

import '../dpop_algorithm.dart';
import '../dpop_key.dart';

/// `cryptography` パッケージ (Gohilla) 実装の ES256 DpopKey。
///
/// Flutter 環境 (iOS / Android / Web) でのみ動作。Pure Dart VM は ECDSA が
/// 未実装で `UnimplementedError`。Flutter HW HSM (Secure Enclave / Keystore)
/// 連携 (`cryptography_flutter` 併用) を将来狙う場合の足場。
class CryptographyEs256DpopKey implements Es256DpopKey {
  final EcKeyPair _keyPair;
  CryptographyEs256DpopKey._(this._keyPair);

  /// 新規 ES256 key pair を生成。Flutter 環境必須。
  static Future<CryptographyEs256DpopKey> generate() async {
    final kp = await Ecdsa.p256(Sha256()).newKeyPair();
    return CryptographyEs256DpopKey._(kp);
  }

  /// 既存の seed (d) と公開鍵 (x, y) から復元する。
  static Future<CryptographyEs256DpopKey> fromSeed({
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
    return CryptographyEs256DpopKey._(kp);
  }

  Future<EcKeyPairData> extractRaw() => _keyPair.extract();

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
    return sig.bytes;
  }

  @override
  Future<String> get jkt async {
    final jwk = await publicJwk();
    final canonical =
        '{"crv":"${jwk['crv']}","kty":"${jwk['kty']}","x":"${jwk['x']}","y":"${jwk['y']}"}';
    final hash = await Sha256().hash(utf8.encode(canonical));
    return _b64u(hash.bytes);
  }
}

String _b64u(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');
