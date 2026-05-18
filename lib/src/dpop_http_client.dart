import 'dart:async';

import 'package:http/http.dart' as http;

import 'dpop_proof.dart';

/// DPoP-aware HTTP クライアント。
///
/// 全 HTTP リクエストに自動で:
/// - DPoP proof JWT (`DPoP` ヘッダ) を付与
/// - access token がある場合 `Authorization: DPoP <token>` を付与 (RFC 9449 § 5)
/// - 401 + `DPoP-Nonce` challenge を受けたら nonce 付きで自動 retry
///
/// 設計は Auth0 / oidc-client-ts の `DpopFetch` パターンと iOS / Android の
/// HTTP interceptor pattern を融合。
class DpopHttpClient extends http.BaseClient {
  final DpopProofGenerator _generator;
  final Future<String?> Function() _accessTokenProvider;
  final http.Client _inner;
  final bool _ownsInner;
  final int _maxNonceRetries;

  /// origin (= scheme + host + port) ごとに最新の DPoP-Nonce を保存する。
  /// AS と RS で異なる nonce を要求するため origin 単位で分ける。
  final Map<String, String> _nonces = {};

  DpopHttpClient({
    required DpopProofGenerator generator,
    Future<String?> Function()? accessTokenProvider,
    http.Client? inner,
    int maxNonceRetries = 1,
  })  : _generator = generator,
        _accessTokenProvider = accessTokenProvider ?? (() async => null),
        _inner = inner ?? http.Client(),
        _ownsInner = inner == null,
        _maxNonceRetries = maxNonceRetries;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final accessToken = await _accessTokenProvider();
    final origin = _origin(request.url);
    var nonce = _nonces[origin];

    var attempt = 0;
    while (true) {
      final signed = await _sign(request, accessToken: accessToken, nonce: nonce);
      final response = await _inner.send(signed);

      // 最新の nonce をレスポンスから取り出して保存。
      final newNonce = _readNonce(response.headers);
      if (newNonce != null) _nonces[origin] = newNonce;

      // 401 + DPoP-Nonce のときだけ retry。
      if (response.statusCode == 401 &&
          newNonce != null &&
          newNonce != nonce &&
          attempt < _maxNonceRetries) {
        nonce = newNonce;
        attempt++;
        // 元レスポンスは捨てる (body を読まずに次へ)
        await response.stream.drain<void>();
        continue;
      }
      return response;
    }
  }

  Future<http.BaseRequest> _sign(
    http.BaseRequest original, {
    required String? accessToken,
    required String? nonce,
  }) async {
    final clone = _cloneRequest(original);
    final htm = original.method;
    final htu = _normalizeUrl(original.url);
    final proof = await _generator.createProof(
      htm: htm,
      htu: htu,
      accessToken: accessToken,
      nonce: nonce,
    );
    clone.headers['DPoP'] = proof;
    if (accessToken != null) {
      clone.headers['Authorization'] = 'DPoP $accessToken';
    }
    return clone;
  }

  /// `http.BaseRequest` のコピーを作る (本体だけシンプルなものに限定)。
  /// MultipartRequest 等のストリーム系は spec 上 1 回しか send できないため非対応。
  http.BaseRequest _cloneRequest(http.BaseRequest original) {
    if (original is http.Request) {
      final clone = http.Request(original.method, original.url)
        ..bodyBytes = original.bodyBytes
        ..encoding = original.encoding
        ..followRedirects = original.followRedirects;
      clone.headers.addAll(original.headers);
      return clone;
    }
    // Fallback: シンプル GET/DELETE を Request にラップ
    final clone = http.Request(original.method, original.url)
      ..followRedirects = original.followRedirects;
    clone.headers.addAll(original.headers);
    return clone;
  }

  String? _readNonce(Map<String, String> headers) {
    // case-insensitive (HTTP headers の lookup は kit によって lower-case)
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() == 'dpop-nonce') return entry.value;
    }
    return null;
  }

  String _origin(Uri url) =>
      '${url.scheme}://${url.host}${url.hasPort ? ':${url.port}' : ''}';

  String _normalizeUrl(Uri url) {
    final base = StringBuffer()
      ..write(url.scheme)
      ..write('://')
      ..write(url.host);
    if (url.hasPort) {
      base
        ..write(':')
        ..write(url.port);
    }
    base.write(url.path);
    return base.toString();
  }

  @override
  void close() {
    if (_ownsInner) _inner.close();
  }
}
