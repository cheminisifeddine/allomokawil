// Notification taps must always land somewhere.
//
// The founder's report, verbatim: «when i get a notification they are not
// clickble when i click on them nothing happens fix it». The API sends a link for
// a quote but `null` for a new message, a published project and a fresh review,
// and the screen dropped every link it did not already recognise — so two of the
// three rows on the founder's own screen were dead.
//
// These pin the rule that replaced it: the link first (it names an exact row),
// then the row's own type, and never a dead tap for a row the server can send.
import 'package:flutter_test/flutter_test.dart';

import 'package:allomokawil/src/models/notification.dart';

void main() {
  test('a project link opens that project, whichever dashboard wrote it', () {
    expect(notificationTarget('new_quote', '/dashboard/projects/12').toString(),
        'project:12');
    expect(notificationTarget('quote_accepted', '/w/projects/9').toString(),
        'project:9');
  });

  test('a chat link opens that conversation', () {
    expect(notificationTarget('new_message', '/chat/31').toString(), 'chat:31');
  });

  test('a message with no link still opens the inbox', () {
    expect(notificationTarget('new_message', null).toString(), 'inbox');
    expect(notificationTarget('new_message', '').toString(), 'inbox');
  });

  test('a published project with no link still opens the projects list', () {
    expect(notificationTarget('project_update', null).toString(), 'projects');
    expect(notificationTarget('new_quote', null).toString(), 'projects');
  });

  test('a review opens the profile it is about', () {
    expect(notificationTarget('review_received', null).toString(), 'profile');
    expect(notificationTarget('review_received', '/w/profile').toString(),
        'profile');
  });

  test('only a row with nothing behind it reports none', () {
    expect(notificationTarget('something_new', null).isNone, isTrue);
  });
}
