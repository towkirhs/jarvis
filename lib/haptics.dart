import 'package:flutter/services.dart';

/// Haptics only at moments that mean something, matched to how much the moment weighs.
/// Every one is paired with something visible, so turning them off loses nothing.
class Haptics {
  static bool on = true;

  /// A choice changed: switching tabs, flipping a filter, undo.
  static void tick() {
    if (on) HapticFeedback.selectionClick();
  }

  /// Something was sent or saved.
  static void tap() {
    if (on) HapticFeedback.lightImpact();
  }

  /// A task or habit got done.
  static void success() {
    if (on) HapticFeedback.mediumImpact();
  }

  /// Something was deleted.
  static void warn() {
    if (on) HapticFeedback.heavyImpact();
  }
}
