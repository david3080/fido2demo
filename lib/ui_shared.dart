import 'package:flutter/material.dart';
import 'package:oidc/oidc.dart';

// iOS は ephemeral ASWebAuthenticationSession を使う。
// Safari と Cookie を共有しない使い捨てセッションなので、iOS の
// 「"oidc.sonrisa.co.jp" を使用しようとしています」確認ダイアログが出ない。
// パスキーは OS のプロバイダ(iCloud キーチェーン等)経由なので ephemeral でも認証可能。
// （macOS は ASWebAuthenticationSession が別ウィンドウになり passkey を
//  アプリ内に収められないため、対象から外した。）
const loginOptions = OidcPlatformSpecificOptions(
  ios: OidcPlatformSpecificOptions_AppAuth_IosMacos(
    externalUserAgent: OidcAppAuthExternalUserAgent.ephemeralAsWebAuthenticationSession,
  ),
);

/// 案内対象 widget に付ける GlobalKey。UserView 側でこのキーをカードやボタンに割り当てる。
final Map<String, GlobalKey> cursorTargetKeys = {
  'name': GlobalKey(),
  'nickname': GlobalKey(),
  'gender': GlobalKey(),
  'birthdate': GlobalKey(),
  'save': GlobalKey(),
  'logout': GlobalKey(),
};
