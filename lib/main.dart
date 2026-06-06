import 'dart:convert';

import 'package:app_links/app_links.dart';
import 'package:dart_dpop/dart_dpop.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:oidc/oidc.dart';
import 'package:oidc_default_store/oidc_default_store.dart';

import 'ciba_request.dart';
import 'firebase_options.dart';
import 'magic_link.dart';
import 'op_endpoints.dart';
import 'providers.dart';
import 'remote_cursor.dart';
import 'ui_shared.dart';
import 'widgets/home_page.dart';

// DPoP 用 ES256 鍵とそれを使う HTTP クライアント。
// 鍵は flutter_secure_storage に永続化し（_loadOrCreateDpopKey）、再起動/FCM
// コールド起動後も同じ鍵 = 既存 access_token (cnf.jkt) を有効に保つ。
// oidcManager/dpopClient は main で生成し providers に override 注入する。
// 宣言的 UI 側は ref(oidcManagerProvider/dpopClientProvider) で参照する。


// FCM / Universal Link ハンドラは providers の保持付きシンク（ValueNotifier）へ
// 書き込むだけ。Riverpod の Notifier がこれをミラーし宣言的 UI に供給する。

void _handleUniversalLink(Uri? uri) {
  final t = parseMagicLinkToken(uri);
  if (t != null) magicLinkTokenSink.value = t;
}

void _handleCibaMessage(RemoteMessage m) {
  final p = PendingApproval.fromFcmData(m.data);
  if (p != null) pendingApprovalSink.value = p;
}


void _handleRemoteCursorMessage(RemoteMessage m) {
  switch (parseRemoteCursorEvent(m.data, cursorTargetKeys.keys.toSet())) {
    case CursorClear():
      cursorCommandSink.value = null;
    case CursorShow(:final command):
      cursorCommandSink.value = command;
    case CursorIgnore():
      break;
  }
}

const _secureStore = FlutterSecureStorage();
const _dpopKeyStorageId = 'dpop_es256_key_v1';

/// DPoP 鍵を flutter_secure_storage に永続化して再利用する。保存済みがあれば
/// d/x/y から復元、無ければ生成して保存。これにより再起動/FCM コールド起動後も
/// 同じ鍵 = 既存 access_token が有効なまま（CIBA 承認等の 401 を防ぐ）。
Future<Es256DpopKey> _loadOrCreateDpopKey() async {
  final stored = await _secureStore.read(key: _dpopKeyStorageId);
  if (stored != null) {
    try {
      final m = jsonDecode(stored) as Map<String, dynamic>;
      return await Es256DpopKey.fromSeed(
        d: base64Url.decode(m['d'] as String),
        x: base64Url.decode(m['x'] as String),
        y: base64Url.decode(m['y'] as String),
      );
    } catch (_) {
      // 壊れていたら作り直す。
    }
  }
  final key = await Es256DpopKey.generate();
  final raw = (key as PointycastleEs256DpopKey).extractRaw();
  await _secureStore.write(
    key: _dpopKeyStorageId,
    value: jsonEncode({
      'd': base64Url.encode(raw['d']!),
      'x': base64Url.encode(raw['x']!),
      'y': base64Url.encode(raw['y']!),
    }),
  );
  return key;
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

  // DPoP 初期化 (manager より先に作る必要あり: httpClient として注入するため)。
  // 鍵は flutter_secure_storage に永続化し、再起動/FCM 起動後も同じ鍵を使う。
  // 起動ごとに鍵が変わると既存 access_token (cnf.jkt) が無効化され 401 になるのを防ぐ。
  final dpopKey = await _loadOrCreateDpopKey();
  final dpopGen = DpopProofGenerator(key: dpopKey);
  final dpopClient = DpopHttpClient(generator: dpopGen);

  final manager = OidcUserManager.lazy(
    discoveryDocumentUri: OidcUtils.getOpenIdConfigWellKnownUri(
      Uri.parse('$opBase/oidc'),
    ),
    clientCredentials:
        const OidcClientAuthentication.none(clientId: 'mobile-rp'),
    store: OidcDefaultStore(),
    httpClient: dpopClient,
    settings: OidcUserManagerSettings(
      scope: const ['openid', 'profile', 'email', 'offline_access'],
      redirectUri: Uri.parse('jp.co.sonrisa.fido2demo://callback'),
      postLogoutRedirectUri: Uri.parse('jp.co.sonrisa.fido2demo://logout'),
      userInfoSettings: const OidcUserInfoSettings(sendUserInfoRequest: true),
    ),
  );
  await manager.init();
  // OP 独自エンドポイントは discovery から解決する（パスをハードコードしない）。
  // OP 側でパスを改名してもアプリは無改修で追従できる。欠落時は fromDiscoverySrc が
  // 例外で落とす（誤パスへ静かに投げるより起動時に気付く）。
  final opEndpoints = OpEndpoints.fromDiscoverySrc(manager.discoveryDocument.src);
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
    final accessToken = manager.currentUser?.token.accessToken;
    if (accessToken == null) return;
    try {
      await dpopClient.post(
        opEndpoints.fcmToken,
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'token': newToken, 'platform': 'ios'}),
      ).timeout(const Duration(seconds: 30));
    } catch (_) {}
  });

  runApp(
    ProviderScope(
      overrides: [
        oidcManagerProvider.overrideWithValue(manager),
        dpopClientProvider.overrideWithValue(dpopClient),
        opEndpointsProvider.overrideWithValue(opEndpoints),
      ],
      child: const MyApp(),
    ),
  );
}

