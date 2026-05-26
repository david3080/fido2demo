import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oidc/oidc.dart';
import '../ciba_request.dart';
import '../providers.dart';
import 'approval_dialog.dart';
import 'cursor_overlay.dart';
import 'login_view.dart';
import 'magic_link_dialog.dart';
import 'user_view.dart';

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'fido2demo',
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo)),
      home: const HomePage(),
    );
  }
}

/// UI = f(状態)。認証ユーザー / CIBA 承認 / Magic Link を Riverpod から watch/listen し、
/// 画面とダイアログを宣言的に決める。
class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // CIBA 承認要求 (null→値) でダイアログを出し、閉じたらシンクを空に戻す。
    ref.listen<PendingApproval?>(pendingApprovalProvider, (prev, next) {
      if (next != null && prev == null) {
        showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (_) => ApprovalDialog(pending: next),
        ).whenComplete(() => ref.read(pendingApprovalProvider.notifier).reset());
      }
    });
    // Magic Link で起動 (null→値) で Passkey 登録ダイアログ。
    ref.listen<String?>(magicLinkTokenProvider, (prev, next) {
      if (next != null && prev == null) {
        showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (_) => MagicLinkDialog(token: next),
        ).whenComplete(() => ref.read(magicLinkTokenProvider.notifier).reset());
      }
    });
    // ログアウトしたらカーソル案内を消す。
    ref.listen<AsyncValue<OidcUser?>>(authUserProvider, (prev, next) {
      if (next.asData?.value == null) {
        ref.read(cursorCommandProvider.notifier).reset();
      }
    });

    final authUser = ref.watch(authUserProvider);
    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            authUser.when(
              data: (user) =>
                  user == null ? const LoginView() : UserView(user: user),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('エラー: $e')),
            ),
            // リモート支援: カーソル/ハイライトのオーバーレイ (タップは透過)
            const Positioned.fill(child: IgnorePointer(child: CursorOverlay())),
          ],
        ),
      ),
    );
  }
}
