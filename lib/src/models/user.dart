import 'enums.dart';

/// A registered account. Mirrors `User` from finili types.
class User {
  final int id;
  final String phone;
  final String? email;
  final String fullName;
  final UserRole type;
  final String? avatarUrl;
  final String? wilaya;
  final String? commune;

  const User({
    required this.id,
    required this.phone,
    this.email,
    required this.fullName,
    required this.type,
    this.avatarUrl,
    this.wilaya,
    this.commune,
  });

  /// Builds an account from one server row, or refuses.
  ///
  /// **This is the fifth and last file in the `as String?` family, and the
  /// only one of the five that is NOT read through `repository._rows`** — so
  /// the family's usual promise, "one unreadable row costs that row and
  /// nothing else", is false here and must not be copied into this file's
  /// reasoning. There are exactly two callers and both are whole-account:
  /// `AuthState._session` (`core/security/auth_state.dart:527`) for
  /// `/api/login` and `/api/register`, and `AuthState._readUser`
  /// (`auth_state.dart:362`) for the session envelope read on **every
  /// launch**. A cast that throws here does not drop a row; it drops the
  /// session, or fails the sign-in.
  ///
  /// So the rule is not "an unreadable field is a missing field". It is
  /// **an account with no readable identity is not an account**, and the
  /// three columns that carry that identity refuse instead of guessing:
  ///
  ///  * [id] keys the signed-in subtree in `app.dart:90`, is `_me` in
  ///    `chat_screen.dart:81`, and resolves which side of a conversation the
  ///    user is in `notifications_screen.dart:308`. Answering an unreadable
  ///    id with `0` — what `_int` does everywhere else in this family —
  ///    would restore a **signed-in user who is nobody**: the session looks
  ///    valid, the home screen draws, and every one of those comparisons is
  ///    silently false. That is strictly worse than being signed out,
  ///    because nothing on screen shows it.
  ///  * [phone] is the account key on `/api/login` and the only way the
  ///    profile screen reaches the user («رقم الهاتف»).
  ///  * [type] picks the dashboard (`app.dart:92`), and `UserRole.from`
  ///    answers `customer` for anything it does not recognise — which is
  ///    correct for a guest choosing between two buttons and **wrong** for a
  ///    server that answered a role this build has never heard of.
  ///    `profile_screen.dart:87` shows a contractor his portfolio only when
  ///    `u.type == UserRole.worker`, so defaulting a drifted role signs a
  ///    contractor into the wrong half of the app on every launch.
  ///
  /// The four optional columns are tolerant, because a missing avatar, email,
  /// wilaya or commune is a normal account and every one of them has a
  /// standard answer for "not supplied".
  ///
  /// Wire shape observed live on 2 Oct 2026 against the deployed API:
  /// `{"id":430,"phone":"0550000000","email":null,"full_name":"Probe Test",
  ///   "type":"customer","avatar_url":null,"wilaya":null,"commune":null}`
  factory User.fromJson(Map<String, dynamic> json) => User(
        id: _identityInt(json['id'], 'id'),
        phone: _identityText(json['phone'], 'phone'),
        email: _email(json['email']),
        fullName: _name(json['full_name']),
        type: _role(json['type']),
        avatarUrl: _optionalText(json['avatar_url']),
        wilaya: _code(json['wilaya']),
        commune: _code(json['commune']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'phone': phone,
        'email': email,
        'full_name': fullName,
        'type': type.wire,
        'avatar_url': avatarUrl,
        'wilaya': wilaya,
        'commune': commune,
      };
}

/// A column the server answered in a shape that is not an account.
///
/// An `Error`, not an `Exception`, on purpose: every caller of
/// [User.fromJson] already treats "this is not a session" as a hard refusal —
/// `_session` converts it to the same Arabic [ApiException] as every other bad
/// shape, and `_readUser` returns null — so nothing relies on catching this by
/// type. What it carries is for the support log `repository._whyRowFailed`
/// already writes, and it is never shown on a screen.
class UnreadableUser implements Exception {
  UnreadableUser(this.column, this.value);

