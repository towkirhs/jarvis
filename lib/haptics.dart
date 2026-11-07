import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';

/// Haptics only at moments that mean something, matched to how much the moment weighs (Android's haptics
/// guidance: crisp named effects, subtle for frequent things, stronger for rare important ones, always paired
/// with something visible). On Android they use the system's own named effects, so each phone plays them the
/// way it was tuned to and the system touch-feedback setting is respected.
class Haptics {
  static bool on = true;
  static const _ch = MethodChannel('jarcis/native');

  static void _play(String kind, Future<void> Function() fallback) {
    if (!on) return;
    if (kIsWeb) {
      fallback();
      return;
    }
    _ch.invokeMethod<bool>('haptic', {'kind': kind}).then((played) {
      if (played != true) fallback();
    }, onError: (_) {
      fallback();
    });
  }

  /// A choice changed: switching tabs, flipping a filter, undo.
  static void tick() => _play('tick', HapticFeedback.selectionClick);

  /// Something was sent or saved.
  static void tap() => _play('key', HapticFeedback.lightImpact);

  /// A task or habit got done.
  static void success() => _play('confirm', HapticFeedback.mediumImpact);

  /// Something was deleted.
  static void warn() => _play('longPress', HapticFeedback.heavyImpact);

  /// It did not work: a form is missing something, a sign-in failed.
  static void reject() => _play('reject', HapticFeedback.heavyImpact);

  /// For showing a form error in one expression: `error = Haptics.rejected() ?? 'message'`.
  static String? rejected() {
    reject();
    return null;
  }

  /// A switch was turned on or off.
  static void toggle(bool on) => _play(on ? 'toggleOn' : 'toggleOff', HapticFeedback.selectionClick);

  /// Picking something up to drag, and putting it down.
  static void dragStart() => _play('gestureStart', HapticFeedback.mediumImpact);
  static void dragEnd() => _play('gestureEnd', HapticFeedback.selectionClick);

  /// A slider moved one step.
  static void segment() => _play('segment', HapticFeedback.selectionClick);
}
