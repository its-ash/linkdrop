import 'package:flutter_test/flutter_test.dart';
import 'package:linkdrop/utils/share_inbox.dart';
import 'package:linkdrop/utils/share_parser.dart';

void main() {
  group('extractUrl with realistic Instagram payloads', () {
    final cases = <String, String>{
      'https://www.instagram.com/reel/C7abcDEF123/?igsh=MTIzNDU2Nzg5MA==':
          'https://www.instagram.com/reel/C7abcDEF123/?igsh=MTIzNDU2Nzg5MA==',
      'Check this out https://www.instagram.com/p/CxYz_12-ab/?utm_source=ig_web_copy_link':
          'https://www.instagram.com/p/CxYz_12-ab/?utm_source=ig_web_copy_link',
      'Look at this reel (https://www.instagram.com/reel/ABC123/).':
          'https://www.instagram.com/reel/ABC123/',
      'https://www.instagram.com/share/reel/BAHxYz12/\n':
          'https://www.instagram.com/share/reel/BAHxYz12/',
      'https://instagr.am/p/ABC123/': 'https://instagr.am/p/ABC123/',
      'watch: https://example.com/a.mp4, then https://www.instagram.com/reel/ZZ9/':
          'https://www.instagram.com/reel/ZZ9/',
    };
    cases.forEach((input, expected) {
      test(input.replaceAll('\n', r'\n'), () => expect(extractUrl(input), expected));
    });

    test('no link', () => expect(extractUrl('hello world'), isNull));
  });

  group('parseInstagramPost', () {
    test('reel, p, tv, reels, username prefix, m. host', () {
      expect(parseInstagramPost('https://www.instagram.com/reel/ABC/?igsh=x')?.code, 'ABC');
      expect(parseInstagramPost('https://instagram.com/p/ABC')?.kind, 'p');
      expect(parseInstagramPost('https://www.instagram.com/tv/ABC/')?.kind, 'tv');
      expect(parseInstagramPost('https://www.instagram.com/reels/ABC/')?.kind, 'reel');
      expect(parseInstagramPost('https://www.instagram.com/someuser/reel/ABC/')?.code, 'ABC');
      expect(parseInstagramPost('https://m.instagram.com/p/ABC/')?.code, 'ABC');
    });
    test('login wall redirect keeps the post', () {
      final p = parseInstagramPost(
        'https://www.instagram.com/accounts/login/?next=%2Freel%2FABC123%2F&source=omni_redirect',
      );
      expect(p?.kind, 'reel');
      expect(p?.code, 'ABC123');
    });
    test('share and short links need a redirect; stories do not parse', () {
      expect(instagramNeedsRedirect('https://www.instagram.com/share/reel/BAHx/'), isTrue);
      expect(instagramNeedsRedirect('https://instagr.am/abcd'), isTrue);
      expect(instagramNeedsRedirect('https://ig.me/xyz'), isTrue);
      expect(instagramNeedsRedirect('https://www.instagram.com/reel/ABC/'), isFalse);
      expect(parseInstagramPost('https://www.instagram.com/stories/user/123/'), isNull);
      expect(isInstagramStory('https://www.instagram.com/stories/user/123/'), isTrue);
    });
    test('isInstagramUrl', () {
      expect(isInstagramUrl('https://l.instagram.com/x'), isTrue);
      expect(isInstagramUrl('https://notinstagram.com/x'), isFalse);
    });
  });

  group('normalizeUrl (duplicate detection)', () {
    test('tracking params and slashes collapse', () {
      final a = normalizeUrl('https://www.instagram.com/reel/ABC/?igsh=1');
      final b = normalizeUrl('https://instagram.com/reel/ABC?utm_source=ig_web_copy_link');
      final c = normalizeUrl('https://www.instagram.com/user/reel/ABC/');
      expect(a, b);
      expect(a, c);
    });
    test('non-instagram links keep meaningful params', () {
      expect(
        normalizeUrl('https://Example.com/f/?id=5&utm_source=x'),
        'https://example.com/f?id=5',
      );
    });
  });

  group('ShareInbox', () {
    test('cold start: shares before a listener are queued, not lost', () {
      final inbox = ShareInbox();
      inbox.add('https://www.instagram.com/reel/A/');
      inbox.add('https://www.instagram.com/reel/A/'); // plugin duplicate
      expect(inbox.consumePending(), ['https://www.instagram.com/reel/A/']);
      expect(inbox.consumePending(), isEmpty);
    });

    test('running app: delivers to listener; duplicate paths collapse', () async {
      final inbox = ShareInbox();
      final got = <String>[];
      inbox.stream.listen(got.add);
      inbox.add('x');
      inbox.add('x');
      await Future<void>.delayed(Duration.zero);
      expect(got, ['x']);
    });

    test('re-sharing the same link later (retry after failure) is delivered', () async {
      var now = DateTime(2026);
      final inbox = ShareInbox(clock: () => now);
      final got = <String>[];
      inbox.stream.listen(got.add);
      inbox.add('same');
      now = now.add(const Duration(seconds: 10));
      inbox.add('same');
      await Future<void>.delayed(Duration.zero);
      expect(got, ['same', 'same']);
    });
  });
}
