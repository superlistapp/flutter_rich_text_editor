import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

/// Controls the visibility of something that blinks.
///
/// A [BlinkController] maintains a timer that alters [opacity] based
/// on a [flashPeriod]. The blinking can be enabled or disabled, and
/// the opacity can be immediately reset to opaque with [jumpToOpaque()].
class BlinkController with ChangeNotifier {
  // Controls whether or not all BlinkControllers animate. This is intended
  // to be used by tests to disable animations so that pumpAndSettle() doesn't
  // time out.
  @visibleForTesting
  static bool indeterminateAnimationsEnabled = true;

  /// Creates a [BlinkController] that uses a ticker to switch between visible
  /// and invisible.
  ///
  /// If [animate] is `true`, the caret animates its [opacity] when switching
  /// between visible and invisible. If [animate] is `false`, the caret
  /// switches between fully opaque and fully transparent.
  BlinkController({
    required TickerProvider tickerProvider,
    Duration flashPeriod = const Duration(milliseconds: 500),
    bool animate = false,
    Duration fadeDuration = const Duration(milliseconds: 200),
  })  : _flashPeriod = flashPeriod,
        _fadeDuration = fadeDuration,
        _animate = animate {
    _ticker = tickerProvider.createTicker(_onTick);
  }

  BlinkController.withTimer({
    Duration flashPeriod = const Duration(milliseconds: 500),
  })  : _fadeDuration = Duration.zero,
        _flashPeriod = flashPeriod;

  @override
  void dispose() {
    _ticker?.dispose();
    _timer?.cancel();

    super.dispose();
  }

  Ticker? _ticker;
  Duration _lastBlinkTime = Duration.zero;

  Timer? _timer;

  /// Duration to switch between visible and invisible.
  Duration get flashPeriod => _flashPeriod;
  final Duration _flashPeriod;

  /// Duration of the fade in or out transition when switching
  /// between visible and invisible.
  final Duration _fadeDuration;

  /// Returns `true` if this controller is currently animating a blinking
  /// signal, or `false` if it's not.
  bool get isBlinking =>
      (_ticker != null || _timer != null) && (_ticker != null ? _ticker!.isTicking : _timer?.isActive ?? false);

  bool _isBlinkingEnabled = true;
  set isBlinkingEnabled(bool newValue) {
    if (newValue == _isBlinkingEnabled) {
      return;
    }

    _isBlinkingEnabled = newValue;
    if (!_isBlinkingEnabled) {
      stopBlinking();
    }
    notifyListeners();
  }

  /// Whether or not the caret is currently visible.
  ///
  /// When [isVisible] switches from `true` to `false`, the [opacity] is
  /// still greater than `0.0` while the fade-out animation is playing.
  bool get isVisible => _isVisible;
  bool _isVisible = true;

  double get opacity => _opacity;
  double _opacity = 1.0;

  /// Whether or not the caret should animate its opacity.
  ///
  /// If `true`, the caret fades in and out when switching between visible
  /// and invisible. If `false`, the caret switches between fully opaque
  /// and fully transparent.
  bool _animate = false;

  /// Whether or not the caret is keeping the current opacity until the next blink.
  ///
  /// This is used to keep the caret fully opaque for the [_flashPeriod], before it
  /// switches to `false` when the caret blinks for the first time. After [_isCaretOpaqueUntilNextBlink]
  /// is set to `true`, the caret fades in and out.
  ///
  /// For example, when the user places the caret, we want it to be visible with
  /// full opacity until the caret switches to invisible instead of immediately
  /// start the fade out animation.
  bool _isCaretOpaqueUntilNextBlink = false;

  void startBlinking() {
    if (!indeterminateAnimationsEnabled) {
      // Never animate a blink when the app/test wants to avoid
      // indeterminate animations.
      return;
    }

    if (_ticker != null) {
      // Don't animate the opacity until the flash period has elapsed.
      _isCaretOpaqueUntilNextBlink = true;

      // We're using a Ticker to blink. Restart it.
      _ticker!
        ..stop()
        ..start();
    } else {
      // We're using a Timer to blink. Restart it.
      _timer?.cancel();
      _timer = Timer(_flashPeriod, _blink);
    }

    _lastBlinkTime = Duration.zero;
    notifyListeners();
  }

  void stopBlinking() {
    // If we're not blinking then we need to be visible with full opacity.
    _isVisible = true;
    _opacity = 1.0;

    // Keep the caret opaque until the flash period has elapsed, when it
    // starts to fade out.
    _isCaretOpaqueUntilNextBlink = true;

    if (_ticker != null) {
      // We're using a Ticker to blink. Stop it.
      _ticker?.stop();
    } else {
      // We're using a Timer to blink. Stop it.
      _timer?.cancel();
      _timer = null;
    }

    notifyListeners();
  }

  /// Make the object completely opaque, and restart the blink timer.
  void jumpToOpaque() {
    final wasBlinking = isBlinking;
    stopBlinking();

    if (!_isBlinkingEnabled) {
      return;
    }

    if (wasBlinking) {
      startBlinking();
    }
  }

  void _onTick(Duration elapsedTime) {
    if (isBlinking && _animate && !_isCaretOpaqueUntilNextBlink) {
      final percentage = ((elapsedTime - _lastBlinkTime).inMilliseconds / _fadeDuration.inMilliseconds).clamp(0.0, 1.0);
      // If the caret is visible, we want to fade in. Otherwise, we want to fade out.
      _opacity = _isVisible ? percentage : 1 - percentage;
      notifyListeners();
    }

    if (elapsedTime - _lastBlinkTime >= _flashPeriod) {
      _blink();
      _lastBlinkTime = elapsedTime;
    }
  }

  void _blink() {
    _isVisible = !_isVisible;
    if (!_animate) {
      // We are not animating the visibility, so the caret is
      // either fully visible or fully invisible.
      _opacity = _isVisible ? 1.0 : 0.0;
    } else {
      // We are animating the visibility, start fading in or out.
      _isCaretOpaqueUntilNextBlink = false;
    }

    notifyListeners();

    if (_timer != null && _isBlinkingEnabled) {
      _timer = Timer(_flashPeriod, _blink);
    }
  }
}

/// The way a blinking caret tracks time.
///
/// Ideally, all time in Flutter widgets is tracked by `Ticker`s because they hook into
/// Flutter's internal time reporting. This is critical for tests.
///
/// Unfortunately, at the time of this writing, running `Ticker`s forces Flutter into
/// full FPS rendering, even when nothing needs to be rebuilt or painted. For that reason,
/// [BlinkController] lets users request the use of Dart `Timer`s, which only fire
/// when needed. `Timer`s are not expected to work in widget tests.
enum BlinkTimingMode {
  ticker,
  timer,
}
