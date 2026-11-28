import 'dpop_key.dart';

/// DPoP private key の永続化を抽象する。
///
/// oidc-client-ts の `DPoPStore` に相当。iOS Secure Enclave / Android Keystore /
/// flutter_secure_storage 等の各種 backend を pluggable にする。
///
/// 永続化しない場合 ([MemoryDpopKeyStore]) はアプリ再起動で key が消えるため、
/// 既存の access_token (cnf.jkt 付き) は invalid になる。
abstract class DpopKeyStore {
  /// 保存済みの key を取り出す。存在しなければ null。
  Future<DpopKey?> load();

  /// key を保存する。既存があれば上書き。
  Future<void> save(DpopKey key);

  /// 保存済み key を削除する。
  Future<void> clear();
}

/// In-memory KeyStore。プロセス内 cache、アプリ再起動で消える。
/// 単純なテスト用途や、永続化が不要な短期セッションで使う。
class MemoryDpopKeyStore implements DpopKeyStore {
  DpopKey? _key;

  @override
  Future<DpopKey?> load() async => _key;

  @override
  Future<void> save(DpopKey key) async {
    _key = key;
  }

  @override
  Future<void> clear() async {
    _key = null;
  }
}

/// KeyStore から key を取り出す or 新規生成するヘルパー。
/// アプリ初回起動時に [keyFactory] で新規 key を作って [store] に保存し、
/// 2 回目以降は [store] から復元する典型パターン。
Future<DpopKey> loadOrCreateDpopKey({
  required DpopKeyStore store,
  required Future<DpopKey> Function() keyFactory,
}) async {
  final existing = await store.load();
  if (existing != null) return existing;
  final fresh = await keyFactory();
  await store.save(fresh);
  return fresh;
}
