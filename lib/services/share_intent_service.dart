import 'dart:async';

import 'package:flutter/services.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

class ShareIntentService {
  ShareIntentService._();

  static final ShareIntentService instance = ShareIntentService._();

  static const _channel = MethodChannel('linkdrop/share_text');

  final _controller = StreamController<String>.broadcast();
  Stream<String> get sharedText => _controller.stream;

  StreamSubscription<List<SharedMediaFile>>? _mediaSub;
  String? _lastEmitted;

  /// The most recent shared text not yet consumed by a listener. `init()`
  /// runs (and may receive a cold-start share) before `LibraryScreen` has
  /// mounted and subscribed to [sharedText], so a plain broadcast stream
  /// would drop it. Callers should read and clear this on mount.
  String? consumePending() {
    final value = _pending;
    _pending = null;
    return value;
  }

  String? _pending;

  /// Registers listeners for both a cold-start share (app launched via the
  /// share sheet) and subsequent shares while the app is already running.
  ///
  /// A native `MethodChannel` reads `Intent.EXTRA_TEXT` directly, because
  /// `receive_sharing_intent`'s Android side drops the caption text whenever
  /// a share also carries an image/video stream (e.g. Instagram post/reel
  /// shares) — it only surfaces the attached file in that case.
  Future<void> init() async {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onSharedText') {
        _emit(call.arguments as String);
      }
    });

    final initialNative = await _channel.invokeMethod<String>('getInitialText');
    if (initialNative != null && initialNative.isNotEmpty) {
      _emit(initialNative);
    }

    final initial = await ReceiveSharingIntent.instance.getInitialMedia();
    for (final file in initial) {
      _emitIfText(file);
    }
    ReceiveSharingIntent.instance.reset();

    _mediaSub = ReceiveSharingIntent.instance.getMediaStream().listen((files) {
      for (final file in files) {
        _emitIfText(file);
      }
    });
  }

  void _emitIfText(SharedMediaFile file) {
    final isTextLike =
        file.type == SharedMediaType.text || file.type == SharedMediaType.url;
    if (isTextLike && file.path.isNotEmpty) {
      _emit(file.path);
    }
  }

  void _emit(String text) {
    if (text == _lastEmitted) return;
    _lastEmitted = text;
    if (_controller.hasListener) {
      _controller.add(text);
    } else {
      _pending = text;
    }
  }

  void dispose() {
    _mediaSub?.cancel();
    _controller.close();
  }
}
