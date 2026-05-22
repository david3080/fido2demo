import 'dart:convert';

import 'package:app_links/app_links.dart';
import 'package:dart_dpop/dart_dpop.dart';
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

// DPoP 用 ES256 鍵とそれを使う HTTP クライアント。
// アプリ起動ごとに鍵を新規生成するため、再起動で進行中の access_token は無効化される
// (= refresh も含めて再ログインが必要)。永続化は flutter_secure_storage で将来対応。
late final DpopProofGenerator _dpopGen;
late final DpopHttpClient _dpopClient;
late final OidcUserManager oidcManager;

// ログインは非 ephemeral: Safari の autofill 機構と統合され、WebAuthn Conditional UI
// (パスキー候補の自動表示) が効くようになる。トレードオフとして Safari Cookie を共有する。
const _loginOptions = OidcPlatformSpecificOptions(
  ios: OidcPlatformSpecificOptions_AppAuth_IosMacos(
    externalUserAgent: OidcAppAuthExternalUserAgent.asWebAuthenticationSession,
  ),
  // macOS は ephemeral にして、ユーザーの通常 Safari ではなく隔離された
  // ASWebAuthenticationSession ウィンドウを使う (外部ブラウザ起動を避ける)。
  // パスキーは OS のプロバイダ経由なので ephemeral でも認証できる。
  macos: OidcPlatformSpecificOptions_AppAuth_IosMacos(
    externalUserAgent: OidcAppAuthExternalUserAgent.ephemeralAsWebAuthenticationSession,
  ),
);

// メアド簡易形式チェック (RFC 完全準拠ではなく実用範囲)。
final RegExp _emailRegex = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
bool _isValidEmail(String s) => s.length <= 254 && _emailRegex.hasMatch(s);

/// HTTP / ネットワーク例外を人間向けメッセージに変換する。
String _humanizeError(Object e) {
  final msg = e.toString();
  if (msg.contains('TimeoutException')) return 'タイムアウトしました。インターネット接続を確認してください。';
  if (msg.contains('SocketException') || msg.contains('Failed host lookup')) return 'ネットワークに接続できません。';
  if (msg.contains('cancel') || msg.contains('Cancel')) return 'キャンセルされました。';
  return msg.replaceFirst('Exception: ', '');
}

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

/// リモート支援デモ: CIBA 承認済みのオペレータ (Claude Code) から
/// `type:'remote_cursor'` の data 通知を受けて、対象 widget にカーソル/ハイライトを出す。
/// target はサーバ側 CURSOR_TARGETS と同じキー。
class CursorCommand {
  CursorCommand({required this.target, required this.label});
  final String target;
  final String label;
}

final ValueNotifier<CursorCommand?> _cursorCommand = ValueNotifier(null);

/// 案内対象 widget に付ける GlobalKey。UserView 側でこのキーをカードやボタンに割り当てる。
final Map<String, GlobalKey> _cursorTargetKeys = {
  'name': GlobalKey(),
  'nickname': GlobalKey(),
  'gender': GlobalKey(),
  'birthdate': GlobalKey(),
  'logout': GlobalKey(),
};

