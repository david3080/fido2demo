/// Reusable Dart implementation of DPoP (Demonstrating Proof of Possession, RFC 9449).
///
/// Designed for use with Flutter / Dart OAuth/OIDC clients (mobile app, BFF, CLI, etc.)
/// that need to send DPoP proof JWTs to token endpoints and DPoP-bound resource endpoints.
library;

export 'src/dpop_key.dart';
export 'src/dpop_proof.dart';
