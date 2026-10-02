import 'dart:async';

import 'package:flutter/material.dart';

import '../core/app_scope.dart';
import '../core/auth_gate.dart';
import '../core/theme/app_theme.dart';
import '../data/repository.dart';
import '../data/taxonomy.dart';
import '../models/enums.dart';
import '../models/plan.dart';
import '../widgets/a11y.dart';
import '../widgets/ui.dart';
import 'verify/verification_screen.dart';
import 'worker/my_portfolio_screen.dart';
import 'worker/profile_edit_screen.dart';
import 'worker/subscription_screen.dart';

/// Lightweight account screen shared by both roles: identity info,
/// wilaya help, and logout.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key, this.clock});

  /// The wall clock, injectable so a test can move the subscription row's
  /// answer across a midnight without waiting for one. Defaults to the system
  /// clock in the app.
  ///
  /// Same seam, same reason, as [SubscriptionScreen.clock]: that screen ages
  /// its own readings once a minute, this one cannot be moved at all by a test.
  /// **The account tab is the worse of the two.** It lives inside the shell's
  /// `IndexedStack` (see `worker_home_screen.dart`), so it is built once and
  /// then stays mounted for the whole session — the «اشتراكي» line keeps the
  /// value `_planSummary` computed when the read first landed, and a
  /// contractor who leaves the app open across his plan's end date is told he
  /// is still «نشط» long after the cover has run out. In the app this reads
  /// correct right up to the moment it stops being correct, which is the
  /// expensive kind of wrong.
  final DateTime Function()? clock;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final user = scope.auth.user;

    // Signed out the account tab is the visitor's own page: same shape, same
    // app bar, and the one door that leads to a real account.
    if (user == null) {
      return _GuestAccountScreen(
          role: scope.auth.guestRole ?? UserRole.customer);
    }

    final u = user;
    final commune = u.commune?.trim();

    return Scaffold(
      appBar: AppBar(
        title: Text('حسابي', style: AppTheme.bar),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 28),
        children: [
          // ── Identity ───────────────────────────────────────────────────
          _ProfileHeader(name: u.fullName, role: u.type),

          // ── Account details ────────────────────────────────────────────
          const SectionTitle('معلومات الحساب', icon: Icons.badge_outlined),
          AppCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                _SettingsRow(
                  icon: Icons.phone_rounded,
                  title: 'رقم الهاتف',
                  value: u.phone,
                ),
                // Not `u.wilaya != null`: an empty or unrecognised code is
                // not a wilaya, and the row used to print the fallback name
                // for one. Dropped, like the commune row below it.
                if (Taxonomy.wilayaNameOrNull(u.wilaya) case final wilaya?) ...[
                  const _RowDivider(),
                  _SettingsRow(
                    icon: Icons.location_on_rounded,
                    title: 'الولاية',
                    value: wilaya,
                  ),
                ],
                if (commune != null && commune.isNotEmpty) ...[
                  const _RowDivider(),
                  _SettingsRow(
                    icon: Icons.location_city_rounded,
                    title: 'البلدية',
                    value: commune,
                  ),
                ],
              ],
            ),
          ),

          // ── The contractor's own material ──────────────────────────────
          //
          // A contractor opens this tab looking for "my work" and "my papers".
          // Leaving them only on the home tab meant hunting for the one place
          // that uploads; the account screen is where a user looks for their own
          // things, so the same three doors are here too.
          if (u.type == UserRole.worker) ...[
            const SizedBox(height: 14),
            const SectionTitle('ملفي المهني', icon: Icons.handyman_outlined),
            AppCard(
              key: const Key('account-portfolio'),
              padding: EdgeInsets.zero,
              onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const MyPortfolioScreen())),
              child: const _SettingsRow(
                icon: Icons.photo_library_outlined,
                title: 'معرض أعمالي',
                value: 'أضف صور أعمالك السابقة',
                tint: AppTheme.accentDeep,
                wash: AppTheme.accentWash,
                trailing: _Chevron(),
              ),
            ),
            const SizedBox(height: 10),
            AppCard(
              key: const Key('account-documents'),
              padding: EdgeInsets.zero,
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const VerificationScreen())),
              child: const _SettingsRow(
                icon: Icons.verified_user_outlined,
                title: 'المستندات والشهادات',
                value: 'بطاقة الحرفي، الهوية، وشهاداتك',
                tint: AppTheme.info,
                wash: AppTheme.infoWash,
                trailing: _Chevron(),
              ),
            ),
            const SizedBox(height: 10),
            AppCard(
              key: const Key('account-edit'),
              padding: EdgeInsets.zero,
              onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ProfileEditScreen())),
              child: const _SettingsRow(
                icon: Icons.tune_rounded,
                title: 'تعديل الملف المهني',
                value: 'التخصصات، النبذة، الأسعار، ومنطقة الخدمة',
                trailing: _Chevron(),
              ),
            ),
            const SizedBox(height: 10),
            // The founder asked for the subscription to be visible where a
            // contractor looks for his own things, not only on the home tab.
            // Not `const`: the row ages the subscription line against the
            // screen's clock (see [ProfileScreen.clock]).
            _PlanAccountRow(clock: clock),
          ],

          // ── Logout ─────────────────────────────────────────────────────
          const SizedBox(height: 14),
          AppCard(
            padding: EdgeInsets.zero,
            // The queue of unsent messages goes with the session inside
            // `auth.logout()`, which is the only place that knows every way a
            // session can end — including the 401 this screen never sees.
            onTap: scope.auth.logout,
            child: const _SettingsRow(
              icon: Icons.logout_rounded,
              title: 'تسجيل الخروج',
              tint: AppTheme.danger,
              wash: AppTheme.dangerWash,
              titleColor: AppTheme.danger,
            ),
          ),
        ],
      ),
    );
  }
}