  /// The wire name of the column that could not be read.
  final String column;

  /// The value that could not be read, kept for the log and never displayed.
  final Object? value;

  @override
  String toString() => 'UnreadableUser($column)';
}

/// An integer that carries an identity: a number from a JSON body, a numeric
/// string from SQLite (`_asInt` in `data/repository.dart` names that shape in
/// its own doc), and **no answer at all** otherwise.
///
/// The `?? 0` that the other four files in this family use is exactly the
/// wrong thing here, and the reason is in the header: 0 is a real user id
/// nobody holds, so a parser that returned it would sign a drifted row in as a
/// plausible stranger. Refuse instead.
int _identityInt(Object? value, String column) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) {
    final parsed = int.tryParse(value.trim());
    if (parsed != null) return parsed;
  }
  throw UnreadableUser(column, value);
}

/// A string that carries an identity: present, a string, and not blank.
String _identityText(Object? value, String column) {
  final text = _text(value);
  if (text == null) throw UnreadableUser(column, value);
  return text;
}

/// A person's name.
///
/// Returns the **empty string** for a name that is only whitespace, rather
/// than refusing: the column is present, it is copy, and the app has a standard
/// answer for a nameless account (`Monogram.of('')` paints «؟», and
/// `customer_home_screen.dart:743` already greets with `null` when the trimmed
/// name is empty). Refusing here would sign the user out over a blank name,
/// which is a worse trade than drawing «؟».
///
/// A name that is **not a string** is refused. Flattening would put «5» where a
/// person's name goes, on the profile header and in the home greeting.
String _name(Object? value) {
  if (value is! String) throw UnreadableUser('full_name', value);
  return value.trim();
}

/// The role, refused when it is not one this build knows.
///
/// Not [UserRole.from]: that answers `customer` for `null`, for `''` and for a
/// fourth role the server invented, and every one of those is a real shape —
/// `auth_state.dart:30` writes `role.wire` on the way out, so a renamed server
/// column arrives as `null` here. See the header for what defaulting costs.
UserRole _role(Object? value) {
  if (value is String) {
    final name = value.trim();
    for (final role in UserRole.values) {
      if (role.name == name) return role;
    }
  }
  throw UnreadableUser('type', value);
}

/// Optional copy, trimmed, and absent when empty or not a string.
///
/// **Never flattened.** `avatar_url` is handed to `NetImage`, where a
/// flattened number is a request to a host that does not exist, and null falls
/// back to the monogram the widget already draws.
String? _optionalText(Object? value) => _text(value);

/// The email, which is the one optional column that keeps an empty string.
///
/// Not a style choice: the app sends `email: ''` on every registration, by the
/// founder's call — «remove the email from sign up or sign in just keep phone
/// number only» (`auth_screen.dart:162`). So `''` is a **real answer** that
/// round-trips through `toJson` into the stored session envelope, and nulling
/// it would make the second launch after sign-in disagree with the first.
String? _email(Object? value) {
  if (value is! String) return null;
  return value.trim();
}

/// A geography **code**: `wilaya` and `commune` are ids, not sentences, and
/// `Taxonomy.wilayaNameOrNull` (`data/taxonomy.dart:308`) is keyed on a string.
///
/// So a code that arrives as a number is flattened here rather than dropped —
/// this is a real shape, not a hypothetical one: `api_shape_guard_test.dart:103`
/// feeds `user_wilaya: 16`, which is what SQLite hands back for a code column.
/// Flattening it to `'16'` is what lets the profile print «الجزائر» instead of
/// dropping the row, and the flattened value is what `wilayaNameOrNull` is
/// looking for.
///
/// An absent or blank code stays null, and `profile_screen.dart:58` already
/// drops the row for a code it cannot resolve rather than printing the «—»
/// fallback.
String? _code(Object? value) {
  if (value is String) return _text(value);
  if (value is num) return value.toInt().toString();
  return null;
}

/// Copy, trimmed, or null when absent/empty/not a string.
String? _text(Object? value) {
  if (value is! String) return null;
  final v = value.trim();
  return v.isEmpty ? null : v;
}
