import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../ciba_request.dart';
import '../providers.dart';
import 'mandate_view.dart';

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
      await ref.read(cibaApprovalServiceProvider).reject(widget.pending);
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
      await ref.read(cibaApprovalServiceProvider).approve(widget.pending);
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
    final hasMandate = (widget.pending.authorizationDetails ?? const []).isNotEmpty;
    return AlertDialog(
      // mandate がある = 「ログイン」ではなく「個別操作の承認」なのでタイトルを変える。
      title: Text(hasMandate ? '操作の承認' : 'ログイン承認'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${widget.pending.clientName} からの要求が届いています。'),
            if (hasMandate) ...[
              const SizedBox(height: 12),
              MandateView(details: widget.pending.authorizationDetails!),
            ] else if (widget.pending.bindingMessage.isNotEmpty) ...[
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
            // mandate がある場合でも binding_message を「補足」として小さく見せる。
            if (hasMandate && widget.pending.bindingMessage.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                widget.pending.bindingMessage,
                style: const TextStyle(fontSize: 12, color: Colors.black54),
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
