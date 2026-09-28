import 'package:flutter/material.dart';

import '../core/app_scope.dart';
import '../core/auth_gate.dart';
import '../core/l10n/strings.dart';
import '../core/theme/app_theme.dart';
import '../data/notification_count_trust.dart';
import '../data/repository.dart';
import '../screens/notifications/notifications_screen.dart';

/// Bell plus unread pip for the two home headers.
///
/// The count comes from the same `/api/unread` endpoint the message tab
/// already trusts. A failed call keeps the last known count instead of
/// painting an error on the header, and the count is refreshed on the way back
/// from the centre, so opening a notification clears the pip.
///
/// **The count is also refreshed when the app comes back to the foreground**,
/// which is the moment it actually goes stale. Before this, `_refresh` ran
/// once from `didChangeDependencies` and the bell was then correct only until
/// the phone was locked — and nothing in the app observed the lifecycle at all
/// (`WidgetsBindingObserver` appears nowhere in `lib/`), so a quote that landed
/// while the contractor was in another app left a header that said «nothing
/// new» until he happened to open the centre. The pip is the one line on the
/// home screen that claims something arrived, so a pip that cannot go up is the
/// worst possible failure for it: it does not look broken, it looks like a
/// quiet day.
class NotificationsBell extends StatefulWidget {
  const NotificationsBell({
    super.key,
    this.repo,
    this.onNavy = false,
    this.trust,
  });

  /// Injected by tests and by callers that already hold a repository.
  final Repository? repo;

  /// Shared with the notification centre, so a write the app could not confirm
  /// stops the header from reasserting the count as fact.
  ///
  /// Null means every count is trusted — the right default for the headers that
  /// open the centre themselves, and for any caller with no centre to disagree
  /// with. See `notification_count_trust.dart` for why a *list* read is not
  /// enough to restore it.
  final NotificationCountTrust? trust;

  /// Draw for a navy header instead of a white app bar.
  final bool onNavy;

  @override
  State<NotificationsBell> createState() => _NotificationsBellState();
}

