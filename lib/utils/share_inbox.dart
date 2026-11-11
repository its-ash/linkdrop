import 'dart:async';

/// Delivers shared text to a (possibly not yet mounted) listener.
///
/// The same share reaches Dart through two native paths (our MethodChannel
/// and `receive_sharing_intent`), so identical text arriving within
/// [duplicateWindow] is collapsed. Identical text arriving later is a genuine
/// re-share (e.g. retrying a failed Instagram link) and must NOT be dropped.
class ShareInbox {
  ShareInbox({this.duplicateWindow = const Duration(seconds: 3), DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final Duration duplicateWindow;
  final DateTime Function() _clock;
  final _controller = StreamController<String>.broadcast();

  Stream<String> get stream => _controller.stream;

  String? _lastText;
  DateTime? _lastAt;
  final List<String> _pending = [];

  /// Shares received before anyone listened (cold start), oldest first.
  List<String> consumePending() {
    final out = List<String>.from(_pending);
    _pending.clear();
    return out;
  }

  void add(String text) {
    final now = _clock();
    if (text == _lastText && _lastAt != null && now.difference(_lastAt!) < duplicateWindow) {
      return;
    }
    _lastText = text;
    _lastAt = now;
    if (_controller.hasListener) {
      _controller.add(text);
    } else {
      _pending.add(text);
    }
  }

  void dispose() => _controller.close();
}
