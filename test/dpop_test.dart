// デフォルト ES256 実装は pointycastle (Pure Dart) なので `dart test` で動く。
// cryptography 版 (CryptographyEs256DpopKey) は Flutter 環境必須なので別途
// integration_test で確認する。

import 'dart:convert';

import 'package:dart_dpop/dart_dpop.dart';
import 'package:test/test.dart';

String _padBase64(String s) {
  final padding = (4 - s.length % 4) % 4;
  return s + ('=' * padding);
}

Map<String, dynamic> _decodeJwtPart(String part) =>
    jsonDecode(utf8.decode(base64Url.decode(_padBase64(part))))
        as Map<String, dynamic>;

void main() {
  group('Es256DpopKey', () {
    test('generates a valid EC P-256 JWK', () async {
      final key = await Es256DpopKey.generate();
      final jwk = await key.publicJwk();
      expect(jwk['kty'], 'EC');
      expect(jwk['crv'], 'P-256');
      expect(jwk['x'], isA<String>());
      expect(jwk['y'], isA<String>());
    });

    test('JKT is deterministic for the same key', () async {
      final key = await Es256DpopKey.generate();
      final jkt1 = await key.jkt;
      final jkt2 = await key.jkt;
      expect(jkt1, equals(jkt2));
    });

    test('different keys produce different JKTs', () async {
      final k1 = await Es256DpopKey.generate();
      final k2 = await Es256DpopKey.generate();
      expect(await k1.jkt, isNot(equals(await k2.jkt)));
    });

    test('algorithm is ES256', () async {
      final key = await Es256DpopKey.generate();
      expect(key.algorithm, DpopAlgorithm.es256);
      expect(key.algorithm.joseName, 'ES256');
    });
  });

  group('DpopProofGenerator', () {
    test('produces a 3-part JWT with dpop+jwt typ', () async {
      final key = await Es256DpopKey.generate();
      final gen = DpopProofGenerator(key: key);
      final proof = await gen.createProof(
        htm: 'POST',
        htu: 'https://example.com/token',
      );
      final parts = proof.split('.');
      expect(parts.length, 3);
      final header = _decodeJwtPart(parts[0]);
      expect(header['typ'], 'dpop+jwt');
      expect(header['alg'], 'ES256');
      expect(header['jwk']['kty'], 'EC');
      final payload = _decodeJwtPart(parts[1]);
      expect(payload['htm'], 'POST');
      expect(payload['htu'], 'https://example.com/token');
      expect(payload['iat'], isA<int>());
      expect(payload['jti'], isA<String>());
      expect(payload['ath'], isNull);
      expect(payload['nonce'], isNull);
    });

    test('htm is normalized to uppercase', () async {
      final gen =
          DpopProofGenerator(key: await Es256DpopKey.generate());
      final proof = await gen.createProof(
        htm: 'get',
        htu: 'https://example.com/x',
      );
      final payload = _decodeJwtPart(proof.split('.')[1]);
      expect(payload['htm'], 'GET');
    });

    test('ath claim is set when accessToken provided', () async {
      final gen =
          DpopProofGenerator(key: await Es256DpopKey.generate());
      final proof = await gen.createProof(
        htm: 'GET',
        htu: 'https://example.com/me',
        accessToken: 'sometoken',
      );
      final payload = _decodeJwtPart(proof.split('.')[1]);
      expect(payload['ath'], isA<String>());
    });

    test('nonce claim is set when nonce provided', () async {
      final gen =
          DpopProofGenerator(key: await Es256DpopKey.generate());
      final proof = await gen.createProof(
        htm: 'POST',
        htu: 'https://example.com/token',
        nonce: 'srv-nonce',
      );
      final payload = _decodeJwtPart(proof.split('.')[1]);
      expect(payload['nonce'], 'srv-nonce');
    });

    test('each call generates a fresh jti and iat', () async {
      final gen =
          DpopProofGenerator(key: await Es256DpopKey.generate());
      final p1 = await gen.createProof(htm: 'POST', htu: 'https://x');
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      final p2 = await gen.createProof(htm: 'POST', htu: 'https://x');
      final j1 = _decodeJwtPart(p1.split('.')[1]);
      final j2 = _decodeJwtPart(p2.split('.')[1]);
      expect(j1['jti'], isNot(equals(j2['jti'])));
      expect(j2['iat'], greaterThanOrEqualTo(j1['iat'] as int));
    });
  });

  group('MemoryDpopKeyStore', () {
    test('load returns null initially', () async {
      final store = MemoryDpopKeyStore();
      expect(await store.load(), isNull);
    });

    test('save and load round-trips', () async {
      final store = MemoryDpopKeyStore();
      final key = await Es256DpopKey.generate();
      await store.save(key);
      expect(await store.load(), equals(key));
    });

    test('clear removes the key', () async {
      final store = MemoryDpopKeyStore();
      await store.save(await Es256DpopKey.generate());
      await store.clear();
      expect(await store.load(), isNull);
    });
  });

  group('loadOrCreateDpopKey', () {
    test('creates a new key when store is empty', () async {
      final store = MemoryDpopKeyStore();
      var called = 0;
      final key = await loadOrCreateDpopKey(
        store: store,
        keyFactory: () async {
          called++;
          return Es256DpopKey.generate();
        },
      );
      expect(called, 1);
      expect(await store.load(), equals(key));
    });

    test('returns existing key without calling factory', () async {
      final store = MemoryDpopKeyStore();
      await store.save(await Es256DpopKey.generate());
      var called = 0;
      await loadOrCreateDpopKey(
        store: store,
        keyFactory: () async {
          called++;
          return Es256DpopKey.generate();
        },
      );
      expect(called, 0);
    });
  });
}
