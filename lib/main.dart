import 'dart:convert';
import 'dart:math' as math;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:oidc/oidc.dart';
import 'package:oidc_default_store/oidc_default_store.dart';
import 'package:passkeys/authenticator.dart';
import 'package:passkeys/types.dart';

import 'firebase_options.dart';

const _opBase = 'https://oidc.sonrisa.co.jp';

final oidcManager = OidcUserManager.lazy(
  discoveryDocumentUri: OidcUtils.getOpenIdConfigWellKnownUri(
    Uri.parse('$_opBase/oidc'),
  ),
  clientCredentials: const OidcClientAuthentication.none(clientId: 'mobile-rp'),
  store: OidcDefaultStore(),
  settings: OidcUserManagerSettings(
    scope: const ['openid', 'profile', 'email', 'offline_access'],
    redirectUri: Uri.parse('jp.co.sonrisa.fido2demo://callback'),
    postLogoutRedirectUri: Uri.parse('jp.co.sonrisa.fido2demo://logout'),
    userInfoSettings: const OidcUserInfoSettings(sendUserInfoRequest: true),
  ),
);

// ephemeral mode で iOS 18 のサードパーティブラウザ問題を回避し、常に Safari エンジンを使う。
const _authOptions = OidcPlatformSpecificOptions(
  ios: OidcPlatformSpecificOptions_AppAuth_IosMacos(
    externalUserAgent: OidcAppAuthExternalUserAgent.ephemeralAsWebAuthenticationSession,
  ),
  macos: OidcPlatformSpecificOptions_AppAuth_IosMacos(
    externalUserAgent: OidcAppAuthExternalUserAgent.ephemeralAsWebAuthenticationSession,
  ),
);

/// CIBA: Mac (Consumption Device) からの保留中認証要求。FCM 通知から復元する。
class PendingApproval {
  PendingApproval({required this.authReqId, required this.clientName, required this.scope});
  final String authReqId;
  final String clientName;
  final String scope;
}

final ValueNotifier<PendingApproval?> _pending = ValueNotifier(null);

void _handleCibaMessage(RemoteMessage m) {
  if (m.data['type'] != 'ciba_request') return;
  final authReqId = m.data['auth_req_id'] as String?;
  if (authReqId == null) return;
  _pending.value = PendingApproval(
    authReqId: authReqId,
    clientName: (m.data['client_name'] as String?) ?? '?',
    scope: (m.data['scope'] as String?) ?? '',
  );
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await FirebaseMessaging.instance.requestPermission();
  await oidcManager.init();
  // 通知ハンドラ登録 (フォアグラウンド + バックグラウンドから通知タップ)
  FirebaseMessaging.onMessage.listen(_handleCibaMessage);
  FirebaseMessaging.onMessageOpenedApp.listen(_handleCibaMessage);
  // アプリ終了時から通知タップで起動した場合
  final initial = await FirebaseMessaging.instance.getInitialMessage();
  if (initial != null) _handleCibaMessage(initial);
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'fido2demo',
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo)),
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
      body: Stack(
        children: [
          StreamBuilder<OidcUser?>(
            stream: oidcManager.userChanges(),
            initialData: oidcManager.currentUser,
            builder: (context, snapshot) {
              final user = snapshot.data;
              return user == null ? const LoginView() : UserView(user: user);
            },
          ),
          // 保留中の CIBA 承認要求があれば dialog を表示する
          ValueListenableBuilder<PendingApproval?>(
            valueListenable: _pending,
            builder: (context, pending, _) {
              if (pending == null) return const SizedBox.shrink();
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _showApprovalDialog(context, pending);
              });
              return const SizedBox.shrink();
            },
          ),
        ],
      ),
    );
  }
}

bool _dialogOpen = false;
void _showApprovalDialog(BuildContext context, PendingApproval pending) {
  if (_dialogOpen) return;
  _dialogOpen = true;
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => ApprovalDialog(pending: pending),
  ).whenComplete(() {
    _dialogOpen = false;
    _pending.value = null;
  });
}

class ApprovalDialog extends StatefulWidget {
  const ApprovalDialog({super.key, required this.pending});
  final PendingApproval pending;
  @override
  State<ApprovalDialog> createState() => _ApprovalDialogState();
}

class _ApprovalDialogState extends State<ApprovalDialog> {
  bool _busy = false;
  String? _error;

  Future<void> _approve() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // 1. OP から Passkey options を取得 (allowCredentials を含む)
      final optsRes = await http.post(
        Uri.parse('$_opBase/interaction/ciba/${widget.pending.authReqId}/passkey-options'),
        headers: {'Content-Type': 'application/json'},
        body: '{}',
      );
      if (optsRes.statusCode != 200) {
        throw Exception('options ${optsRes.statusCode}: ${optsRes.body}');
      }
      // 2. passkeys パッケージで iOS のネイティブ Passkey 認証 (Face ID)
      final req = AuthenticateRequestType.fromJsonString(optsRes.body);
      final resp = await PasskeyAuthenticator().authenticate(req);
      // 3. assertion を OP に送って承認完了
      final apprRes = await http.post(
        Uri.parse('$_opBase/interaction/ciba/${widget.pending.authReqId}/approve'),
        body: {'assertion': resp.toJsonString()},
      );
      if (apprRes.statusCode != 204) {
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
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
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
      final cancelled = e.toString().contains('FlutterAppAuthUserCancelledException');
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

class UserView extends StatefulWidget {
  const UserView({super.key, required this.user});
  final OidcUser user;
  @override
  State<UserView> createState() => _UserViewState();
}

class _UserViewState extends State<UserView> {
  String _fcmStatus = '初期化中…';

  @override
  void initState() {
    super.initState();
    _registerFcmToken();
  }

  Future<void> _registerFcmToken() async {
    try {
      final fcmToken = await FirebaseMessaging.instance.getToken();
      if (fcmToken == null) {
        if (mounted) setState(() => _fcmStatus = 'FCM token 取得失敗 (null)');
        return;
      }
      final accessToken = widget.user.token.accessToken;
      if (accessToken == null) {
        if (mounted) setState(() => _fcmStatus = 'access_token 不在');
        return;
      }
      final res = await http.post(
        Uri.parse('$_opBase/api/me/fcm-tokens'),
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'token': fcmToken, 'platform': 'ios'}),
      );
      final preview = fcmToken.substring(0, math.min(20, fcmToken.length));
      if (!mounted) return;
      setState(() {
        _fcmStatus = res.statusCode == 204
            ? '登録成功 (token: $preview…)'
            : '登録失敗 ${res.statusCode}: ${res.body}';
      });
    } catch (e) {
      if (mounted) setState(() => _fcmStatus = 'エラー: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    const encoder = JsonEncoder.withIndent('  ');
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _DataCard(title: 'subject', body: widget.user.uid ?? 'N/A'),
        _DataCard(
          title: 'ID Token Claims',
          body: encoder.convert(widget.user.claims.toJson()),
        ),
        _DataCard(title: 'UserInfo', body: encoder.convert(widget.user.userInfo)),
        _DataCard(
          title: 'FCM Token (CIBA Authentication Device 登録)',
          body: _fcmStatus,
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
