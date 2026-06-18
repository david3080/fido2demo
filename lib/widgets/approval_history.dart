import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oidc/oidc.dart';
import '../ciba_history_service.dart';
import '../providers.dart';

/// 承認履歴: 過去の承認/拒否/期限切れを新しい順に表示する（読み取り専用の監査ビュー）。
class ApprovalHistory extends ConsumerStatefulWidget {
  const ApprovalHistory({super.key, required this.user});
  final OidcUser user;
  @override
  ConsumerState<ApprovalHistory> createState() => _ApprovalHistoryState();
}

class _ApprovalHistoryState extends ConsumerState<ApprovalHistory> {
  late Future<List<CibaHistoryItem>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<CibaHistoryItem>> _load() async {
    final at = widget.user.token.accessToken;
    if (at == null) return const [];
    final svc = ref.read(cibaHistoryServiceProvider);
    if (svc == null) return const [];
    return svc.list(at);
  }

  void _refresh() {
    if (mounted) setState(() => _future = _load());
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async => _refresh(),
      child: FutureBuilder<List<CibaHistoryItem>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final items = snap.data ?? const <CibaHistoryItem>[];
          if (items.isEmpty) {
            return ListView(
              children: const [
                SizedBox(height: 140),
                Center(child: Icon(Icons.history, size: 64, color: Colors.black26)),
                SizedBox(height: 12),
                Center(
                  child: Text('承認履歴はありません',
                      style: TextStyle(color: Colors.black54)),
                ),
              ],
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) => _HistoryCard(item: items[i]),
          );
        },
      ),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({required this.item});
  final CibaHistoryItem item;

  ({String label, Color color, IconData icon}) get _outcome {
    switch (item.outcome) {
      case 'approved':
        return (label: '承認済み', color: Colors.green, icon: Icons.check_circle);
      case 'denied':
        return (label: '拒否', color: Colors.red, icon: Icons.cancel);
      default:
        return (label: '期限切れ', color: Colors.grey, icon: Icons.schedule);
    }
  }

  String _when() {
    if (item.resolvedAt <= 0) return '';
    final t = DateTime.fromMillisecondsSinceEpoch(item.resolvedAt * 1000);
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'たった今';
    if (d.inHours < 1) return '${d.inMinutes}分前';
    if (d.inDays < 1) return '${d.inHours}時間前';
    return '${d.inDays}日前';
  }

  @override
  Widget build(BuildContext context) {
    final o = _outcome;
    final details = item.authorizationDetails ?? const [];
    final payments = details.where((e) => e['type'] == 'payment').toList();
    String summary;
    if (payments.isNotEmpty) {
      final e = payments.first;
      final amount = e['amount']?.toString() ?? '?';
      final currency = (e['currency'] as String?) ?? '';
      final merchant = (e['merchant'] as String?) ?? '';
      summary = '$amount $currency${merchant.isNotEmpty ? ' / $merchant' : ''}';
    } else if (item.bindingMessage.isNotEmpty) {
      summary = item.bindingMessage;
    } else {
      summary = 'scope: ${item.scope}';
    }

    return Card(
      child: ListTile(
        leading: Icon(o.icon, color: o.color),
        title: Row(
          children: [
            Text(o.label,
                style: TextStyle(fontWeight: FontWeight.w600, color: o.color)),
            const Spacer(),
            Text(_when(),
                style: const TextStyle(fontSize: 12, color: Colors.black45)),
          ],
        ),
        subtitle: Text(summary, maxLines: 2, overflow: TextOverflow.ellipsis),
      ),
    );
  }
}
