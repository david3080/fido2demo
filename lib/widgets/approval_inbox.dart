import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oidc/oidc.dart';
import '../ciba_request.dart';
import '../providers.dart';
import 'approval_dialog.dart';

/// 承認インボックス: 自分宛の pending CIBA 承認要求を一覧表示する受信箱。
/// プッシュ（pendingApprovalProvider）と /ciba/pending の両方で最新化し、
/// カードをタップすると既存の ApprovalDialog（パスキー承認）を開く。
class ApprovalInbox extends ConsumerStatefulWidget {
  const ApprovalInbox({super.key, required this.user});
  final OidcUser user;
  @override
  ConsumerState<ApprovalInbox> createState() => _ApprovalInboxState();
}

class _ApprovalInboxState extends ConsumerState<ApprovalInbox> {
  late Future<List<PendingApproval>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<PendingApproval>> _load() async {
    final at = widget.user.token.accessToken;
    if (at == null) return const [];
    final svc = ref.read(cibaPendingServiceProvider);
    if (svc == null) return const []; // OP が ciba_pending 未広告
    return svc.list(at);
  }

  void _refresh() {
    if (mounted) setState(() => _future = _load());
  }

  Future<void> _open(PendingApproval p) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: true, // カード起点なので操作せず閉じられてよい。
      builder: (_) => ApprovalDialog(pending: p),
    );
    _refresh(); // 承認/拒否/閉じる後に一覧を更新
  }

  @override
  Widget build(BuildContext context) {
    // プッシュで新規要求が来たら一覧を更新する。
    ref.listen<PendingApproval?>(pendingApprovalProvider, (prev, next) {
      if (next != null) _refresh();
    });
    return RefreshIndicator(
      onRefresh: () async => _refresh(),
      child: FutureBuilder<List<PendingApproval>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final items = snap.data ?? const <PendingApproval>[];
          if (items.isEmpty) {
            return ListView(
              children: const [
                SizedBox(height: 140),
                Center(child: Icon(Icons.inbox_outlined, size: 64, color: Colors.black26)),
                SizedBox(height: 12),
                Center(
                  child: Text('承認待ちの要求はありません',
                      style: TextStyle(color: Colors.black54)),
                ),
                SizedBox(height: 6),
                Center(
                  child: Text('下に引いて更新',
                      style: TextStyle(fontSize: 12, color: Colors.black38)),
                ),
              ],
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) =>
                _InboxCard(pending: items[i], onTap: () => _open(items[i])),
          );
        },
      ),
    );
  }
}

class _InboxCard extends StatelessWidget {
  const _InboxCard({required this.pending, required this.onTap});
  final PendingApproval pending;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final details = pending.authorizationDetails ?? const [];
    final payments =
        details.where((e) => e['type'] == 'payment').toList();
    final isPayment = payments.isNotEmpty;

    String summary;
    if (isPayment) {
      final e = payments.first;
      final amount = e['amount']?.toString() ?? '?';
      final currency = (e['currency'] as String?) ?? '';
      final merchant = (e['merchant'] as String?) ?? '';
      summary = '$amount $currency${merchant.isNotEmpty ? ' / $merchant' : ''}';
    } else if (pending.bindingMessage.isNotEmpty) {
      summary = pending.bindingMessage;
    } else {
      summary = 'scope: ${pending.scope}';
    }

    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor:
              isPayment ? Colors.green.shade50 : Colors.indigo.shade50,
          child: Icon(
            isPayment ? Icons.payments : Icons.verified_user,
            color: isPayment ? Colors.green.shade700 : Colors.indigo.shade700,
          ),
        ),
        title: Text(
          isPayment ? '支払いの承認' : '操作の承認',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(summary, maxLines: 2, overflow: TextOverflow.ellipsis),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