void _handleRemoteCursorMessage(RemoteMessage m) {
  if (m.data['type'] != 'remote_cursor') return;
  final target = m.data['target'] as String?;
  if (target == null || !_cursorTargetKeys.containsKey(target)) return;
  _cursorCommand.value = CursorCommand(
    target: target,
    label: (m.data['label'] as String?) ?? '',
  );
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  // macOS など通知認可が取得できない環境でも起動を止めない (例外で runApp 前に
  // 落ちると黒画面になるため)。CIBA プッシュは認可が取れた環境でのみ届く。
  try {
    await FirebaseMessaging.instance.requestPermission();
  } catch (e) {
    debugPrint('FCM requestPermission failed (continuing): $e');
  }

  // DPoP 初期化 (oidcManager より先に作る必要あり: httpClient として注入するため)
  final dpopKey = await Es256DpopKey.generate();
  _dpopGen = DpopProofGenerator(key: dpopKey);
  _dpopClient = DpopHttpClient(generator: _dpopGen);

  oidcManager = OidcUserManager.lazy(
    discoveryDocumentUri: OidcUtils.getOpenIdConfigWellKnownUri(
      Uri.parse('$_opBase/oidc'),
    ),
    clientCredentials:
        const OidcClientAuthentication.none(clientId: 'mobile-rp'),
    store: OidcDefaultStore(),
    httpClient: _dpopClient,
    settings: OidcUserManagerSettings(
      scope: const ['openid', 'profile', 'email', 'offline_access'],
      redirectUri: Uri.parse('jp.co.sonrisa.fido2demo://callback'),
      postLogoutRedirectUri: Uri.parse('jp.co.sonrisa.fido2demo://logout'),
      userInfoSettings: const OidcUserInfoSettings(sendUserInfoRequest: true),
    ),
  );
  await oidcManager.init();
  // 通知ハンドラ登録 (フォアグラウンド + バックグラウンドから通知タップ)
  FirebaseMessaging.onMessage.listen(_handleCibaMessage);
  FirebaseMessaging.onMessageOpenedApp.listen(_handleCibaMessage);
  // リモート支援デモ: カーソル案内 (data-only, アプリ前面時に届く)
  FirebaseMessaging.onMessage.listen(_handleRemoteCursorMessage);
  // アプリ終了時から通知タップで起動した場合
  try {
    final initial = await FirebaseMessaging.instance.getInitialMessage();
    if (initial != null) _handleCibaMessage(initial);
  } catch (e) {
    debugPrint('FCM getInitialMessage failed (continuing): $e');
  }

  // Universal Link (Magic Link メール内の URL から起動した場合 / バックグラウンド復帰)
  final appLinks = AppLinks();
  appLinks.uriLinkStream.listen(_handleUniversalLink);
  final initialUri = await appLinks.getInitialLink();
  if (initialUri != null) _handleUniversalLink(initialUri);

  // FCM token rotation を自動追従。アプリが OIDC ログイン中なら新 token を
  // サーバの replaceFcmToken に反映し、stale token に CIBA が届かない問題を防ぐ。
  FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
    final accessToken = oidcManager.currentUser?.token.accessToken;
    if (accessToken == null) return;
    await _postFcmToken(accessToken, newToken).catchError((_) {});
  });

  runApp(const MyApp());
}

