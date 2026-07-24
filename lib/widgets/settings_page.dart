import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../op_base_settings.dart';
import '../providers.dart';

/// 接続先 OP のドメイン切り替え画面。変更は次回起動時から反映されるため、
/// 保存後はアプリを手動で完全終了→再起動するよう案内する
/// （iOS はアプリ自身によるプロセス終了を許可していないため）。
class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  late final TextEditingController _controller;
  bool _saving = false;

  static const _presets = {
    '本番': defaultOpBase,
    'テスト': 'https://test.sonrisa.co.jp',
  };

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: ref.read(opBaseProvider));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    await saveOpBase(_controller.text);
    if (!mounted) return;
    setState(() => _saving = false);
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('保存しました'),
        content: const Text(
          '次回起動時から新しい接続先が使われます。'
          'アプリを完全に終了してから開き直してください。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final current = ref.watch(opBaseProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('接続先設定')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('現在の接続先: $current', style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              decoration: const InputDecoration(
                labelText: '接続先 URL',
                hintText: 'https://oidc.sonrisa.co.jp',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.url,
              autocorrect: false,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: _presets.entries
                  .map(
                    (e) => ActionChip(
                      label: Text('${e.key} (${e.value})'),
                      onPressed: () => setState(() => _controller.text = e.value),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('保存'),
            ),
          ],
        ),
      ),
    );
  }
}
