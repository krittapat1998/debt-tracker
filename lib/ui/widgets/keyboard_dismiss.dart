import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

/// Puts the keyboard away when the user taps anywhere outside the text field
/// being typed in, on every screen, dialog and sheet below it. iOS number
/// pads have no return key, so otherwise nothing closes them. Scrolling keeps
/// the keyboard up; tapping another field just moves to it.
class TapOutsideClosesKeyboard extends StatefulWidget {
  const TapOutsideClosesKeyboard({super.key, required this.child});
  final Widget child;

  @override
  State<TapOutsideClosesKeyboard> createState() => _TapOutsideClosesKeyboardState();
}

class _TapOutsideClosesKeyboardState extends State<TapOutsideClosesKeyboard> {
  /// Where the finger went down outside the field; decided on lift-off.
  Offset? _downAt;

  void _down(EditableTextTapOutsideIntent intent) {
    final event = intent.pointerDownEvent;
    if (event.kind == PointerDeviceKind.touch) {
      _downAt = event.position;
    } else {
      // A mouse or stylus click closes it at once, as Flutter already does.
      intent.focusNode.unfocus();
    }
  }

  void _up(EditableTextTapUpOutsideIntent intent) {
    final downAt = _downAt;
    _downAt = null;
    if (downAt != null && (intent.pointerUpEvent.position - downAt).distance < kTouchSlop) {
      intent.focusNode.unfocus();
    }
  }

  @override
  Widget build(BuildContext context) => Actions(
        actions: {
          EditableTextTapOutsideIntent: CallbackAction<EditableTextTapOutsideIntent>(onInvoke: _down),
          EditableTextTapUpOutsideIntent: CallbackAction<EditableTextTapUpOutsideIntent>(onInvoke: _up),
        },
        child: widget.child,
      );
}
