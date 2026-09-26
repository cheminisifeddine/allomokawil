// Renders the two surfaces the invented-wilaya fix touches, with a project the
// server sent **without** a wilaya, and with the same project in a real one, so
// the two captures can be compared by eye.
//
// The claim being checked is a layout claim — "the place row is gone, and the
// card closes up instead of leaving a gap" — and a claim about pixels is only
// worth anything with pixels attached, so this writes real PNGs to /tmp/shots.
// Run:  flutter test test/wilaya_shot_test.dart
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:allomokawil/src/core/app_scope.dart';
import 'package:allomokawil/src/core/network/api_client.dart';
import 'package:allomokawil/src/core/security/auth_state.dart';
import 'package:allomokawil/src/core/theme/app_theme.dart';
import 'package:allomokawil/src/data/repository.dart';
import 'package:allomokawil/src/models/project.dart';
import 'package:allomokawil/src/widgets/project_card.dart';

const _outDir = '/tmp/shots';

/// The same job, three ways the server can answer it.
///
/// [blank] is the shape the fix is about: `Project.fromJson` reads
/// `wilaya: (json['wilaya'] as String?) ?? ''`, so a row sent without the field
/// arrives here as `''` — not as null, and not as a wilaya.
Map<String, dynamic> _project(String id, {Object? wilaya, String? commune}) => {
      'id': id,
      'customer_id': 30,
      'title': 'دهان شقة 3 غرف',
      'description': 'دهان كامل للشقة مع إصلاح الجدران المتضررة',
      'category': 'painting',
      'images': <String>[],
      if (wilaya != null) 'wilaya': wilaya,
      if (commune != null) 'commune': commune,
      'budget_min': 60000,
      'budget_max': 90000,
      'urgency': 'within_week',
      'status': 'open',
      'selected_worker_id': null,
      'created_at': '2026-09-11 20:23:44',
      'updated_at': '2026-09-11 20:23:44',
    };

http.Response _json(Object body) => http.Response(jsonEncode(body), 200,
    headers: {'content-type': 'application/json'});

/// Three cards in one list: real wilaya, no wilaya, and a code this build has
/// never heard of — the three renderings the fix has to get right.
final _list = [
  _project('a', wilaya: '16', commune: 'حسين داي'),
  _project('b'),
  _project('c', wilaya: '59'),
];

ApiClient _api() => ApiClient(
      baseUrls: ['https://x.test'],
      httpClient: MockClient((req) async {
        final p = req.url.path;
        if (p.endsWith('/api/login') || p.endsWith('/api/register')) {
          return _json({
            'token': 'tok',
            'user': {
              'id': 30,
              'phone': '0773000000',
              'email': null,
              'full_name': 'زبون تجربة',
              'type': 'customer',
              'avatar_url': null,
              'wilaya': '16',
              'commune': null,
            },
          });
        }
        if (p.contains('/projects')) return _json(_list);
        return _json(<String, Object?>{});
      }),
    );

void main() {
  setUpAll(() => Directory(_outDir).createSync(recursive: true));

  testWidgets('the place row is dropped, not filled with Algiers',
      (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final api = _api();
    final auth = AuthState(api);
    await auth.restore();
    await auth.login(
        phone: '0773000000', password: 'secret123', rememberMe: true);

    tester.view.physicalSize = const Size(392, 850) * 2.75;
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);

    final key = GlobalKey();
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: RepaintBoundary(
        key: key,
        child: AppScope(
          api: api,
          auth: auth,
          child: Scaffold(
            body: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                for (final p in _list) ProjectCard(project: Project.fromJson(p)),
              ],
            ),
          ),
        ),
      ),
    ));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 80));
    }

    final boundary =
        key.currentContext!.findRenderObject() as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 3.0);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      File('$_outDir/20_wilaya_truth.png')
          .writeAsBytesSync(bytes!.buffer.asUint8List());
    });

    // The pixels are the proof, but the assertion is the cheap one: the first
    // card names its wilaya, the other two must name no place at all.
    expect(find.text('الجزائر'), findsNWidgets(1),
        reason: 'only the card that really is in Algiers may name it');
    expect(find.textContaining('وهران'), findsNothing);
  });
}
