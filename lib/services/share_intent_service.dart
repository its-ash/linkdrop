import 'dart:async';

import 'package:receive_sharing_intent/receive_sharing_intent.dart';

class ShareIntentService {
  ShareIntentService._();

  static final ShareIntentService instance = ShareIntentService._();

  final _controller = StreamController<String>.broadcast();
  Stream<String> get sharedText => _controller.stream;

  StreamSubscription<List<SharedMediaFile>>? _mediaSub;

  /// Registers listeners for both a cold-start share (app launched via the
  /// share sheet) and subsequent shares while the app is already running.
  Future<void> init() async {
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
      _controller.add(file.path);
    }
  }

  void dispose() {
    _mediaSub?.cancel();
    _controller.close();
  }
}
