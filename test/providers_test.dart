import 'package:fido2demo/ciba_request.dart';
import 'package:fido2demo/providers.dart';
import 'package:fido2demo/remote_cursor.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // シンクはグローバル ValueNotifier なのでテスト間で必ず空に戻す。
  tearDown(() {
    pendingApprovalSink.value = null;
    magicLinkTokenSink.value = null;
    cursorCommandSink.value = null;
  });

  test('pendingApprovalProvider mirrors the sink and reset() clears it', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(pendingApprovalProvider), isNull);

    final p = PendingApproval(
      authReqId: 'req-1',
      clientName: 'RP',
      scope: 'openid',
      bindingMessage: '42',
    );
    pendingApprovalSink.value = p;
    expect(container.read(pendingApprovalProvider), same(p));

    container.read(pendingApprovalProvider.notifier).reset();
    expect(pendingApprovalSink.value, isNull);
    expect(container.read(pendingApprovalProvider), isNull);
  });

  test('provider seeds from a sink value set before first read', () {
    magicLinkTokenSink.value = 'tok-1';
    final container = ProviderContainer();
    addTearDown(container.dispose);
    // build() 時点のシンク値を初期 state にする（コールド起動の取りこぼし防止）。
    expect(container.read(magicLinkTokenProvider), 'tok-1');
  });

  test('cursorCommandProvider mirrors show then clear', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    cursorCommandSink.value = CursorCommand(target: 'save', label: 'ここ');
    expect(container.read(cursorCommandProvider)?.target, 'save');

    cursorCommandSink.value = null; // 解除
    expect(container.read(cursorCommandProvider), isNull);
  });
}
