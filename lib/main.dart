import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:oidc/oidc.dart';
import 'package:oidc_default_store/oidc_default_store.dart';

import 'firebase_options.dart';

final oidcManager = OidcUserManager.lazy(
  discoveryDocumentUri: OidcUtils.getOpenIdConfigWellKnownUri(
    Uri.parse('https://oidc.sonrisa.co.jp/oidc'),
  ),
  clientCredentials: const OidcClientAuthentication.none(clientId: 'mobile-rp'),
  store: OidcDefaultStore(),
  settings: OidcUserManagerSettings(
    scope: const ['openid', 'profile', 'email', 'offline_access'],
    redirectUri: Uri.parse('jp.co.sonrisa.fido2demo://callback'),
    postLogoutRedirectUri: Uri.parse('jp.co.sonrisa.fido2demo://logout'),
    // oidc パッケージは既定で userinfo を呼ばない。明示的に有効化する。
    userInfoSettings: const OidcUserInfoSettings(sendUserInfoRequest: true),
  ),
);

// iOS/macOS とも ASWebAuthenticationSession を使う。中で WebAuthn が iOS の
// ネイティブ Passkey API (Face ID) に委譲される。ephemeral mode を選び、
// iOS 18 でデフォルトブラウザが Chrome 等の場合にサードパーティ
// ブラウザのエンジンが選ばれる挙動を回避する (常に Safari エンジン)。
const _authOptions = OidcPlatformSpecificOptions(
  ios: OidcPlatformSpecificOptions_AppAuth_IosMacos(
    externalUserAgent: OidcAppAuthExternalUserAgent.ephemeralAsWebAuthenticationSession,
  ),
  macos: OidcPlatformSpecificOptions_AppAuth_IosMacos(
    externalUserAgent: OidcAppAuthExternalUserAgent.ephemeralAsWebAuthenticationSession,
  ),
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  // CIBA Authentication Device 用に通知許可をリクエスト (iOS)
  await FirebaseMessaging.instance.requestPermission();
  await oidcManager.init();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'fido2demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('fido2demo — OIDC + Passkey')),
      body: StreamBuilder<OidcUser?>(
        stream: oidcManager.userChanges(),
        initialData: oidcManager.currentUser,
        builder: (context, snapshot) {
          final user = snapshot.data;
          if (user == null) {
            return const LoginView();
          }
          return UserView(user: user);
        },
      ),
    );
  }
}

class LoginView extends StatefulWidget {
  const LoginView({super.key});

  @override
  State<LoginView> createState() => _LoginViewState();
}

class _LoginViewState extends State<LoginView> {
  bool _busy = false;

  Future<void> _login() async {
    setState(() => _busy = true);
    try {
      await oidcManager.loginAuthorizationCodeFlow(options: _authOptions);
    } catch (e) {
      // ユーザーが認証画面 (ASWebAuthenticationSession) を閉じた場合は
      // FlutterAppAuthUserCancelledException が伝播する。エラーではないので何も表示しない。
      final cancelled =
          e.toString().contains('FlutterAppAuthUserCancelledException');
      if (cancelled || !mounted) return;
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
        ],
      ),
    );
  }
}

class UserView extends StatelessWidget {
  const UserView({super.key, required this.user});

  final OidcUser user;

  @override
  Widget build(BuildContext context) {
    const encoder = JsonEncoder.withIndent('  ');
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _DataCard(title: 'subject', body: user.uid ?? 'N/A'),
        _DataCard(
          title: 'ID Token Claims',
          body: encoder.convert(user.claims.toJson()),
        ),
        _DataCard(
          title: 'UserInfo',
          body: encoder.convert(user.userInfo),
        ),
        // フェーズ2.2 Step1 デバッグ表示。後で OP に登録するロジックに置き換える。
        FutureBuilder<String?>(
          future: FirebaseMessaging.instance.getToken(),
          builder: (context, snap) => _DataCard(
            title: 'FCM Token (デバッグ表示)',
            body: snap.data ?? (snap.hasError ? 'error: ${snap.error}' : '取得中…'),
          ),
        ),
        const SizedBox(height: 8),
        FilledButton.tonalIcon(
          onPressed: () => oidcManager.logout(),
          icon: const Icon(Icons.logout),
          label: const Text('ログアウト'),
        ),
      ],
    );
  }
}

class _DataCard extends StatelessWidget {
  const _DataCard({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            SelectableText(
              body,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