/// The contractor's subscription, read live so the account screen never claims
/// a plan the server does not have.
class _PlanAccountRow extends StatefulWidget {
  const _PlanAccountRow({this.clock});

  /// The screen's clock, forwarded to [_planSummary] so this row never prints
  /// a plan state that was true when the read landed and false now.
  final DateTime Function()? clock;

  @override
  State<_PlanAccountRow> createState() => _PlanAccountRowState();
}

class _PlanAccountRowState extends State<_PlanAccountRow> {
  Future<BillingCatalogue>? _future;

  /// True while a *retry* is in flight, so the one control this row owns does
  /// not keep offering itself after it has been pressed.
  bool _retrying = false;

  /// Ages the subscription line once a minute. See [_armAgeTick].
  Timer? _ageTimer;

  /// The screen's clock. Defaults to the system clock in the app.
  DateTime _now() => (widget.clock ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    // Armed here, not only on a retry: the row's *first* read is issued in
    // `didChangeDependencies` and a contractor who never presses retry is
    // exactly the one whose line would sit frozen all session.
    _armAgeTick();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future ??= Repository(AppScope.of(context).api).subscription();
  }

  /// Keep the line honest while the tab sits mounted in the shell's
  /// `IndexedStack`.
  ///
  /// **This row is the one place in the app that most needed it.** The account
  /// tab is built once and then never rebuilt by tab switches — `IndexedStack`
  /// keeps every child alive — so before this timer the «اشتراكي» line held
  /// whatever `_planSummary` said when the read first landed. The read is
  /// issued exactly once, and a plan can end *during* a session: a contractor
  /// who opens the app before midnight and looks again after sees «نشط حتى
  /// 2026-10-01» from yesterday's answer, on the row whose only job is to get
  /// him to the renewal screen.
  ///
  /// Armed from the same place the future is set, not from `build` — a timer
  /// created in `build` is a new timer on every frame. It is armed whether or
  /// not a read has landed, because the arming is cheap and a read that lands
  /// later must not find the row un-aged.
  void _armAgeTick() {
    _ageTimer?.cancel();
    _ageTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (!mounted) return;
      setState(() {});
    });
  }

  @override
  void dispose() {
    _ageTimer?.cancel();
    _ageTimer = null;
    super.dispose();
  }

  /// Re-issue the read. The block body is load-bearing: an arrow-form
  /// `setState(() => _future = ...)` returns the assigned `Future`, and Flutter
  /// asserts on a `setState` callback that returns one.
  void _retry() {
    if (_retrying) return;
    // The read is issued from the `AppScope` in context, not from a field
    // cached in `didChangeDependencies`: this widget can outlive a rebuild that
    // swapped the scope, and the row must ask again rather than reuse a client
    // from a session that has ended.
    final api = AppScope.of(context).api;
    setState(() {
      _retrying = true;
      _future = Repository(api).subscription().whenComplete(() {
        if (mounted) setState(() => _retrying = false);
      });
    });
    _armAgeTick();
  }

  @override
  Widget build(BuildContext context) {
    return AppCard(
      key: const Key('account-subscription'),
      padding: EdgeInsets.zero,
      onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const SubscriptionScreen())),
      child: FutureBuilder<BillingCatalogue>(
        future: _future,
        builder: (context, snap) {
          // A failed read is not a free trial, and this row used to say it was.
          //
          // `_planSummary` keys on `s == null`, and `snap.data` is null on an
          // error exactly as it is on a read that has not answered — so a 500
          // fell into the same branch as a settled read and printed
          // «اختر خطتك — شهري أو سنوي». A contractor on a paid plan whose read
          // failed was told, in the app's own voice, that he had no plan, on the
          // one row whose entire job is to get him to the renewal screen.
          //
          // A pending read is a different state from a failed one and is left
          // to `_planSummary`, which already says «جارٍ التحقق من اشتراكك…».
          if (snap.hasError) {
            return _SettingsRow(
              icon: Icons.workspace_premium_outlined,
              title: 'اشتراكي',
              value: 'تعذّر جلب اشتراكك',
              valueColor: AppTheme.danger,
              tint: AppTheme.danger,
              wash: AppTheme.dangerWash,
              trailing: _PlanRetry(
                onTap: _retry,
                busy: _retrying,
              ),
            );
          }
          return _SettingsRow(
            icon: Icons.workspace_premium_outlined,
            title: 'اشتراكي',
            value: _planSummary(snap.data?.current, snap.connectionState,
                now: _now()),
            tint: AppTheme.accentDeep,
            wash: AppTheme.accentWash,
            trailing: const _Chevron(),
          );
        },
      ),
    );
  }
}