/// FCM token をサーバに POST するヘルパー (UserView の _registerFcmToken と onTokenRefresh の両方から呼ぶ)。
/// _dpopClient 経由なので Bearer は自動で DPoP に変換され proof が付与される。
Future<void> _postFcmToken(String accessToken, String fcmToken) async {
  await _dpopClient
      .post(
        Uri.parse('$_opBase/api/me/fcm-tokens'),
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'token': fcmToken, 'platform': 'ios'}),
      )
      .timeout(const Duration(seconds: 30));
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
      body: SafeArea(
        child: Stack(
        children: [
          StreamBuilder<OidcUser?>(
            stream: oidcManager.userChanges(),
            initialData: oidcManager.currentUser,
            builder: (context, snapshot) {
              final user = snapshot.data;
              if (user == null) {
                // ログアウト時はカーソル案内を消す
                if (_cursorCommand.value != null) {
                  WidgetsBinding.instance.addPostFrameCallback(
                    (_) => _cursorCommand.value = null,
                  );
                }
                return const LoginView();
              }
              return UserView(user: user);
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
          // リモート支援: カーソル/ハイライトのオーバーレイ (タップは透過)
          const Positioned.fill(child: IgnorePointer(child: CursorOverlay())),
        ],
        ),
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
    final email = _controller.text.trim().toLowerCase();
    if (email.isEmpty) {
      setState(() => _error = 'メールアドレスを入力してください');
      return;
    }
    if (email.length > 254) {
      setState(() => _error = 'メールアドレスが長すぎます (254 文字以内)');
      return;
    }
    if (!_isValidEmail(email)) {
      setState(() => _error = 'メールアドレスの形式が正しくありません (例: name@example.com)');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final res = await http
          .post(
            Uri.parse('$_opBase/api/register/email-challenge'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'email': email}),
          )
          .timeout(const Duration(seconds: 30));
      if (res.statusCode == 429) {
        throw Exception('リクエストが多すぎます。しばらくしてから再試行してください。');
      }
      if (res.statusCode >= 500) {
        throw Exception('サーバが一時的に利用できません。しばらくしてから再試行してください。');
      }
      if (res.statusCode != 204) {
        throw Exception('予期しないエラー (HTTP ${res.statusCode})');
      }
      if (mounted) setState(() => _sent = true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = _humanizeError(e);
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
      // SingleChildScrollView でラップして、キーボード表示時に AlertDialog の
      // content が縮んで error 文字が actions ボタンと重なる問題を回避する。
      content: SingleChildScrollView(
        child: Column(
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
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  border: Border.all(color: Colors.red.shade300),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  _error!,
                  style: TextStyle(color: Colors.red.shade700, fontSize: 13),
                ),
              ),
              const SizedBox(height: 4),
            ],
          ],
        ),
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
      final res = await http
          .post(
            Uri.parse('$_opBase/api/register/verify-email'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'token': widget.token}),
          )
          .timeout(const Duration(seconds: 30));
      if (res.statusCode == 400) {
        throw Exception('リンクの有効期限が切れたか、既に使用されています。もう一度メアドから送信してください。');
      }
      if (res.statusCode == 409) {
        throw Exception('既に登録済みです。サインインしてください。');
      }
      if (res.statusCode >= 500) {
        throw Exception('サーバが一時的に利用できません。');
      }
      if (res.statusCode != 200) {
        throw Exception('予期しないエラー (HTTP ${res.statusCode})');
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
          _error = _humanizeError(e);
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
      final optsRes = await http
          .post(
            Uri.parse('$_opBase/api/register/passkey-options'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'verified_token': _verifiedToken}),
          )
          .timeout(const Duration(seconds: 30));
      if (optsRes.statusCode == 401) {
        throw Exception('登録セッションが切れました。最初からやり直してください。');
      }
      if (optsRes.statusCode != 200) {
        throw Exception('options 取得失敗 (HTTP ${optsRes.statusCode})');
      }
      final req = RegisterRequestType.fromJsonString(optsRes.body);
      final resp = await PasskeyAuthenticator().register(req);
      final verifyRes = await http
          .post(
            Uri.parse('$_opBase/api/register/passkey-verify'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'verified_token': _verifiedToken,
              'attestation': jsonDecode(resp.toJsonString()),
            }),
          )
          .timeout(const Duration(seconds: 30));
      if (verifyRes.statusCode != 201) {
        throw Exception('Passkey 検証失敗 (HTTP ${verifyRes.statusCode})');
      }
      if (!mounted) return;
      setState(() => _status = '登録完了。サインインします…');
      Navigator.of(context).pop();
      await oidcManager.loginAuthorizationCodeFlow(
        options: _loginOptions,
        promptOverride: const ['login'],
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = _humanizeError(e);
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
  final _name = TextEditingController();
  final _nickname = TextEditingController();
  final _birthdate = TextEditingController();
  String _gender = '';
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _registerFcmToken(); // CIBA 通知用に裏で登録 (画面には出さない)
    _loadProfile();
  }

  @override
  void dispose() {
    _name.dispose();
    _nickname.dispose();
    _birthdate.dispose();
    super.dispose();
  }

  String get _email {
    final ui = widget.user.userInfo['email'];
    if (ui is String && ui.isNotEmpty) return ui;
    final c = widget.user.claims.toJson()['email'];
    if (c is String && c.isNotEmpty) return c;
    return widget.user.uid ?? '';
  }

  Future<void> _registerFcmToken() async {
    try {
      final fcmToken = await FirebaseMessaging.instance.getToken();
      final accessToken = widget.user.token.accessToken;
      if (fcmToken == null || accessToken == null) return;
      await _dpopClient.post(
        Uri.parse('$_opBase/api/me/fcm-tokens'),
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'token': fcmToken, 'platform': 'ios'}),
      );
    } catch (_) {
      // 失敗してもプロフィール画面は使えるので黙って無視。
    }
  }

  Future<void> _loadProfile() async {
    try {
      final accessToken = widget.user.token.accessToken;
      if (accessToken != null) {
        final res = await _dpopClient.get(
          Uri.parse('$_opBase/api/me/profile'),
          headers: {'Authorization': 'Bearer $accessToken'},
        );
        if (res.statusCode == 200) {
          final m = jsonDecode(res.body) as Map<String, dynamic>;
          _name.text = (m['name'] as String?) ?? '';
          _nickname.text = (m['nickname'] as String?) ?? '';
          _birthdate.text = (m['birthdate'] as String?) ?? '';
          _gender = (m['gender'] as String?) ?? '';
        }
      }
    } catch (_) {
      // 読めなくても空で編集開始できる。
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final accessToken = widget.user.token.accessToken;
      if (accessToken == null) {
        throw Exception('セッションが切れました。ログインし直してください。');
      }
      final res = await _dpopClient.put(
        Uri.parse('$_opBase/api/me/profile'),
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'name': _name.text.trim(),
          'nickname': _nickname.text.trim(),
          'gender': _gender,
          'birthdate': _birthdate.text.trim(),
        }),
      );
      if (res.statusCode != 204) {
        throw Exception('保存に失敗しました (HTTP ${res.statusCode})');
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('プロフィールを保存しました')),
      );
    } catch (e) {
      if (mounted) setState(() => _error = _humanizeError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickBirthdate() async {
    final parsed = DateTime.tryParse(_birthdate.text);
    final picked = await showDatePicker(
      context: context,
      initialDate: parsed ?? DateTime(2000, 1, 1),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      final y = picked.year.toString().padLeft(4, '0');
      final m = picked.month.toString().padLeft(2, '0');
      final d = picked.day.toString().padLeft(2, '0');
      setState(() => _birthdate.text = '$y-$m-$d');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('プロフィール',
              style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 2),
          Text(_email, style: const TextStyle(color: Colors.black54)),
          const SizedBox(height: 16),
          _FieldCard(
            key: _cursorTargetKeys['name'],
            label: '氏名',
            child: TextField(
              controller: _name,
              decoration: const InputDecoration(
                  hintText: '未設定', border: OutlineInputBorder()),
            ),
          ),
          _FieldCard(
            key: _cursorTargetKeys['nickname'],
            label: 'ニックネーム',
            child: TextField(
              controller: _nickname,
              decoration: const InputDecoration(
                  hintText: '未設定', border: OutlineInputBorder()),
            ),
          ),
          _FieldCard(
            key: _cursorTargetKeys['gender'],
            label: '性別',
            child: DropdownButtonFormField<String>(
              initialValue: _gender.isEmpty ? null : _gender,
              decoration: const InputDecoration(border: OutlineInputBorder()),
              hint: const Text('未設定'),
              items: const [
                DropdownMenuItem(value: 'male', child: Text('男性')),
                DropdownMenuItem(value: 'female', child: Text('女性')),
                DropdownMenuItem(value: 'other', child: Text('その他')),
              ],
              onChanged: (v) => setState(() => _gender = v ?? ''),
            ),
          ),
          _FieldCard(
            key: _cursorTargetKeys['birthdate'],
            label: '誕生日',
            child: TextField(
              controller: _birthdate,
              readOnly: true,
              onTap: _pickBirthdate,
              decoration: const InputDecoration(
                hintText: '未設定',
                border: OutlineInputBorder(),
                suffixIcon: Icon(Icons.calendar_today),
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 4),
            Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 13)),
          ],
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save),
            label: const Text('保存'),
          ),
          const SizedBox(height: 24),
          FilledButton.tonalIcon(
            key: _cursorTargetKeys['logout'],
            // ブラウザを開く RP-initiated ログアウトではなくローカルでトークンを破棄する。
            // ログインは毎回 prompt=login を強制するため、OP セッションが残っても
            // 勝手な自動ログインは起きない (= ブラウザの点滅を無くせる)。
            onPressed: () => oidcManager.forgetUser(),
            icon: const Icon(Icons.logout),
            label: const Text('ログアウト'),
          ),
        ],
      ),
    );
  }
}

