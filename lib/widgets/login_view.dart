import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../error_messages.dart';
import '../providers.dart';
import '../registration_service.dart';
import '../ui_shared.dart';
import '../validators.dart';

class LoginView extends ConsumerStatefulWidget {
  const LoginView({super.key});

  @override
  ConsumerState<LoginView> createState() => _LoginViewState();
}

class _LoginViewState extends ConsumerState<LoginView> {
  bool _busy = false;

  Future<void> _login() async {
    setState(() => _busy = true);
    try {
      // prompt=login: 既存の OIDC session cookie で skip させず必ず再認証。
      // oidc-provider 9 は select_account を未サポートのため login を使う。
      // 結果として Conditional UI が走り、複数 Passkey 登録時は iOS の
      // 選択 sheet で候補から選べるようになる。
      await ref.read(oidcManagerProvider).loginAuthorizationCodeFlow(
        options: loginOptions,
        promptOverride: const ['login'],
      );
    } catch (e) {
      if (isUserCancelledLogin(e) || !mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ログインに失敗しました。もう一度お試しください。')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.fingerprint, size: 72),
          const SizedBox(height: 24),
          const Text('Passkey でサインイン'),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _busy ? null : _login,
            icon: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.login),
            label: const Text('サインイン'),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _busy ? null : () => _openRegisterEmail(context),
            icon: const Icon(Icons.mail_outline),
            label: const Text('新規登録 (メアドで)'),
          ),
        ],
      ),
    );
  }

  void _openRegisterEmail(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (_) => const RegisterEmailDialog(),
    );
  }
}

/// 新規登録: メアド入力 → /api/register/email-challenge を呼んで Magic Link 送信
class RegisterEmailDialog extends ConsumerStatefulWidget {
  const RegisterEmailDialog({super.key});
  @override
  ConsumerState<RegisterEmailDialog> createState() => _RegisterEmailDialogState();
}

class _RegisterEmailDialogState extends ConsumerState<RegisterEmailDialog> {
  final _controller = TextEditingController();
  bool _busy = false;
  String? _error;
  bool _sent = false;

  Future<void> _send() async {
    final email = _controller.text.trim().toLowerCase();
    if (email.isEmpty) {
      setState(() => _error = 'メールアドレスを入力してください');
      return;
    }
    if (email.length > 254) {
      setState(() => _error = 'メールアドレスが長すぎます (254 文字以内)');
      return;
    }
    if (!isValidEmail(email)) {
      setState(() => _error = 'メールアドレスの形式が正しくありません (例: name@example.com)');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(registrationServiceProvider).sendEmailChallenge(email);
      if (mounted) setState(() => _sent = true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = humanizeError(e);
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_sent) {
      return AlertDialog(
        title: const Text('メールを送信しました'),
        content: const Text(
          '受信箱でメール内の「アプリで開く」ボタンをタップしてください。\n'
          '有効期限は 30 分です。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('閉じる'),
          ),
        ],
      );
    }
    return AlertDialog(
      title: const Text('新規登録'),
      // SingleChildScrollView でラップして、キーボード表示時に AlertDialog の
      // content が縮んで error 文字が actions ボタンと重なる問題を回避する。
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('メールアドレスを入力してください。確認メールを送信します。'),
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              enabled: !_busy,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              decoration: const InputDecoration(
                hintText: 'you@example.com',
                border: OutlineInputBorder(),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  border: Border.all(color: Colors.red.shade300),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  _error!,
                  style: TextStyle(color: Colors.red.shade700, fontSize: 13),
                ),
              ),
              const SizedBox(height: 4),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('キャンセル'),
        ),
        FilledButton(
          onPressed: _busy ? null : _send,
          child: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('送信'),
        ),
      ],
    );
  }
}
