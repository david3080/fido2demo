import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../ciba_approval.dart';
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

  /// 承認/拒否のエラーを一貫処理する。期限切れ/処理済み(stale)はダイアログを閉じて
  /// 統一メッセージを出す（承認は無反応・拒否は偽成功、という不整合を無くす）。
  void _onActionError(Object e) {
    if (!mounted) return;
    if (e is CibaApprovalException && e.stale) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('この要求は期限切れ（または処理済み）です。')),
      );
      return;
    }
    setState(() {
      _error = e.toString();
      _busy = false;
    });
  }

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
      _onActionError(e);
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
      final msg = (widget.pending.authorizationDetails ?? const []).isNotEmpty
          ? '承認しました。エージェントに権限を委譲しました。'
          : '承認しました。Mac でサインインが完了します。';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg)),
      );
    } catch (e) {
      _onActionError(e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final details = widget.pending.authorizationDetails ?? const [];
    final hasMandate = details.isNotEmpty;
    final hasPayment = details.any((e) => e['type'] == 'payment');
    final titleText = hasPayment ? '支払いの承認' : (hasMandate ? '操作の承認' : 'サインインの承認');
    return AlertDialog(
      // mandate の有無・種別で「サインイン」か「委譲の承認」かを出し分ける。
      // カードから開く想定なので、操作せず閉じられるよう × を置く。
      title: Row(
        children: [
          Expanded(child: Text(titleText)),
          IconButton(
            icon: const Icon(Icons.close),
            tooltip: '閉じる',
            onPressed: _busy ? null : () => Navigator.of(context).pop(),
          ),
        ],
      ),
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
            if (hasMandate) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: const [
                  _SecChip(icon: Icons.fingerprint, label: 'パスキー承認'),
                  _SecChip(icon: Icons.filter_1, label: '単回'),
                  _SecChip(icon: Icons.shield_outlined, label: 'スコープ限定'),
                ],
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

/// 委譲の安全性を一目で示す小さなチップ（パスキー承認 / 単回 / スコープ限定）。
class _SecChip extends StatelessWidget {
  const _SecChip({required this.icon, required this.label});
  final IconData icon;
  final String label;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.indigo.shade50,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: Colors.indigo.shade700),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: Colors.indigo.shade700,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
