import 'package:flutter/material.dart';

/// RFC 9396 authorization_details を「同意の中身」として人間に見せる。
/// type ごとにビジュアルを分岐。未対応 type は素の JSON を fallback 表示。
class MandateView extends StatelessWidget {
  const MandateView({super.key, required this.details});
  final List<Map<String, dynamic>> details;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final m in details) ...[
          _entry(context, m),
          const SizedBox(height: 8),
        ],
      ],
    );
  }

  Widget _entry(BuildContext context, Map<String, dynamic> m) {
    final type = m['type'];
    switch (type) {
      case 'points':
        return _PointsMandate(entry: m);
      case 'payment':
        return _PaymentMandate(entry: m);
      default:
        return _RawMandate(entry: m);
    }
  }
}

/// ポイント使用 mandate. リーサポイント等のロイヤリティポイント用。
class _PointsMandate extends StatelessWidget {
  const _PointsMandate({required this.entry});
  final Map<String, dynamic> entry;

  @override
  Widget build(BuildContext context) {
    final amount = entry['amount']?.toString() ?? '?';
    final program = (entry['program'] as String?) ?? 'ポイント';
    final merchant = entry['merchant'] as String?;
    final actions = ((entry['actions'] as List?) ?? const []).cast<String>();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.deepPurple.shade50,
        border: Border.all(color: Colors.deepPurple.shade300),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.stars_rounded, size: 18, color: Colors.deepPurple.shade700),
              const SizedBox(width: 6),
              Text(
                '$program ポイントの使用',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.deepPurple.shade700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                amount,
                style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -1,
                ),
              ),
              const SizedBox(width: 4),
              const Text('PT', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ],
          ),
          if (merchant != null) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.storefront, size: 14, color: Colors.black54),
                const SizedBox(width: 4),
                Text('使用先: $merchant', style: const TextStyle(fontSize: 13)),
              ],
            ),
          ],
          if (actions.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'action: ${actions.join(", ")}',
              style: const TextStyle(fontSize: 11, color: Colors.black45),
            ),
          ],
        ],
      ),
    );
  }
}

/// 通貨決済 mandate（フェーズ3 で実装した payment 型）。
class _PaymentMandate extends StatelessWidget {
  const _PaymentMandate({required this.entry});
  final Map<String, dynamic> entry;

  @override
  Widget build(BuildContext context) {
    final amount = entry['amount']?.toString() ?? '?';
    final currency = (entry['currency'] as String?) ?? '';
    final merchant = entry['merchant'] as String?;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        border: Border.all(color: Colors.green.shade400),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.payments, size: 18, color: Colors.green.shade800),
              const SizedBox(width: 6),
              Text(
                '決済',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.green.shade800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                amount,
                style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -1,
                ),
              ),
              const SizedBox(width: 4),
              Text(currency, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ],
          ),
          if (merchant != null) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.storefront, size: 14, color: Colors.black54),
                const SizedBox(width: 4),
                Text('支払先: $merchant', style: const TextStyle(fontSize: 13)),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _RawMandate extends StatelessWidget {
  const _RawMandate({required this.entry});
  final Map<String, dynamic> entry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        border: Border.all(color: Colors.grey.shade400),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('type: ${entry['type']}',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          for (final e in entry.entries)
            if (e.key != 'type')
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  '${e.key}: ${e.value}',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
        ],
      ),
    );
  }
}