/// The row's way back from a failed read: a real control, not a label.
///
/// The row itself stays tappable — it is the door to the plan screen, and a
/// contractor who cannot see his plan can still go and look for it — so the
/// retry sits inside the row's trailing slot rather than replacing it.
class _PlanRetry extends StatelessWidget {
  final VoidCallback onTap;
  final bool busy;

  const _PlanRetry({required this.onTap, required this.busy});

  /// Kept as a field so the busy branch is a real callback and not a rebuilt
  /// closure on every frame.
  static void _swallow() {}

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      // What it does, for a screen reader: the icon alone is not a label.
      label: 'تعذّر جلب اشتراكك، اضغط لإعادة المحاولة',
      child: A11y.tap(
        label: 'إعادة المحاولة',
        enabled: !busy,
        child: InkWell(
          key: const Key('account-subscription-retry'),
          borderRadius: BorderRadius.circular(AppTheme.rPill),
          // A busy retry must still *win* the gesture arena, so this is a
          // no-op callback and never `null`. Passing null drops the recogniser
          // out of the arena entirely, and since this control sits inside the
          // row's own `AppCard.onTap`, the second tap on a slow connection was
          // caught by the card: the man who pressed "retry" was silently taken
          // to the plan screen instead, with the retry still running behind
          // him. Swallowing the tap is the behaviour; the hourglass says why.
          onTap: busy ? _swallow : onTap,
          child: Container(
            constraints: const BoxConstraints(
                minWidth: AppTheme.tapMin, minHeight: AppTheme.tapMin),
            padding: const EdgeInsets.symmetric(horizontal: AppTheme.s8),
            alignment: Alignment.center,
            child: Icon(
              busy ? Icons.hourglass_empty_rounded : Icons.refresh_rounded,
              size: 20,
              color: AppTheme.danger,
            ),
          ),
        ),
      ),
    );
  }
}

/// One line under «اشتراكي»: what the contractor is actually on right now.
String _planSummary(SubscriptionStatus? s, ConnectionState state,
    {required DateTime now}) {
  if (s == null) {
    return state == ConnectionState.waiting
        ? 'جارٍ التحقق من اشتراكك…'
        : 'اختر خطتك — شهري أو سنوي';
  }
  if (s.isFree) return 'الباقة المجانية — اطّلع على الخطط';
  // An expired plan must not be described as «نشط» on the row the contractor
  // taps to renew. The line below used to print the server's raw SQLite string
  // and call it active whatever the date said, so a lapsed subscription still
  // read "أساسي — نشط حتى 2020-01-01" on the screen whose only job is to send
  // him to the renewal screen.
  //
  // `isExpired`, not `isExpiredAt(now)`. This line used to ask the *model*
  // the question, which reaches `DateTime.now()` inside `models/plan.dart`, and
  // on the surface where it mattered least: the account tab is mounted once
  // inside the shell's `IndexedStack` and then rebuilt by nothing, so the
  // answer it printed was the one that was true when the read landed. A
  // contractor whose plan ended during the session was told his paid cover
  // still ran, and told it on the row that exists to send him to renew.
  //
  // `subscription_screen.dart` answered the same question against the clock
  // it was handed (`52b3640`); this row is the same fuse in the last reader
  // that had it left.
  final end = subscriptionEndDateLabel(s.expiresAtLocal);
  if (s.isExpiredAt(now)) {
    return end == null ? '${s.nameAr} — منتهية' : '${s.nameAr} — انتهت في $end';
  }
  return end == null ? s.nameAr : '${s.nameAr} — نشط حتى $end';
}

