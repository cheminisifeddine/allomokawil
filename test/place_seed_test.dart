// Where the phone is decides what the app puts in front of the visitor.
//
// The founder, verbatim: «ask for gps fird thing when the user open the app so
// you show related offers to him. And get accurate offers too».
//
// Two screens answer that brief, and both are pinned here: the contractor's
// market opens filtered on the wilaya the phone answered with, and the client's
// «top rated» strip leads with the contractors who work in that wilaya. The
// third test is the promise that makes the first two safe: with no answer from
// the phone, nothing is filtered and nothing is reordered.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:allomokawil/src/core/app_scope.dart';
import 'package:allomokawil/src/core/location/locator.dart';
import 'package:allomokawil/src/core/location/place_state.dart';
import 'package:allomokawil/src/core/network/api_client.dart';
import 'package:allomokawil/src/core/security/auth_state.dart';
import 'package:allomokawil/src/data/repository.dart';
import 'package:allomokawil/src/models/enums.dart';
import 'package:allomokawil/src/screens/customer/customer_home_screen.dart';
import 'package:allomokawil/src/screens/worker/worker_home_screen.dart';

const _algiers = DetectedPlace(
  wilayaId: '16',
  wilayaName: 'الجزائر',
  commune: 'باب الوادي',
  lat: 36.75,
  lng: 3.06,
  seatKm: 2.1,
  communeFromDevice: true,
);

Map<String, Object?> _workerJson(int id, String name, String wilaya) => {
      'id': id,
      'user_id': id,
      'full_name': name,
      'specialties': <String>['painting'],
      'experience_years': 6,
      'service_radius_km': 25,
      'verification_status': 'verified',
      'verification_pending_docs': 0,
      'avg_rating': 4.8,
      'total_reviews': 12,
      'wilaya': wilaya,
    };

/// Records every URL the app asks for, so a test can assert on the query.
final _asked = <Uri>[];

MockClient _recorder(List<Object> Function(Uri) answer) =>
    MockClient((req) async {
      _asked.add(req.url);
      return http.Response(
        jsonEncode(answer(req.url)),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

Future<({ApiClient api, AuthState auth, Repository repo})> _boot(
    MockClient client) async {
  SharedPreferences.setMockInitialValues({});
  final api = ApiClient(httpClient: client, baseUrls: ['https://x.test']);
  final auth = AuthState(api);
  await auth.restore();
  await auth.enterAsGuest(UserRole.worker);
  return (api: api, auth: auth, repo: Repository(api));
}

Future<void> _pump(
  WidgetTester tester,
  Widget screen,
  ApiClient api,
  AuthState auth,
  PlaceState place, {
  Size size = const Size(392, 1400),
}) async {
  tester.view.physicalSize = size * 2.75;
  tester.view.devicePixelRatio = 2.75;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(MaterialApp(
    home: AppScope(
      api: api,
      auth: auth,
      place: place,
      // `MarketplaceView` is a body, not a page: it is the tab's content inside
      // `WorkerHomeScreen`. A Scaffold here is what the tab provides.
      child: Scaffold(body: screen),
    ),
  ));
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

void main() {
  setUp(_asked.clear);

  testWidgets('the market opens on the wilaya the phone answered with',
      (tester) async {
    final s = await _boot(_recorder((uri) => <Object>[]));
    final place = PlaceState.detached()..seed(_algiers);

    await _pump(tester, MarketplaceView(repo: s.repo, guest: true), s.api,
        s.auth, place);

    final browse =
        _asked.where((u) => u.path.contains('/projects')).toList();
    expect(browse, isNotEmpty, reason: 'the market reads the open projects');
    expect(browse.first.queryParameters['wilaya'], '16',
        reason: 'the offers a contractor sees first are the ones he can reach');

    // And the chip says so, rather than looking like a filter he chose.
    expect(find.text('الجزائر'), findsWidgets);
  });

  testWidgets('a visitor with no fix gets the whole country, unfiltered',
      (tester) async {
    final s = await _boot(_recorder((uri) => <Object>[]));

    await _pump(tester, MarketplaceView(repo: s.repo, guest: true), s.api,
        s.auth, PlaceState.detached());

    final browse =
        _asked.where((u) => u.path.contains('/projects')).toList();
    expect(browse, isNotEmpty);
    expect(browse.first.queryParameters['wilaya'], isNull);
    expect(find.text('كل الولايات'), findsWidgets);
  });

  testWidgets('the client home leads with the contractors who work nearby',
      (tester) async {
    final s = await _boot(_recorder((uri) {
      if (uri.path.contains('/workers/top')) {
        // The server's own order: the best rated first, in another wilaya.
        return [
          _workerJson(1, 'Far Rated', '09'),
          _workerJson(2, 'Near Rated', '16'),
        ];
      }
      return <Object>[];
    }));
    final place = PlaceState.detached()..seed(_algiers);

    await _pump(tester, const CustomerHomeScreen(), s.api, s.auth, place);

    final near = find.text('Near Rated');
    final far = find.text('Far Rated');
    expect(near, findsOneWidget);
    expect(far, findsOneWidget);
    expect(tester.getTopLeft(near).dx, lessThan(tester.getTopLeft(far).dx),
        reason: 'a pro in the visitor\'s wilaya leads the strip');
  });
}
