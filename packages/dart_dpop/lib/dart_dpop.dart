/// Reusable Dart implementation of DPoP (Demonstrating Proof of Possession, RFC 9449).
///
/// Designed after oidc-client-ts (TypeScript), AppAuth-iOS (Swift), and
/// AppAuth-Android (Kotlin) patterns:
/// - **Algorithm abstraction** (currently ES256, expandable to EdDSA / RS256)
/// - **Pluggable KeyStore** (in-memory default; app provides SecureStorage /
///   Secure Enclave / Keystore)
/// - **Proof Generator** for low-level use (tests, manual flows)
/// - **HTTP client middleware** (`DpopHttpClient extends http.BaseClient`)
///   with auto nonce retry
///
/// Default ES256 implementation: pointycastle (Pure Dart, runs on VM / Flutter / Web).
/// Alternative: cryptography (Flutter only, ready for HW HSM via cryptography_flutter).
library;

export 'src/dpop_algorithm.dart';
export 'src/dpop_key.dart';
export 'src/dpop_key_store.dart';
export 'src/dpop_proof.dart';
export 'src/dpop_http_client.dart';
export 'src/impl/es256_pointycastle.dart';
export 'src/impl/es256_cryptography.dart';
