# dart_dpop

Reusable Dart implementation of **DPoP** (Demonstrating Proof of Possession, [RFC 9449](https://datatracker.ietf.org/doc/rfc9449/)) for OAuth 2.0 / OIDC clients, including FAPI 2.0.

Designed after `oidc-client-ts` (TypeScript), AppAuth-iOS (Swift), and AppAuth-Android (Kotlin) patterns:

- **Algorithm abstraction** (currently ES256, expandable to EdDSA / RS256)
- **Pluggable KeyStore** (in-memory default; app provides SecureStorage / Secure Enclave / Keystore)
- **Proof Generator** for low-level use (tests, manual flows)
- **HTTP client middleware** (`DpopHttpClient extends http.BaseClient`) with auto nonce retry

## Why DPoP

OAuth `Bearer` access tokens are vulnerable to token theft (a stolen token can be replayed by anyone). DPoP binds each access token to a client-held key pair so that a stolen token alone is useless without the matching private key. Required by **FAPI 2.0** for sender-constrained tokens.

## Install

```yaml
dependencies:
  dart_dpop:
    git:
      url: https://github.com/david3080/dart_dpop.git
      ref: main
```

> **Note**: depends on the `cryptography` package, whose ES256 (`Ecdsa.p256`) requires a Flutter (iOS / Android / Web) runtime; pure Dart VM is unsupported. Tests are tagged `flutter` and should be run from a Flutter app's `integration_test`.

## Usage

### Low-level: generate a proof JWT manually

```dart
import 'package:dart_dpop/dart_dpop.dart';

final key = await Es256DpopKey.generate();
final generator = DpopProofGenerator(key: key);

final tokenProof = await generator.createProof(
  htm: 'POST',
  htu: 'https://op.example.com/token',
);

final apiProof = await generator.createProof(
  htm: 'GET',
  htu: 'https://api.example.com/me',
  accessToken: accessToken,
);

final jkt = await key.jkt;
```

### High-level: drop-in HTTP client with auto nonce retry

```dart
import 'package:dart_dpop/dart_dpop.dart';

final key = await Es256DpopKey.generate();
final client = DpopHttpClient(
  generator: DpopProofGenerator(key: key),
  accessTokenProvider: () async => currentAccessToken,
);

final response = await client.get(Uri.parse('https://api.example.com/me'));
// → 401 + DPoP-Nonce challenge では自動で nonce を含めて再試行
```

### Pluggable key persistence

```dart
import 'package:dart_dpop/dart_dpop.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStorageDpopKeyStore implements DpopKeyStore {
  final FlutterSecureStorage _storage;
  SecureStorageDpopKeyStore(this._storage);

  @override
  Future<DpopKey?> load() async {
    // ... read base64-encoded {d, x, y} → Es256DpopKey.fromSeed(...)
  }

  @override
  Future<void> save(DpopKey key) async {
    if (key is Es256DpopKey) {
      final data = await key.extract();
      // ... write {d: ..., x: ..., y: ...} as base64
    }
  }

  @override
  Future<void> clear() => _storage.delete(key: 'dpop_key');
}

final key = await loadOrCreateDpopKey(
  store: SecureStorageDpopKeyStore(FlutterSecureStorage()),
  keyFactory: () => Es256DpopKey.generate(),
);
```

## Reference designs

Inspired by:

- [oidc-client-ts (TypeScript)](https://github.com/authts/oidc-client-ts) — `DpopStore` interface, `UserManager.dpopProof()`
- [openid-client (Node.js)](https://github.com/panva/openid-client) — FAPI 2.0 conformant DPoP support
- AppAuth-iOS (Swift) + Secure Enclave / CryptoKit — platform keystore for private key
- AppAuth-Android (Kotlin) + Android Keystore + StrongBox — same on Android

## Future work

- EdDSA (Ed25519) and RS256 support
- Secure Enclave / Android Keystore bindings via platform plugin
- DPoP-bound refresh token flow helpers
- `bind_authorization_code` (= `dpop_jkt` in authorization request)
- Conformance tests against FAPI 2.0 profiles

## License

MIT
