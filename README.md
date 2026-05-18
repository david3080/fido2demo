# dart_dpop

Reusable Dart implementation of **DPoP** (Demonstrating Proof of Possession, [RFC 9449](https://datatracker.ietf.org/doc/rfc9449/)) for OAuth 2.0 / OIDC clients.

## Why

OAuth `Bearer` access tokens are vulnerable to token theft (a stolen token can be replayed by anyone). DPoP binds each access token to a client-held key pair, so a stolen token alone cannot be used without the matching private key.

`dart_dpop` provides a minimal, dependency-light implementation suitable for:

- Flutter mobile apps acting as OAuth clients
- Dart CLI / server-side clients
- BFF (Backend for Frontend) consuming an OAuth-protected API

## Install

```yaml
dependencies:
  dart_dpop:
    git:
      url: https://github.com/david3080/dart_dpop.git
      ref: main
```

## Usage

```dart
import 'package:dart_dpop/dart_dpop.dart';

final key = await DpopKey.generate();
final proof = DpopProof(key);

// Token endpoint request
final dpopForToken = await proof.create(
  htm: 'POST',
  htu: 'https://op.example.com/token',
);

await http.post(
  Uri.parse('https://op.example.com/token'),
  headers: {
    'Content-Type': 'application/x-www-form-urlencoded',
    'DPoP': dpopForToken,
  },
  body: ...,
);

// Resource access (after getting access_token)
final dpopForApi = await proof.create(
  htm: 'GET',
  htu: 'https://api.example.com/me',
  accessToken: accessToken, // adds `ath` claim
);

await http.get(
  Uri.parse('https://api.example.com/me'),
  headers: {
    'Authorization': 'DPoP $accessToken', // not Bearer
    'DPoP': dpopForApi,
  },
);
```

## Persistence

The library does not handle storage. Persist the private key seed with `flutter_secure_storage` (or similar) and restore via `DpopKey.restoreFromSeed`:

```dart
final seed = await key.exportSeed();
await secureStorage.write(key: 'dpop_seed', value: base64Url.encode(seed));

// Later (app restart)
final seedB64 = await secureStorage.read(key: 'dpop_seed');
final restored = await DpopKey.restoreFromSeed(d: ..., x: ..., y: ...);
```

## License

MIT
