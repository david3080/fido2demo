import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oidc/oidc.dart';
import '../ciba_request.dart';
import '../providers.dart';
import 'approval_dialog.dart';
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
  int _tabIndex = 0; // 0=承認インボックス, 1=プロフィール

  @override
  void initState() {
    super.initState();
    // コールド起動 (getInitialMessage/getInitialLink) の値は runApp 前に sink へ
    // 入るため provider の初期 state に既に乗っており、ref.listen は「変化」が無く
    // 発火しない。初期 state を一度だけ拾ってダイアログを出す。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final pending = ref.read(pendingApprovalProvider);
      if (pending != null) _showApproval(pending);
      final token = ref.read(magicLinkTokenProvider);
      if (token != null) _showMagicLink(token);
    });
  }

  void _showApproval(PendingApproval pending) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ApprovalDialog(pending: pending),
    ).whenComplete(() => ref.read(pendingApprovalProvider.notifier).reset());
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
    // 起動後の CIBA 承認要求 (null→値) でダイアログを出し、閉じたらシンクを空に戻す。
    ref.listen<PendingApproval?>(pendingApprovalProvider, (prev, next) {
      if (next != null && prev == null) _showApproval(next);
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
              title: Text(_tabIndex == 0 ? '承認' : 'プロフィール'),
              automaticallyImplyLeading: false,
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
                  icon: Icon(Icons.person_outline),
                  selectedIcon: Icon(Icons.person),
                  label: 'プロフィール',
                ),
              ],
            ),
    );
  }
}
