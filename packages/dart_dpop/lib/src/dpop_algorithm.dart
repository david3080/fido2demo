/// DPoP 署名アルゴリズム識別子。
///
/// RFC 9449 § 4.2 では「registered asymmetric digital signature algorithm」のみ許可、
/// `none` は明示禁止。Es256 が最も広く使われる (FAPI 2.0 / Auth0 / Keycloak 等)。
/// EdDSA / RS256 は将来拡張用に enum として予約しているが、現実装では未対応。
enum DpopAlgorithm {
  es256,
  // eddsa, rs256 等を将来追加
}

extension DpopAlgorithmJose on DpopAlgorithm {
  /// JOSE `alg` ヘッダ値。
  String get joseName {
    switch (this) {
      case DpopAlgorithm.es256:
        return 'ES256';
    }
  }
}
