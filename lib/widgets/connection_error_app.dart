import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';
import 'settings_page.dart';

/// 起動時の OP 接続（discovery 文書取得）に失敗した場合のフォールバック画面。
/// oidcManagerProvider 等は未初期化のため通常の MyApp は組み立てられないが、
/// opBaseProvider だけは override できるので、設定画面から接続先を直せるようにする。
/// これが無いと、到達不能なドメインを設定した瞬間に次回起動が白画面のまま詰む。
class ConnectionErrorApp extends StatelessWidget {
  const ConnectionErrorApp({super.key, required this.opBase, required this.error});
  final String opBase;
  final Object? error;

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      overrides: [opBaseProvider.overrideWithValue(opBase)],
      child: MaterialApp(
        title: 'fido2demo',
        theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo)),
        home: Scaffold(
          appBar: AppBar(title: const Text('接続エラー')),
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.cloud_off, size: 48, color: Colors.redAccent),
                  const SizedBox(height: 16),
                  Text(
                    '接続先 ($opBase) に接続できませんでした。',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      '$error',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(builder: (_) => const SettingsPage()),
                    ),
                    child: const Text('接続先設定を開く'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
