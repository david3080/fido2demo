import 'package:dart_dpop/dart_dpop.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:oidc/oidc.dart';

import 'ciba_approval.dart';
import 'ciba_request.dart';
import 'profile_service.dart';
import 'registration_service.dart';
import 'remote_cursor.dart';

const opBase = 'https://oidc.sonrisa.co.jp';

/// main() で初期化したインスタンスを override で注入する。
final oidcManagerProvider = Provider<OidcUserManager>(
  (ref) => throw UnimplementedError('override in main()'),
);
final dpopClientProvider = Provider<DpopHttpClient>(
  (ref) => throw UnimplementedError('override in main()'),
);

/// CIBA 承認/拒否はパスキー assertion 自体が本人性を証明するため、アプリへの
/// ログイン（access token）を要しない公開エンドポイント。ログアウト/コールド起動
/// でも動くよう、token に依存しない素の HTTP クライアントで呼ぶ。
final httpClientProvider = Provider<http.Client>((ref) {
  final c = http.Client();
  ref.onDispose(c.close);
  return c;
});

/// パスキー認証ポート（テストで差し替えるため Provider 経由で注入）。
final passkeyPortProvider = Provider<PasskeyPort>((ref) => const NativePasskey());

/// CIBA 承認/拒否サービス。公開エンドポイントなので素の httpClient を使う。
final cibaApprovalServiceProvider = Provider<CibaApprovalService>((ref) {
  return CibaApprovalService(
    client: ref.watch(httpClientProvider),
    passkey: ref.watch(passkeyPortProvider),
    opBase: opBase,
  );
});

/// プロフィール取得/保存・FCM token 登録。DPoP 付きクライアントを使う。
final profileServiceProvider = Provider<ProfileService>((ref) {
  return ProfileService(client: ref.watch(dpopClientProvider), opBase: opBase);
});

/// 新規登録メール送信。token 不要なので素の httpClient を使う。
final registrationServiceProvider = Provider<RegistrationService>((ref) {
  return RegistrationService(client: ref.watch(httpClientProvider), opBase: opBase);
});

/// 認証ユーザー。currentUser を seed してから userChanges() を流す
/// （旧 StreamBuilder の initialData 相当）。
final authUserProvider = StreamProvider<OidcUser?>((ref) async* {
  final m = ref.watch(oidcManagerProvider);
  yield m.currentUser;
  yield* m.userChanges();
});

// main() の FCM/Universal Link ハンドラが書き込む「保持付きシンク」。
// 注意(テスト): これらはモジュール global なので、widget テストで値を入れたら
// addTearDown で null に戻すこと（次のテストへ漏れる）。
// ValueNotifier なのでコールド起動 (getInitialMessage/Link) の値も保持され、
// Provider が後から購読しても取りこぼさない。別 isolate の ProviderContainer
// 共有を避けつつ宣言的 UI に供給するためのブリッジ。
final ValueNotifier<PendingApproval?> pendingApprovalSink = ValueNotifier(null);
final ValueNotifier<String?> magicLinkTokenSink = ValueNotifier(null);
final ValueNotifier<CursorCommand?> cursorCommandSink = ValueNotifier(null);

/// ValueNotifier シンクを Riverpod state にミラーする。reset() でシンクを空にする。
class _MirrorNotifier<T> extends Notifier<T?> {
  _MirrorNotifier(this._source);
  final ValueNotifier<T?> _source;

  @override
  T? build() {
    void update() => state = _source.value;
    _source.addListener(update);
    ref.onDispose(() => _source.removeListener(update));
    return _source.value;
  }

  void reset() => _source.value = null;
}

final pendingApprovalProvider =
    NotifierProvider<_MirrorNotifier<PendingApproval>, PendingApproval?>(
  () => _MirrorNotifier(pendingApprovalSink),
);
final magicLinkTokenProvider =
    NotifierProvider<_MirrorNotifier<String>, String?>(
  () => _MirrorNotifier(magicLinkTokenSink),
);
final cursorCommandProvider =
    NotifierProvider<_MirrorNotifier<CursorCommand>, CursorCommand?>(
  () => _MirrorNotifier(cursorCommandSink),
);