/// The account tab for a visitor who has not made an account: same app bar,
/// same shape, and the sign-in form only when he asks for it.
class _GuestAccountScreen extends StatelessWidget {
  final UserRole role;

  const _GuestAccountScreen({required this.role});

  @override
  Widget build(BuildContext context) {
    final worker = role == UserRole.worker;
    return Scaffold(
      appBar: AppBar(title: Text('حسابي', style: AppTheme.bar)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
            child: AppCard(
              padding: AppTheme.cardPad,
              child: Row(
                children: [
                  const IconBubble(
                    icon: Icons.person_outline_rounded,
                    tint: AppTheme.navy,
                    wash: AppTheme.lineSoft,
                    size: 64,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('زائر',
                            style: AppTheme.h1
                                .copyWith(color: AppTheme.textPrimary)),
                        const SizedBox(height: 8),
                        StatusPill(
                          label: worker ? 'حرفي — بدون حساب' : 'صاحب مشروع — بدون حساب',
                          color: AppTheme.accentDeep,
                          wash: AppTheme.accentWash,
                          icon: worker
                              ? Icons.handyman_rounded
                              : Icons.person_rounded,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: SignInWall(
              title: 'حسابك في الو مقاول',
              body: worker
                  ? 'سجّل الدخول لتُرسل عروضك على المشاريع المفتوحة وتُدير طلباتك وصور أعمالك.'
                  : 'سجّل الدخول لتتواصل مع المقاولين وتنشر مشروعك وتستقبل العروض.',
              role: role,
              note: 'كل التصفّح متاح بدون حساب.',
            ),
          ),
        ],
      ),
    );
  }
}

/// Avatar + name + role badge. The role is the one thing a user may not
/// remember choosing, so it stays visible on the account screen.
class _ProfileHeader extends StatelessWidget {
  final String name;
  final UserRole role;

  const _ProfileHeader({required this.name, required this.role});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: AppTheme.cardPad,
      child: Row(
        children: [
          InitialAvatar(name: name, size: 64),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.h1.copyWith(color: AppTheme.textPrimary),
                ),
                const SizedBox(height: 8),
                StatusPill(
                  label: _roleLabel(role),
                  color: AppTheme.accentDeep,
                  wash: AppTheme.accentWash,
                  icon: _roleIcon(role),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A settings row: leading [IconBubble] + label (+ optional value).
/// Colours are always explicit so a row can never vanish.
class _SettingsRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? value;

  /// Colour of the [value] line. Defaults to muted, like every other secondary
  /// line on this screen; a row whose read failed passes `AppTheme.danger` so
  /// the sentence that replaced a real answer is not dressed as ordinary text.
  final Color? valueColor;
  final Color tint;
  final Color wash;
  final Color titleColor;

  final Widget? trailing;

  const _SettingsRow({
    required this.icon,
    required this.title,
    this.value,
    this.valueColor,
    this.tint = AppTheme.navy,
    this.wash = AppTheme.lineSoft,
    this.titleColor = AppTheme.textPrimary,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Row(
        children: [
          IconBubble(icon: icon, tint: tint, wash: wash, size: 44),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTheme.label
                      .copyWith(fontSize: AppTheme.fsSmall, color: titleColor),
                ),
                if (value != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    value!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.caption
                        .copyWith(fontSize: AppTheme.fsCaption, color: AppTheme.textMuted),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// Right-pointing chevron for a row that opens another screen.
class _Chevron extends StatelessWidget {
  const _Chevron();

  @override
  Widget build(BuildContext context) {
    return const Icon(Icons.chevron_left_rounded,
        size: 20, color: AppTheme.textMuted);
  }
}

/// Hairline between rows, indented so it starts after the icon bubble.
class _RowDivider extends StatelessWidget {
  const _RowDivider();

  @override
  Widget build(BuildContext context) {
    return const Divider(height: 1, indent: 70, color: AppTheme.lineSoft);
  }
}

String _roleLabel(UserRole role) {
  switch (role) {
    case UserRole.worker:
      return 'مقاول حرفي';
    case UserRole.admin:
      return 'مسؤول';
    case UserRole.customer:
      return 'صاحب مشروع';
  }
}

IconData _roleIcon(UserRole role) {
  switch (role) {
    case UserRole.worker:
      return Icons.handyman_rounded;
    case UserRole.admin:
      return Icons.admin_panel_settings_rounded;
    case UserRole.customer:
      return Icons.person_rounded;
  }
}
