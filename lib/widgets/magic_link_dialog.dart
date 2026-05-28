import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:passkeys/authenticator.dart';
import 'package:passkeys/types.dart';
import '../error_messages.dart';
import '../providers.dart';
import '../ui_shared.dart';

/// Magic Link tap で起動 → token を verify → email 取得 → Passkey 登録 → OIDC ログイン
class MagicLinkDialog extends ConsumerStatefulWidget {
  const MagicLinkDialog({super.key, required this.token});
  final String token;
  @override
  ConsumerState<MagicLinkDialog> createState() => _MagicLinkDialogState();
}

class _MagicLinkDialogState extends ConsumerState<MagicLinkDialog> {
  bool _busy = false;
  String? _email;
  String? _verifiedToken;
  String? _error;
  String _status = 'メールアドレス確認中…';

  @override
  void initState() {
    super.initState();
    _verifyEmail();
  }

  Future<void> _verifyEmail() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final res = await http
          .post(
            Uri.parse('$opBase/oidc/register/verify-email'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'token': widget.token}),
          )
          .timeout(const Duration(seconds: 30));
      if (res.statusCode != 200) {
        throw Exception(explainRegistrationHttpError(res.statusCode, res.body));
      }
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      if (mounted) {
        setState(() {
          _email = body['email'] as String?;
          _verifiedToken = body['verified_token'] as String?;
          _status = '確認しました。Face ID で Passkey を作成してください。';
          _busy = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = humanizeError(e);
          _busy = false;
        });
      }
    }
  }

  Future<void> _registerPasskey() async {
    if (_verifiedToken == null) return;
    setState(() {
      _busy = true;
      _error = null;
      _status = 'Passkey を作成中…';
    });
    try {
      final optsRes = await http
          .post(
            Uri.parse('$opBase/oidc/register/passkey/options'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'token': _verifiedToken}),
          )
          .timeout(const Duration(seconds: 30));
      // ここが Face ID 起動前のプリチェック: 期限切れ等はこの 200/!=200 で先に弾かれる。
      if (optsRes.statusCode != 200) {
        throw Exception(explainRegistrationHttpError(optsRes.statusCode, optsRes.body));
      }
      final req = RegisterRequestType.fromJsonString(optsRes.body);
      final resp = await PasskeyAuthenticator().register(req);
      // passkeys の resp は {id,rawId,type,response:{clientDataJSON,attestationObject},...}。
      // Rust は {token, response:{clientDataJSON, attestationObject}} を受ける。
      final respMap = jsonDecode(resp.toJsonString()) as Map<String, dynamic>;
      final verifyRes = await http
          .post(
            Uri.parse('$opBase/oidc/register/passkey/verify'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'token': _verifiedToken,
              'response': respMap['response'],
            }),
          )
          .timeout(const Duration(seconds: 30));
      if (verifyRes.statusCode != 201) {
        throw Exception(explainRegistrationHttpError(verifyRes.statusCode, verifyRes.body));
      }
      if (!mounted) return;
      setState(() => _status = '登録完了。サインインします…');
      Navigator.of(context).pop();
      await ref.read(oidcManagerProvider).loginAuthorizationCodeFlow(
        options: loginOptions,
        promptOverride: const ['login'],
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = humanizeError(e);
          _busy = false;
          _status = 'エラーが発生しました';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Passkey 登録'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_email != null)
            Text('メアド: $_email', style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Row(
            children: [
              if (_busy)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              if (_busy) const SizedBox(width: 8),
              Expanded(child: Text(_status)),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            SelectableText(
              _error!,
              style: const TextStyle(color: Colors.red, fontSize: 12),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('キャンセル'),
        ),
        FilledButton.icon(
          onPressed: (_busy || _verifiedToken == null) ? null : _registerPasskey,
          icon: const Icon(Icons.fingerprint),
          label: const Text('Passkey 作成'),
        ),
      ],
    );
  }
}
