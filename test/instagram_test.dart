import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:linkdrop/services/instagram_extractor.dart';
import 'package:linkdrop/utils/share_parser.dart';

void main() {
  test('shortcodeToMediaId matches the id Instagram reports', () {
    // oembed: media_id 2913440072144448240_25025320
    expect(shortcodeToMediaId('Chunk8-jurw'), '2913440072144448240');
    expect(shortcodeToMediaId('CDUMkliABpa'), '2365570995034528346');
  });

  test('instagramSlideIndex', () {
    expect(instagramSlideIndex('https://www.instagram.com/p/ABC/?img_index=3'), 3);
    expect(instagramSlideIndex('https://www.instagram.com/p/ABC/'), isNull);
    expect(instagramSlideIndex('https://www.instagram.com/p/ABC/?img_index=0'), isNull);
  });

  group('parseInstagramHtml', () {
    test('post page JSON (xig_polaris_media) picks the largest video', () {
      final data = {
        'require': [
          [
            'ScheduledServerJS',
            {
              '__bbox': {
                'result': {
                  'data': {
                    'xig_polaris_media': {
                      'if_not_gated_logged_out': {
                        'code': 'ABC',
                        'video_versions': [
                          {'type': 101, 'url': 'https://cdn/small.mp4', 'width': 360, 'height': 640},
                          {'type': 102, 'url': 'https://cdn/big.mp4', 'width': 720, 'height': 1280},
                        ],
                        'image_versions2': {
                          'candidates': [
                            {'url': 'https://cdn/thumb.jpg', 'width': 720, 'height': 1280},
                          ],
                        },
                      },
                    },
                  },
                },
              },
            },
          ],
        ],
      };
      final html = '<html><script type="application/json" data-sjs>${jsonEncode(data)}</script></html>';
      final media = parseInstagramHtml(html, 'ABC');
      expect(media, hasLength(1));
      expect(media.single.url, 'https://cdn/big.mp4');
      expect(media.single.isVideo, isTrue);
      expect(media.single.extension, 'mp4');
    });

    test('carousel of image + video', () {
      final node = {
        'code': 'CAR',
        'carousel_media': [
          {
            'image_versions2': {
              'candidates': [
                {'url': 'https://cdn/1.jpg', 'width': 1080, 'height': 1080},
                {'url': 'https://cdn/1s.jpg', 'width': 320, 'height': 320},
              ],
            },
          },
          {
            'video_versions': [
              {'url': 'https://cdn/2.mp4', 'width': 720, 'height': 720},
            ],
            'image_versions2': {
              'candidates': [
                {'url': 'https://cdn/2.jpg', 'width': 720, 'height': 720},
              ],
            },
          },
        ],
      };
      final html = '<script type="application/json">${jsonEncode({'x': node})}</script>';
      final media = parseInstagramHtml(html, 'CAR');
      expect(media.map((m) => m.url), ['https://cdn/1.jpg', 'https://cdn/2.mp4']);
      expect(media.map((m) => m.isVideo), [false, true]);
    });

    test('old GraphQL shape (xdt_shortcode_media with sidecar)', () {
      final json = {
        'data': {
          'xdt_shortcode_media': {
            'shortcode': 'OLD',
            'edge_sidecar_to_children': {
              'edges': [
                {
                  'node': {'display_url': 'https://cdn/a.jpg'},
                },
                {
                  'node': {'video_url': 'https://cdn/b.mp4', 'display_url': 'https://cdn/b.jpg'},
                },
              ],
            },
          },
        },
      };
      final media = mediaFromAnyJson(json, 'OLD');
      expect(media.map((m) => m.url), ['https://cdn/a.jpg', 'https://cdn/b.mp4']);
    });

    test('prefers the node whose code matches over related posts', () {
      final json = {
        'related': {
          'code': 'OTHER',
          'video_versions': [
            {'url': 'https://cdn/other.mp4'},
          ],
        },
        'post': {
          'code': 'MINE',
          'video_versions': [
            {'url': 'https://cdn/mine.mp4'},
          ],
        },
      };
      expect(mediaFromAnyJson(json, 'MINE').single.url, 'https://cdn/mine.mp4');
    });

    test('loose scan finds video_versions inside a script that is not JSON', () {
      const html =
          '<script>require("x").handle({"items":[{"video_versions":[{"url":"https:\\/\\/cdn\\/v.mp4","width":10,"height":10}]}]});</script>';
      expect(parseInstagramHtml(html, 'X').single.url, 'https://cdn/v.mp4');
    });

    test('og:video fallback', () {
      const html = '<meta property="og:video" content="https://cdn/og.mp4?a=1&amp;b=2" />';
      expect(parseInstagramHtml(html, 'X').single.url, 'https://cdn/og.mp4?a=1&b=2');
    });

    test('a page with no media gives nothing', () {
      expect(parseInstagramHtml('<html><body>Log in</body></html>', 'X'), isEmpty);
    });
  });

  test('readJsonValueAt handles nesting, strings with brackets and escapes', () {
    const s = 'x: {"a":"}]\\"","b":[1,{"c":2}]} tail';
    expect(readJsonValueAt(s, 2), '{"a":"}]\\"","b":[1,{"c":2}]}');
    expect(readJsonValueAt('"k": "v\\"x" ,', 4), '"v\\"x"');
    expect(readJsonValueAt('{"a":1', 0), isNull);
  });
}
