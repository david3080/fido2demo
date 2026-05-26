import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers.dart';
import '../remote_cursor.dart';
import '../ui_shared.dart';

/// リモート支援デモ: cursorCommandProvider を監視し、対象 widget (GlobalKey) の位置に
/// ハイライト枠・ポインタ・説明ラベルを重ねて表示する。タップは透過 (IgnorePointer)。
class CursorOverlay extends ConsumerStatefulWidget {
  const CursorOverlay({super.key});
  @override
  ConsumerState<CursorOverlay> createState() => _CursorOverlayState();
}

class _CursorOverlayState extends ConsumerState<CursorOverlay>
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
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  void _applyCommand(CursorCommand? cmd) {
    // null は案内の解除 (clear_highlight / target='none')。表示中の枠を消す。
    if (cmd == null) {
      setState(() {
        _target = null;
        _label = '';
      });
      return;
    }
    // 次の案内が来るまで表示し続ける (自動では消さない)。
    setState(() {
      _target = cmd.target;
      _label = cmd.label;
    });
    // 対象を画面内へスクロールして見せる。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = cursorTargetKeys[cmd.target]?.currentContext;
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
    final targetCtx = cursorTargetKeys[t]?.currentContext;
    final selfBox = context.findRenderObject() as RenderBox?;
    if (targetCtx == null || selfBox == null || !selfBox.hasSize) return null;
    final targetBox = targetCtx.findRenderObject() as RenderBox?;
    if (targetBox == null || !targetBox.hasSize) return null;
    final topLeft = selfBox.globalToLocal(targetBox.localToGlobal(Offset.zero));
    return topLeft & targetBox.size;
  }

  @override
  Widget build(BuildContext context) {
    // cursorCommandProvider の変化で表示/解除を適用する。
    ref.listen<CursorCommand?>(cursorCommandProvider, (_, next) => _applyCommand(next));
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
