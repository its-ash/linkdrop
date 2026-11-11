import 'dart:async';

import 'package:flutter/services.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import '../utils/share_inbox.dart';

class ShareIntentService {
  ShareIntentService._();

  static final ShareIntentService instance = ShareIntentService._();

  static const _channel = MethodChannel('linkdrop/share_text');

  final _inbox = ShareInbox();
  Stream<String> get sharedText => _inbox.stream;

  StreamSubscription<List<SharedMediaFile>>? _mediaSub;

  /// Shares received before `LibraryScreen` subscribed (cold start).
  /// Callers should read and clear this on mount.
  List<String> consumePending() => _inbox.consumePending();

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
        _inbox.add(call.arguments as String);
      }
    });

    // Never let a failing native/plugin call abort app start-up (and with it
    // the share that launched us).
    try {
      final initialNative = await _channel.invokeMethod<String>('getInitialText');
      if (initialNative != null && initialNative.isNotEmpty) {
        _inbox.add(initialNative);
      }
    } catch (_) {}

    try {
      final initial = await ReceiveSharingIntent.instance.getInitialMedia();
      for (final file in initial) {
        _emitIfText(file);
      }
      ReceiveSharingIntent.instance.reset();
    } catch (_) {}

    _mediaSub = ReceiveSharingIntent.instance.getMediaStream().listen((files) {
      for (final file in files) {
        _emitIfText(file);
      }
    }, onError: (_) {});
  }

  void _emitIfText(SharedMediaFile file) {
    final isTextLike = file.type == SharedMediaType.text || file.type == SharedMediaType.url;
    if (isTextLike && file.path.isNotEmpty) {
      _inbox.add(file.path);
    }
  }

  void dispose() {
    _mediaSub?.cancel();
    _inbox.dispose();
  }
}
