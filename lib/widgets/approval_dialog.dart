import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:passkeys/authenticator.dart';
import 'package:passkeys/types.dart';
import '../ciba_request.dart';
import '../providers.dart';

class ApprovalDialog extends ConsumerStatefulWidget {
  const ApprovalDialog({super.key, required this.pending});
  final PendingApproval pending;
  @override
  ConsumerState<ApprovalDialog> createState() => _ApprovalDialogState();
}

class _ApprovalDialogState extends ConsumerState<ApprovalDialog> {
  bool _busy = false;
  String? _error;

  Future<void> _reject() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final accessToken = ref.read(oidcManagerProvider).currentUser?.token.accessToken;
      // DPoP クライアントが Bearer を DPoP に変換し proof を付与する。承認主体は
      // access token から特定される（サーバ側 ciba_actor、cookie 不要）。
      final res = await ref.read(dpopClientProvider).post(
        Uri.parse('$opBase/oidc/ciba/${widget.pending.authReqId}/reject'),
        headers: {'Authorization': 'Bearer $accessToken'},
      );
      if (res.statusCode != 204) {
        throw Exception('reject ${res.statusCode}: ${res.body}');
      }
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('拒否しました。要求元にも通知されます。')),
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _busy = false;
        });
      }
    }
  }

  Future<void> _approve() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final accessToken = ref.read(oidcManagerProvider).currentUser?.token.accessToken;
      // 1. OP から Passkey options を取得 (access token + DPoP, allowCredentials を含む)
      final optsRes = await ref.read(dpopClientProvider).post(
        Uri.parse('$opBase/oidc/ciba/${widget.pending.authReqId}/passkey-options'),
        headers: {'Authorization': 'Bearer $accessToken', 'Content-Type': 'application/json'},
        body: '{}',
      );
      if (optsRes.statusCode != 200) {
        throw Exception('options ${optsRes.statusCode}: ${optsRes.body}');
      }
      // 2. passkeys パッケージで iOS のネイティブ Passkey 認証 (Face ID)
      final req = AuthenticateRequestType.fromJsonString(optsRes.body);
      final resp = await PasskeyAuthenticator().authenticate(req);
      // 3. assertion を OP に送って承認完了。Rust は {id, response:{...}} を受け 200 を返す。
      final respMap = jsonDecode(resp.toJsonString()) as Map<String, dynamic>;
      final apprRes = await ref.read(dpopClientProvider).post(
        Uri.parse('$opBase/oidc/ciba/${widget.pending.authReqId}/approve'),
        headers: {'Authorization': 'Bearer $accessToken', 'Content-Type': 'application/json'},
        body: jsonEncode({'id': respMap['id'], 'response': respMap['response']}),
      );
      if (apprRes.statusCode != 200) {
        throw Exception('approve ${apprRes.statusCode}: ${apprRes.body}');
      }
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('承認しました。Mac でログインが完了するはずです。')),
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('ログイン承認'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${widget.pending.clientName} からのログイン要求が届いています。'),
          if (widget.pending.bindingMessage.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                border: Border.all(color: Colors.amber.shade400),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '内容を確認してください',
                    style: TextStyle(fontSize: 11, color: Colors.brown, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  SelectableText(
                    widget.pending.bindingMessage,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            'scope: ${widget.pending.scope}',
            style: const TextStyle(fontSize: 12, color: Colors.black54),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            SelectableText(
              _error!,
              style: const TextStyle(color: Colors.red, fontSize: 12),
            ),
            const SizedBox(height: 8),
            // エラー時でもダイアログから抜けられるようにする（401 等で操作不能を防ぐ）。
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('閉じる'),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : _reject,
          child: const Text('拒否'),
        ),
        FilledButton.icon(
          onPressed: _busy ? null : _approve,
          icon: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.fingerprint),
          label: const Text('承認 (Passkey)'),
        ),
      ],
    );
  }
}
