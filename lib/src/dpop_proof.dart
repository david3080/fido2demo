import 'dart:convert';
import 'dart:math';
import 'package:cryptography/cryptography.dart';

import 'dpop_algorithm.dart';
import 'dpop_key.dart';

/// DPoP proof JWT を生成する低レベル API。
///
/// 1 つの [DpopKey] を共有して、各リクエストごとに [createProof] を呼ぶ。
/// HTTP クライアント統合は [DpopHttpClient] を使うほうが便利。
class DpopProofGenerator {
  final DpopKey key;
  DpopProofGenerator({required this.key});

  /// DPoP proof JWT (compact JWS) を生成する。
  ///
  /// - [htm]: HTTP method (内部で大文字化)
  /// - [htu]: HTTP URI (query/fragment は spec 上含めない方が安全)
  /// - [accessToken]: 渡すと `ath` claim (= base64url(SHA-256(token))) を追加。
  ///   resource access (リソースサーバへの request) では必須。
  /// - [nonce]: 渡すと `nonce` claim を追加。AS / RS が `DPoP-Nonce` challenge を
  ///   返したときに [DpopHttpClient] が自動セットする。
  Future<String> createProof({
    required String htm,
    required String htu,
    String? accessToken,
    String? nonce,
  }) async {
    final jwk = await key.publicJwk();
    final header = {
      'typ': 'dpop+jwt',
      'alg': key.algorithm.joseName,
      'jwk': jwk,
    };
    final payload = <String, dynamic>{
      'htm': htm.toUpperCase(),
      'htu': htu,
      'iat': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      'jti': _randomJti(),
    };
    if (accessToken != null) {
      final h = await Sha256().hash(utf8.encode(accessToken));
      payload['ath'] = _b64u(h.bytes);
    }
    if (nonce != null) payload['nonce'] = nonce;

    final headerB64 = _b64u(utf8.encode(jsonEncode(header)));
    final payloadB64 = _b64u(utf8.encode(jsonEncode(payload)));
    final signingInput = utf8.encode('$headerB64.$payloadB64');
    final signature = await key.sign(signingInput);
    final sigB64 = _b64u(signature);
    return '$headerB64.$payloadB64.$sigB64';
  }

  String _randomJti() {
    final r = Random.secure();
    final bytes = List<int>.generate(16, (_) => r.nextInt(256));
    return _b64u(bytes);
  }
}

String _b64u(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');