/// プロフィール 1 項目分のカード (ラベル + 入力 widget)。カーソル案内の対象。
class _FieldCard extends StatelessWidget {
  const _FieldCard({super.key, required this.label, required this.child});
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            child,
          ],
        ),
      ),
    );
  }
}

/// リモート支援デモ: `_cursorCommand` を監視し、対象 widget (GlobalKey) の位置に
/// ハイライト枠・ポインタ・説明ラベルを重ねて表示する。タップは透過 (IgnorePointer)。
class CursorOverlay extends StatefulWidget {
  const CursorOverlay({super.key});
  @override
  State<CursorOverlay> createState() => _CursorOverlayState();
}

class _CursorOverlayState extends State<CursorOverlay>
    with SingleTickerProviderStateMixin {
  String? _target;
  String _label = '';
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _cursorCommand.addListener(_onCommand);
  }

  @override
  void dispose() {
    _cursorCommand.removeListener(_onCommand);
    _pulse.dispose();
    super.dispose();
  }

  void _onCommand() {
    final cmd = _cursorCommand.value;
    if (cmd == null) return;
    // 次の案内が来るまで表示し続ける (自動では消さない)。
    setState(() {
      _target = cmd.target;
      _label = cmd.label;
    });
    // 対象を画面内へスクロールして見せる。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _cursorTargetKeys[cmd.target]?.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 300),
          alignment: 0.3,
        );
      }
    });
  }

  /// 対象 widget の現在位置をこのオーバーレイのローカル座標で返す。
  /// 毎フレーム呼んでスクロールに追従させる。対象が画面外/未生成なら null。
  Rect? _currentRect() {
    final t = _target;
    if (t == null) return null;
    final targetCtx = _cursorTargetKeys[t]?.currentContext;
    final selfBox = context.findRenderObject() as RenderBox?;
    if (targetCtx == null || selfBox == null || !selfBox.hasSize) return null;
    final targetBox = targetCtx.findRenderObject() as RenderBox?;
    if (targetBox == null || !targetBox.hasSize) return null;
    final topLeft = selfBox.globalToLocal(targetBox.localToGlobal(Offset.zero));
    return topLeft & targetBox.size;
  }

  @override
  Widget build(BuildContext context) {
    if (_target == null) return const SizedBox.shrink();
    final primary = Theme.of(context).colorScheme.primary;
    // _pulse を毎フレーム購読することで、スクロール中も位置を再計算する。
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, _) {
        final rect = _currentRect();
        if (rect == null) return const SizedBox.shrink();
        final t = _pulse.value;
        final labelAbove = rect.top > 56;
        return Stack(
          children: [
            Positioned(
              left: rect.left - 4,
              top: rect.top - 4,
              width: rect.width + 8,
              height: rect.height + 8,
              child: Container(
                decoration: BoxDecoration(
                  color: primary.withAlpha((30 + 30 * t).round()),
                  border: Border.all(
                    color: primary.withAlpha((128 + 127 * t).round()),
                    width: 3,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            Positioned(
              left: rect.left - 18,
              top: rect.center.dy - 14,
              child: Icon(Icons.touch_app, size: 32, color: primary),
            ),
            if (_label.isNotEmpty)
              Positioned(
                left: rect.left,
                top: labelAbove ? rect.top - 44 : rect.bottom + 12,
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 280),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: primary,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
