import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oidc/oidc.dart';
import '../ciba_request.dart';
import '../providers.dart';
import 'approval_history.dart';
import 'approval_inbox.dart';
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
class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  int _tabIndex = 0; // 0=承認インボックス, 1=履歴, 2=プロフィール
  static const _titles = ['承認', '履歴', 'プロフィール'];

  @override
  void initState() {
    super.initState();
    // コールド起動 (getInitialMessage/getInitialLink) の値は runApp 前に sink へ
    // 入るため provider の初期 state に既に乗っており、ref.listen は「変化」が無く
    // 発火しない。初期 state を一度だけ拾って処理する。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (ref.read(pendingApprovalProvider) != null) _onPushApproval();
      final token = ref.read(magicLinkTokenProvider);
      if (token != null) _showMagicLink(token);
    });
  }

  /// push 受信時: モーダルは強制しない。承認タブ（インボックス）へ切り替え、通知する。
  /// インボックスは自身で pendingApprovalProvider を listen して一覧を更新する。
  /// 承認は「カードをタップ → ダイアログ」起点に統一（古い要求に強制操作させない）。
  void _onPushApproval() {
    if (!mounted) return;
    setState(() => _tabIndex = 0);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('新しい承認要求が届きました')),
    );
    ref.read(pendingApprovalProvider.notifier).reset();
  }

  void _showMagicLink(String token) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => MagicLinkDialog(token: token),
    ).whenComplete(() => ref.read(magicLinkTokenProvider.notifier).reset());
  }

  @override
  Widget build(BuildContext context) {
    // 起動後の CIBA 承認要求 (push) は承認タブへ誘導する（モーダルは強制しない）。
    ref.listen<PendingApproval?>(pendingApprovalProvider, (prev, next) {
      if (next != null) _onPushApproval();
    });
    // Magic Link で復帰 (null→値) で Passkey 登録ダイアログ。
    ref.listen<String?>(magicLinkTokenProvider, (prev, next) {
      if (next != null && prev == null) _showMagicLink(next);
    });
    // ログアウトしたらカーソル案内を消す。
    ref.listen<AsyncValue<OidcUser?>>(authUserProvider, (prev, next) {
      if (next.asData?.value == null) {
        ref.read(cursorCommandProvider.notifier).reset();
      }
    });

    final authUser = ref.watch(authUserProvider);
    final user = authUser.asData?.value;
    return Scaffold(
      // ログイン時は「承認デバイス」として承認/プロフィールのタブを出す。
      appBar: user == null
          ? null
          : AppBar(
              title: Text(_titles[_tabIndex]),
              automaticallyImplyLeading: false,
              actions: [
                IconButton(
                  icon: const Icon(Icons.logout),
                  tooltip: 'ログアウト',
                  // ブラウザを開く RP-initiated ログアウトではなくローカルでトークン破棄。
                  onPressed: () => ref.read(oidcManagerProvider).forgetUser(),
                ),
              ],
            ),
      body: SafeArea(
        child: Stack(
          children: [
            authUser.when(
              data: (u) => u == null
                  ? const LoginView()
                  : IndexedStack(
                      index: _tabIndex,
                      children: [
                        ApprovalInbox(user: u),
                        ApprovalHistory(user: u),
                        UserView(user: u),
                      ],
                    ),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('エラー: $e')),
            ),
            // リモート支援: カーソル/ハイライトのオーバーレイ (タップは透過)
            const Positioned.fill(child: IgnorePointer(child: CursorOverlay())),
          ],
        ),
      ),
      bottomNavigationBar: user == null
          ? null
          : NavigationBar(
              selectedIndex: _tabIndex,
              onDestinationSelected: (i) => setState(() => _tabIndex = i),
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.inbox_outlined),
                  selectedIcon: Icon(Icons.inbox),
                  label: '承認',
                ),
                NavigationDestination(
                  icon: Icon(Icons.history),
                  label: '履歴',
                ),
                NavigationDestination(
                  icon: Icon(Icons.person_outline),
                  selectedIcon: Icon(Icons.person),
                  label: 'プロフィール',
                ),
              ],
            ),
    );
  }
}
