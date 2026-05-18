import 'dart:convert';
import 'dart:math' as math;

import 'package:app_links/app_links.dart';
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

// ログインは非 ephemeral: Safari の autofill 機構と統合され、WebAuthn Conditional UI
// (パスキー候補の自動表示) が効くようになる。トレードオフとして Safari Cookie を共有する。
const _loginOptions = OidcPlatformSpecificOptions(
  ios: OidcPlatformSpecificOptions_AppAuth_IosMacos(
    externalUserAgent: OidcAppAuthExternalUserAgent.asWebAuthenticationSession,
  ),
  macos: OidcPlatformSpecificOptions_AppAuth_IosMacos(
    externalUserAgent: OidcAppAuthExternalUserAgent.asWebAuthenticationSession,
  ),
);

// ログアウトは ephemeral: 「サインインのために … を使用しようとしています」確認ダイアログを抑制。
const _logoutOptions = OidcPlatformSpecificOptions(
  ios: OidcPlatformSpecificOptions_AppAuth_IosMacos(
    externalUserAgent: OidcAppAuthExternalUserAgent.ephemeralAsWebAuthenticationSession,
  ),
  macos: OidcPlatformSpecificOptions_AppAuth_IosMacos(
    externalUserAgent: OidcAppAuthExternalUserAgent.ephemeralAsWebAuthenticationSession,
  ),
);

/// Magic Link (Universal Link で受信) の token を保持する。
/// HomePage がこれを監視して登録 dialog を表示する。
final ValueNotifier<String?> _magicLinkToken = ValueNotifier(null);

void _handleUniversalLink(Uri? uri) {
  if (uri == null) return;
  if (uri.host != 'oidc.sonrisa.co.jp') return;
  if (uri.path != '/r') return;
  final t = uri.queryParameters['t'];
  if (t == null || t.isEmpty) return;
  _magicLinkToken.value = t;
}

/// CIBA: Mac (Consumption Device) からの保留中認証要求。FCM 通知から復元する。
class PendingApproval {
  PendingApproval({
    required this.authReqId,
    required this.clientName,
    required this.scope,
    required this.bindingMessage,
  });
  final String authReqId;
  final String clientName;
  final String scope;
  final String bindingMessage;
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
    bindingMessage: (m.data['binding_message'] as String?) ?? '',
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

  // Universal Link (Magic Link メール内の URL から起動した場合 / バックグラウンド復帰)
  final appLinks = AppLinks();
  appLinks.uriLinkStream.listen(_handleUniversalLink);
  final initialUri = await appLinks.getInitialLink();
  if (initialUri != null) _handleUniversalLink(initialUri);

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
          // Magic Link で起動した場合は Passkey 登録 dialog を表示する
          ValueListenableBuilder<String?>(
            valueListenable: _magicLinkToken,
            builder: (context, token, _) {
              if (token == null) return const SizedBox.shrink();
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _showMagicLinkDialog(context, token);
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

bool _magicLinkDialogOpen = false;
void _showMagicLinkDialog(BuildContext context, String token) {
  if (_magicLinkDialogOpen) return;
  _magicLinkDialogOpen = true;
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => MagicLinkDialog(token: token),
  ).whenComplete(() {
    _magicLinkDialogOpen = false;
    _magicLinkToken.value = null;
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

  Future<void> _reject() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final res = await http.post(
        Uri.parse('$_opBase/interaction/ciba/${widget.pending.authReqId}/reject'),
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
      // prompt=login: 既存の OIDC session cookie で skip させず必ず再認証。
      // oidc-provider 9 は select_account を未サポートのため login を使う。
      // 結果として Conditional UI が走り、複数 Passkey 登録時は iOS の
      // 選択 sheet で候補から選べるようになる。
      await oidcManager.loginAuthorizationCodeFlow(
        options: _loginOptions,
        promptOverride: const ['login'],
      );
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
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _busy ? null : () => _openRegisterEmail(context),
            icon: const Icon(Icons.mail_outline),
            label: const Text('新規登録 (メアドで)'),
          ),
        ],
      ),
    );
  }

  void _openRegisterEmail(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (_) => const RegisterEmailDialog(),
    );
  }
}

/// 新規登録: メアド入力 → /api/register/email-challenge を呼んで Magic Link 送信
class RegisterEmailDialog extends StatefulWidget {
  const RegisterEmailDialog({super.key});
  @override
  State<RegisterEmailDialog> createState() => _RegisterEmailDialogState();
}

