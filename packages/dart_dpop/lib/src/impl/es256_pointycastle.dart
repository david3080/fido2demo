import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

import '../dpop_algorithm.dart';
import '../dpop_key.dart';

/// Pure Dart 実装の ES256 DpopKey。
///
/// pointycastle を使うので Dart VM / Flutter / Web のすべてで動く (= `dart test` で
/// 単体テスト可能)。Flutter native HSM (Secure Enclave / Keystore) は使わないので、
/// 高セキュリティ要件があれば cryptography 系 / 専用 plugin と差し替える。
class PointycastleEs256DpopKey implements Es256DpopKey {
  final ECPrivateKey _privKey;
  final ECPublicKey _pubKey;

  PointycastleEs256DpopKey._(this._privKey, this._pubKey);

  static Future<PointycastleEs256DpopKey> generate() async {
    final params = ECKeyGeneratorParameters(ECCurve_secp256r1());
    final keyGen = KeyGenerator('EC')
      ..init(ParametersWithRandom(params, _secureRandom()));
    final pair = keyGen.generateKeyPair();
    return PointycastleEs256DpopKey._(
      pair.privateKey as ECPrivateKey,
      pair.publicKey as ECPublicKey,
    );
  }

  /// d (private scalar)、x, y (公開鍵座標) から復元する。
  /// 永続化された key の復元用。
  static Future<PointycastleEs256DpopKey> fromSeed({
    required List<int> d,
    required List<int> x,
    required List<int> y,
  }) async {
    final curve = ECCurve_secp256r1();
    final priv = ECPrivateKey(
      _bytesToBigInt(d),
      curve,
    );
    final point = curve.curve.createPoint(_bytesToBigInt(x), _bytesToBigInt(y));
    final pub = ECPublicKey(point, curve);
    return PointycastleEs256DpopKey._(priv, pub);
  }

  /// d (32 bytes)、x (32 bytes)、y (32 bytes) を取り出す。永続化用。
  Map<String, List<int>> extractRaw() {
    return {
      'd': _bigIntTo32Bytes(_privKey.d!),
      'x': _bigIntTo32Bytes(_pubKey.Q!.x!.toBigInteger()!),
      'y': _bigIntTo32Bytes(_pubKey.Q!.y!.toBigInteger()!),
    };
  }

  @override
  DpopAlgorithm get algorithm => DpopAlgorithm.es256;

  @override
  Future<Map<String, dynamic>> publicJwk() async {
    return {
      'kty': 'EC',
      'crv': 'P-256',
      'x': _b64u(_bigIntTo32Bytes(_pubKey.Q!.x!.toBigInteger()!)),
      'y': _b64u(_bigIntTo32Bytes(_pubKey.Q!.y!.toBigInteger()!)),
    };
  }

  @override
  Future<List<int>> sign(List<int> signingInput) async {
    final signer = ECDSASigner(SHA256Digest())
      ..init(
        true,
        ParametersWithRandom(
          PrivateKeyParameter<ECPrivateKey>(_privKey),
          _secureRandom(),
        ),
      );
    final sig = signer.generateSignature(
      Uint8List.fromList(signingInput),
    ) as ECSignature;
    // JOSE/JWS の ES256 は raw r||s (32 + 32 = 64 bytes) 期待。
    // pointycastle は (r, s) BigInt ペアなので 32 bytes 固定長 raw に変換。
    final rBytes = _bigIntTo32Bytes(sig.r);
    final sBytes = _bigIntTo32Bytes(sig.s);
    return [...rBytes, ...sBytes];
  }

  @override
  Future<String> get jkt async {
    final jwk = await publicJwk();
    final canonical =
        '{"crv":"${jwk['crv']}","kty":"${jwk['kty']}","x":"${jwk['x']}","y":"${jwk['y']}"}';
    final hash = SHA256Digest().process(Uint8List.fromList(utf8.encode(canonical)));
    return _b64u(hash);
  }
}

// ---- helpers ----

SecureRandom _secureRandom() {
  final r = Random.secure();
  final seed = Uint8List.fromList(List<int>.generate(32, (_) => r.nextInt(256)));
  return FortunaRandom()..seed(KeyParameter(seed));
}

/// BigInt を 32 bytes big-endian にゼロパディング (P-256 の x/y/d/r/s 用)。
Uint8List _bigIntTo32Bytes(BigInt value) {
  // BigInt.toRadixString より byte 化が早いので手動で。
  final bytes = Uint8List(32);
  var v = value;
  for (var i = 31; i >= 0 && v > BigInt.zero; i--) {
    bytes[i] = (v & BigInt.from(0xff)).toInt();
    v = v >> 8;
  }
  return bytes;
}

BigInt _bytesToBigInt(List<int> bytes) {
  var v = BigInt.zero;
  for (final b in bytes) {
    v = (v << 8) | BigInt.from(b & 0xff);
  }
  return v;
}

String _b64u(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');
