import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

// Decisive probe: the flutter_test fallback font draws every glyph as a square
// of exactly fontSize. Real Cairo has proportional, non-square advances. So the
// measured width of the same string under `fontFamily: 'Cairo'` vs the default
// tells us whether the FontLoader actually took effect.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final reg = await rootBundle.load('assets/fonts/Cairo-Regular.ttf');
    final loader = FontLoader('Cairo')..addFont(Future.value(reg));
    await loader.load();
  });

  testWidgets('which font is actually rasterized?', (tester) async {
    const s = 'مرحبا';
    const size = 20.0;

    await tester.pumpWidget(MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Column(mainAxisSize: MainAxisSize.min, children: const [
          Text(s, key: Key('cairo'),
              style: TextStyle(fontFamily: 'Cairo', fontSize: size)),
          Text(s, key: Key('none'), style: TextStyle(fontSize: size)),
          Text(s, key: Key('bogus'),
              style: TextStyle(fontFamily: 'NoSuchFamilyXyz', fontSize: size)),
        ]),
      ),
    ));

    double w(String k) => tester.getSize(find.byKey(Key(k))).width;
    final cairo = w('cairo');
    final none = w('none');
    final bogus = w('bogus');
    const square = 5 * size; // what the box font would give for 5 glyphs

    // ignore: avoid_print
    print('PROBE cairo=$cairo none=$none bogus=$bogus box_font_would_be=$square');
    // ignore: avoid_print
    print('PROBE cairo_is_box=${cairo == square} '
        'none_is_box=${none == square} bogus_is_box=${bogus == square}');
  });
}