class _RegisterEmailDialogState extends State<RegisterEmailDialog> {
  final _controller = TextEditingController();
  bool _busy = false;
  String? _error;
  bool _sent = false;

  Future<void> _send() async {
    final email = _controller.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _error = 'メアドを入力してください');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final res = await http.post(
        Uri.parse('$_opBase/api/register/email-challenge'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email}),
      );
      if (res.statusCode != 204) {
        throw Exception('HTTP ${res.statusCode}: ${res.body}');
      }
      if (mounted) setState(() => _sent = true);
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
    if (_sent) {
      return AlertDialog(
        title: const Text('メールを送信しました'),
        content: const Text(
          '受信箱でメール内の「アプリで開く」ボタンをタップしてください。\n'
          '有効期限は 15 分です。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('閉じる'),
          ),
        ],
      );
    }
    return AlertDialog(
      title: const Text('新規登録'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('メールアドレスを入力してください。確認メールを送信します。'),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            enabled: !_busy,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            decoration: const InputDecoration(
              hintText: 'you@example.com',
              border: OutlineInputBorder(),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 12)),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('キャンセル'),
        ),
        FilledButton(
          onPressed: _busy ? null : _send,
          child: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('送信'),
        ),
      ],
    );
  }
}

/// Magic Link tap で起動 → token を verify → email 取得 → Passkey 登録 → OIDC ログイン
class MagicLinkDialog extends StatefulWidget {
  const MagicLinkDialog({super.key, required this.token});
  final String token;
  @override
  State<MagicLinkDialog> createState() => _MagicLinkDialogState();
}

class _MagicLinkDialogState extends State<MagicLinkDialog> {
  bool _busy = false;
  String? _email;
  String? _verifiedToken;
  String? _error;
  String _status = 'メールアドレス確認中…';

  @override
  void initState() {
    super.initState();
    _verifyEmail();
  }

  Future<void> _verifyEmail() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final res = await http.post(
        Uri.parse('$_opBase/api/register/verify-email'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'token': widget.token}),
      );
      if (res.statusCode == 409) {
        throw Exception('このメアドは既に登録されています。サインインしてください。');
      }
      if (res.statusCode != 200) {
        throw Exception('verify-email HTTP ${res.statusCode}: ${res.body}');
      }
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      if (mounted) {
        setState(() {
          _email = body['email'] as String?;
          _verifiedToken = body['verified_token'] as String?;
          _status = '確認しました。Face ID で Passkey を作成してください。';
          _busy = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _busy = false;
        });
      }
    }
  }

  Future<void> _registerPasskey() async {
    if (_verifiedToken == null) return;
    setState(() {
      _busy = true;
      _error = null;
      _status = 'Passkey を作成中…';
    });
    try {
      // 1. registration options
      final optsRes = await http.post(
        Uri.parse('$_opBase/api/register/passkey-options'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'verified_token': _verifiedToken}),
      );
      if (optsRes.statusCode != 200) {
        throw Exception('options HTTP ${optsRes.statusCode}: ${optsRes.body}');
      }
      // 2. iOS のネイティブ Passkey 作成 (Face ID)
      final req = RegisterRequestType.fromJsonString(optsRes.body);
      final resp = await PasskeyAuthenticator().register(req);
      // 3. attestation を送信
      final verifyRes = await http.post(
        Uri.parse('$_opBase/api/register/passkey-verify'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'verified_token': _verifiedToken,
          'attestation': jsonDecode(resp.toJsonString()),
        }),
      );
      if (verifyRes.statusCode != 201) {
        throw Exception('verify HTTP ${verifyRes.statusCode}: ${verifyRes.body}');
      }
      if (!mounted) return;
      setState(() => _status = '登録完了。サインインします…');
      Navigator.of(context).pop();
      // 自動でサインイン: ASWebAuthenticationSession 経由で OIDC ログイン
      await oidcManager.loginAuthorizationCodeFlow(options: _loginOptions);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _busy = false;
          _status = 'エラーが発生しました';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Passkey 登録'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_email != null)
            Text('メアド: $_email', style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Row(
            children: [
              if (_busy)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              if (_busy) const SizedBox(width: 8),
              Expanded(child: Text(_status)),
            ],
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
          child: const Text('キャンセル'),
        ),
        FilledButton.icon(
          onPressed: (_busy || _verifiedToken == null) ? null : _registerPasskey,
          icon: const Icon(Icons.fingerprint),
          label: const Text('Passkey 作成'),
        ),
      ],
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
          onPressed: () => oidcManager.logout(options: _logoutOptions),
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