class _NotificationsBellState extends State<NotificationsBell>
    with WidgetsBindingObserver {
  late final Repository _repo;
  bool _wired = false;
  int _unread = 0;

  /// The centre the user just left, when it could not confirm its own write.
  ///
  /// Held rather than read once, because the withdrawal can land while this
  /// header is already on screen: a SnackBar verdict from a screen below is
  /// delivered before the pop, and the count has to react to both. `mounted`
  /// is checked on every callback — the pop disposes this state right after.
  NotificationCountTrust? _trust;

  /// One read in flight at a time.
  ///
  /// A phone can resume, background and resume again in the time one request
  /// takes on a 3G bar, and each of those starts another. Without this the
  /// slower answer wins the `setState`, so the pip can end up showing the
  /// count from *before* the newer read — a badge that goes backwards on
  /// resume, which is worse than a stale one.
  bool _refreshing = false;

  /// A read was asked for while another was in flight, and it is not the same
  /// question — see [_refresh].
  ///
  /// **This flag exists because the guard above was swallowing the one read
  /// that cannot be dropped.** Coalescing is right only when the two asks are
  /// the same question: two resumes inside one frame both mean «what is
  /// unread right now», and the answer already in flight is that answer. The
  /// read that follows coming back from the centre is *not* the same
  /// question. The user has just marked notifications read, and the read in
  /// flight was issued before that write, so it is holding a snapshot of a
  /// world that has since moved on. Silently dropping the correcting ask left
  /// the header painted with the count from before he emptied the centre: a
  /// pip standing over a screen he just cleared, disagreeing with it in
  /// public, and never re-read — because nothing else observes the count until
  /// he leaves the app and comes back, which is the one thing the resume
  /// refresh is there to prevent.
  ///
  /// So a superseding ask is remembered and served as soon as the in-flight
  /// read returns, and that read's own answer is **not painted**: it is a
  /// number the user has already been shown to be out of date, and flashing
  /// it for the length of one request is the same lie held for shorter.
  bool _superseded = false;

  @override
  void initState() {
    super.initState();
    // Registered here rather than in `didChangeDependencies` because the
    // observer is about the engine, not about this screen's dependencies.
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _trust?.removeListener(_onTrustChanged);
    super.dispose();
  }

  /// The centre withdrew confidence in the count; stop painting it as one.
  void _onTrustChanged() {
    if (!mounted) return;
    setState(() {});
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_wired) {
      return;
    }
    _wired = true;
    _repo = widget.repo ?? Repository(AppScope.of(context).api);
    _trust = widget.trust;
    _trust?.addListener(_onTrustChanged);
    _refresh();
  }

  /// Android delivers this on every return to the foreground, and iOS too.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Only `resumed`. `inactive` fires when a dialog, the app switcher or a
    // permission sheet comes over the top, and the app is still not usable —
    // asking the network there spends the user's data to draw the same number
    // they will see a moment later anyway.
    if (state != AppLifecycleState.resumed) {
      return;
    }
    // `_repo` is assigned in `didChangeDependencies`, which the engine can
    // reach before it delivers the first lifecycle message. Reading a `late
    // final` then throws inside a framework callback, where it is swallowed
    // as a red-screen report about a bug the user never caused.
    if (!_wired) {
      return;
    }
    _refresh();
  }

  /// Reads the pip's number.
  ///
  /// [force] is the difference between *the same question twice* and *a
  /// different one*. A lifecycle resume leaves it false, so a second resume
  /// inside the same frame is coalesced into the read already open. Coming
  /// back from the centre passes true, because the count the in-flight read is
  /// holding predates the write the user just made.
  Future<void> _refresh({bool force = false}) async {
    if (_refreshing) {
      if (!force) {
        return;
      }
      // Answered by the in-flight read's own completion, not queued behind a
      // second open request: one read is still enough to find out.
      _superseded = true;
      return;
    }
    _refreshing = true;
    try {
      final n = await _repo.unreadCount();
      if (!mounted) {
        return;
      }
      if (_superseded) {
        // A newer ask arrived while this was open, so this number is already
        // known to be behind and is not drawn at all.
        return;
      }
      setState(() {
        _unread = n;
        // The server answered, so the count is its number again — even if the
        // centre withdrew confidence a moment ago.
        _trust?.restore();
      });
    } catch (_) {
      // Keep the last known count: a dropped request is not a broken header.
      //
      // **And keep the withdrawal in place, which is the half this used to
      // lose.** A failed read proves nothing either way, so the count stays
      // whatever it was — but restoring trust here would be a claim the
      // transport never made, and on the one path that matters it undoes a
      // sentence the user has already read. The centre says «تعذّر التأكّد»,
      // the pop-back read then fails on the same bad bar, and a `restore()`
      // here would repaint the disclaimed number in confidence with nothing on
      // screen to explain why. So the catch changes nothing, and the muted pip
      // survives until a read actually lands.
    } finally {
      _refreshing = false;
      if (_superseded) {
        _superseded = false;
        await _refresh(force: true);
      }
    }
  }

  Future<void> _open() async {
    // Signed out there is no inbox to open; the bell is still drawn so the app
    // looks the same either way, and the tap leads to the account form.
    if (!await AuthGate.requireAuth(context, what: 'لقراءة إشعاراتك')) return;
    if (!mounted) return;
    // The centre gets the same trust flag this header reads, so a write it
    // could not confirm withdraws the count on both sides of the navigation
    // instead of leaving the header to redraw the number it disclaimed.
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => NotificationsScreen(repo: _repo, trust: widget.trust),
      ),
    );
    if (mounted) {
      // Forced: he may have marked things read in there, and the count the
      // in-flight read is holding was asked for before he did.
      await _refresh(force: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ink = widget.onNavy ? AppTheme.onNavy : AppTheme.navy;
    return Semantics(
      button: true,
      label: S.notifications,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          IconButton(
            key: const Key('notifications-bell'),
            icon: Icon(Icons.notifications_none_rounded, color: ink),
            tooltip: S.notifications,
            onPressed: _open,
          ),
          if (_unread > 0) _pip(),
        ],
      ),
    );
  }

  /// The unread count itself, and the one place in the app where a number is
  /// drawn in alarm red with no sentence attached.
  ///
  /// **That is why the colour had to change.** Red is the app's «this is
  /// wrong / act now» voice — it is used for the danger banner and the failed
  /// form, never for anything merely *present*. So when the centre has said
  /// out loud that it cannot check the count, painting the same number in the
  /// same red does not soften the claim, it re-issues it: the user reads
  /// «تعذّر التأكّد» in the centre and «3» in red on the header, and the colour
  /// is louder than the sentence, so the withdrawn answer wins.
  ///
  /// A muted fill says the same number is *not confirmed* rather than *is
  /// urgent*, and it is the same visual weight — the pip does not vanish and
  /// become easy to miss, it just stops claiming. White on `textMuted` is
  /// 4.96:1, the same 11 px weight the confirmed pip uses, so nothing but the
  /// colour distinguishes the two states.
  Widget _pip() {
    final unconfirmed = _trust?.unconfirmed ?? false;
    return PositionedDirectional(
      top: 4,
      end: 2,
      child: IgnorePointer(
        child: Semantics(
          // Read instead of the bare digits when the count is a guess, so the
          // state is announced rather than only painted — colour is the one
          // difference a screen reader cannot see.
          label: unconfirmed ? S.notifCountUnconfirmed : null,
          child: Container(
            key: const Key('notifications-badge'),
            constraints: const BoxConstraints(minWidth: 18),
            padding: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              color: unconfirmed ? AppTheme.textMuted : AppTheme.danger,
              borderRadius: BorderRadius.circular(AppTheme.rPill),
              border: Border.all(color: AppTheme.surface, width: 1.5),
            ),
            child: Text(
              _unread > 99 ? '99+' : '$_unread',
              textAlign: TextAlign.center,
              style: AppTheme.caption.copyWith(
                fontSize: AppTheme.fsBadge,
                color: AppTheme.onNavy,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
