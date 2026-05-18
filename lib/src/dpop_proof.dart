import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

import 'dpop_key.dart';

/// DPoP proof JWT 生成 (RFC 9449)。
///
/// 同じ [DpopKey] に対して 1 つだけ [DpopProof] を作って繰り返し [create] を呼ぶ
/// 想定。各呼び出しで `iat` と `jti` を新規生成するので per-request の proof を作れる。
class DpopProof {
  final DpopKey key;
  DpopProof(this.key);

  /// DPoP proof JWT を生成する。
  ///
  /// - [htm]: HTTP method (大文字に正規化)
  /// - [htu]: HTTP URI (query / fragment は spec 上含めない方が無難)
  /// - [accessToken]: 与えると `ath` claim (= base64url(SHA-256(access_token))) を追加。
  ///   resource access 時 (RS への request 等) は **必須**。token endpoint へは不要。
  /// - [nonce]: 与えると `nonce` claim を追加。AS が DPoP-Nonce challenge を返した時に対応。
  Future<String> create({
    required String htm,
    required String htu,
    String? accessToken,
    String? nonce,
  }) async {
    final jwk = await key.publicJwk();
    final header = {
      'typ': 'dpop+jwt',
      'alg': 'ES256',
      'jwk': jwk,
    };
    final payload = <String, dynamic>{
      'htm': htm.toUpperCase(),
      'htu': htu,
      'iat': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      'jti': _randomJti(),
    };
    if (accessToken != null) {
      final hash = await Sha256().hash(utf8.encode(accessToken));
      payload['ath'] = _b64u(hash.bytes);
    }
    if (nonce != null) payload['nonce'] = nonce;

    final headerB64 = _b64u(utf8.encode(jsonEncode(header)));
    final payloadB64 = _b64u(utf8.encode(jsonEncode(payload)));
    final signingInput = utf8.encode('$headerB64.$payloadB64');
    final signature =
        await Ecdsa.p256(Sha256()).sign(signingInput, keyPair: key.keyPair);
    // cryptography パッケージの ECDSA signature.bytes は raw r||s (64 bytes) =
    // JOSE/JWS の ES256 期待 format と一致する。DER 変換は不要。
    final sigB64 = _b64u(signature.bytes);
    return '$headerB64.$payloadB64.$sigB64';
  }

  String _randomJti() {
    final r = Random.secure();
    final bytes = List<int>.generate(16, (_) => r.nextInt(256));
    return _b64u(bytes);
  }
}

String _b64u(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');
