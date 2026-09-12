// The first screen of a fresh install.
//
// It used to be a role gate: two big cards ("I'm a project owner" / "I'm a
// contractor") that the user had to answer before seeing anything else, and only
// then a sheet asking sign-in or sign-up. That is two questions before the user
// can type a single character — and a returning user, who already knows what they
// are, still had to answer both.
//
// This screen answers the questions a first-time user actually has, in order:
// what is this, is it for me, how does it work, is it safe — and offers exactly
// two actions, "create an account" and "sign in", which open the one auth screen
// where the role is chosen. Nothing else is asked on the way in.
//
// The hero art is drawn, not shipped: `_BlueprintArt` is original vector line art
// (a blueprint grid, a house under a crane) painted with `CustomPainter`, so the
// build carries no third-party image, icon pack or stock photo.
import 'package:flutter/material.dart';

import '../../core/l10n/strings.dart';
import '../../core/theme/app_theme.dart';
import '../../data/taxonomy.dart';
import '../../models/enums.dart';
import '../../widgets/ui.dart';
import '../auth/auth_screen.dart';

class LandingScreen extends StatelessWidget {
  const LandingScreen({super.key});

  void _openAuth(BuildContext context, AuthMode mode,
      {UserRole role = UserRole.customer}) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => AuthScreen(mode: mode, role: role)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _Hero(),
            const SizedBox(height: 18),
            const _TrustRow(),
            const SizedBox(height: 22),
            const SectionTitle('كيف يعمل التطبيق؟'),
            const SizedBox(height: 10),
            const _Step(
              number: '1',
              icon: Icons.post_add_rounded,
              title: 'انشر مشروعك',
              body: 'اوصف ما تريد إنجازه، أضف الصور والميزانية والولاية.',
            ),
            const _Step(
              number: '2',
              icon: Icons.compare_arrows_rounded,
              title: 'قارن العروض',
              body: 'يصلك عرض من كل مقاول بالسعر والمدة، وتختار الأنسب.',
            ),
            const _Step(
              number: '3',
              icon: Icons.handshake_outlined,
              title: 'أنجز وقيّم',
              body: 'تتواصل عبر المحادثة، وبعد التسليم تترك تقييمك بالنجوم.',
              last: true,
            ),
            const SizedBox(height: 20),
            const SectionTitle('أشهر الخدمات'),
            const SizedBox(height: 12),
            const _CategoryStrip(),
            const SizedBox(height: 22),
            AppCard(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'ابدأ الآن — مجاناً',
                    textAlign: TextAlign.center,
                    style: AppTheme.h2.copyWith(color: AppTheme.textPrimary),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'نشر المشروع واستقبال العروض بدون أي رسوم.',
                    textAlign: TextAlign.center,
                    style: AppTheme.caption
                        .copyWith(color: AppTheme.textSecondary, height: 1.6),
                  ),
                  const SizedBox(height: 16),
                  PrimaryButton(
                    key: const Key('landing-create-account'),
                    label: S.createAccount,
                    icon: Icons.person_add_alt_1_rounded,
                    onPressed: () => _openAuth(context, AuthMode.signUp),
                  ),
                  const SizedBox(height: 10),
                  SecondaryButton(
                    key: const Key('landing-sign-in'),
                    label: S.loginTitle,
                    icon: Icons.login_rounded,
                    onPressed: () => _openAuth(context, AuthMode.signIn),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        'أنت مقاول أو حرفي؟',
                        style: AppTheme.caption
                            .copyWith(color: AppTheme.textSecondary),
                      ),
                      TextButton(
                        key: const Key('landing-contractor-link'),
                        onPressed: () => _openAuth(context, AuthMode.signUp,
                            role: UserRole.worker),
                        child: Text(
                          'أنشئ حساب مقاول',
                          style: AppTheme.label
                              .copyWith(fontSize: 14.5, color: AppTheme.info),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const _TermsLine(),
          ],
        ),
      ),
    );
  }
}

/// Navy panel: brand, what the app is, and the drawn blueprint scene.
class _Hero extends StatelessWidget {
  const _Hero();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [AppTheme.navy, AppTheme.navyDeep],
        ),
        borderRadius: BorderRadius.circular(AppTheme.rXl),
        boxShadow: AppTheme.softShadow,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: const BoxDecoration(
                        color: AppTheme.accent,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.architecture_rounded,
                          size: 22, color: AppTheme.navy),
                    ),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        S.appName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.h1
                            .copyWith(color: AppTheme.onNavy, fontSize: 26),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  'كل خدمات البناء والتهيئة',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.h2
                      .copyWith(color: AppTheme.onNavy, fontSize: 19),
                ),
                const SizedBox(height: 4),
                Text(
                  'من البحث عن مقاول موثوق إلى تسليم العمل.',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.body
                      .copyWith(color: AppTheme.onNavyMuted, fontSize: 13.5),
                ),
              ],
            ),
          ),
          // The drawing gets its own band under the words. Behind them, the roof
          // line crossed the tagline and the clipped crane read as a mistake.
          const SizedBox(
            height: 104,
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, 4, 16, 6),
              child: CustomPaint(painter: _BlueprintArt(), size: Size.infinite),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.07),
              border: Border(
                top: BorderSide(color: Colors.white.withValues(alpha: 0.10)),
              ),
            ),
            child: Row(
              children: const [
                Expanded(
                  child: _HeroStat(
                      icon: Icons.verified_user_outlined,
                      label: 'مقاولون موثّقون'),
                ),
                Expanded(
                  child: _HeroStat(
                      icon: Icons.star_rounded, label: 'تقييمات حقيقية'),
                ),
                Expanded(
                  child: _HeroStat(icon: Icons.map_outlined, label: '58 ولاية'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroStat extends StatelessWidget {
  final IconData icon;
  final String label;

  const _HeroStat({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, size: 20, color: AppTheme.accent),
        const SizedBox(height: 6),
        Text(
          label,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTheme.caption
              .copyWith(color: AppTheme.onNavy, fontSize: 11.5, height: 1.3),
        ),
      ],
    );
  }
}

/// Three plain promises, in the words a first-time user would use.
class _TrustRow extends StatelessWidget {
  const _TrustRow();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: AppCard(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
            child: Column(
              children: [
                const IconBubble(
                    icon: Icons.photo_library_outlined,
                    tint: AppTheme.info,
                    wash: AppTheme.infoWash,
                    size: 38),
                const SizedBox(height: 8),
                Text('معرض أعمال',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.caption
                        .copyWith(color: AppTheme.textPrimary, fontSize: 12.5)),
                const SizedBox(height: 2),
                Text('شاهد أعمال كل مقاول',
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.caption.copyWith(
                        color: AppTheme.textMuted,
                        fontSize: 10.5,
                        height: 1.4)),
              ],
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: AppCard(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
            child: Column(
              children: [
                const IconBubble(
                    icon: Icons.forum_outlined,
                    tint: AppTheme.accentDeep,
                    wash: AppTheme.accentWash,
                    size: 38),
                const SizedBox(height: 8),
                Text('محادثة مباشرة',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.caption
                        .copyWith(color: AppTheme.textPrimary, fontSize: 12.5)),
                const SizedBox(height: 2),
                Text('تفاوض داخل التطبيق',
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.caption.copyWith(
                        color: AppTheme.textMuted,
                        fontSize: 10.5,
                        height: 1.4)),
              ],
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: AppCard(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
            child: Column(
              children: [
                const IconBubble(
                    icon: Icons.payments_outlined,
                    tint: AppTheme.success,
                    wash: AppTheme.successWash,
                    size: 38),
                const SizedBox(height: 8),
                Text('بدون رسوم',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.caption
                        .copyWith(color: AppTheme.textPrimary, fontSize: 12.5)),
                const SizedBox(height: 2),
                Text('العروض مجانية',
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.caption.copyWith(
                        color: AppTheme.textMuted,
                        fontSize: 10.5,
                        height: 1.4)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// One numbered step of the three-step explanation.
class _Step extends StatelessWidget {
  final String number;
  final IconData icon;
  final String title;
  final String body;
  final bool last;

  const _Step({
    required this.number,
    required this.icon,
    required this.title,
    required this.body,
    this.last = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: last ? 0 : 12),
      child: AppCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                IconBubble(
                    icon: icon,
                    tint: AppTheme.navy,
                    wash: AppTheme.accentWash,
                    size: 46),
                Positioned(
                  bottom: -2,
                  left: -2,
                  child: Container(
                    width: 20,
                    height: 20,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                      color: AppTheme.accent,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      number,
                      style: AppTheme.label
                          .copyWith(fontSize: 12, color: AppTheme.navy),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.h2
                          .copyWith(color: AppTheme.textPrimary, fontSize: 16)),
                  const SizedBox(height: 3),
                  Text(
                    body,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.caption
                        .copyWith(color: AppTheme.textSecondary, height: 1.55),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Horizontally scrolling row of the trades, so the marketplace is visible
/// before an account exists.
class _CategoryStrip extends StatelessWidget {
  const _CategoryStrip();

  @override
  Widget build(BuildContext context) {
    final items = Taxonomy.categories.take(10).toList();
    // 104 = a 38 px bubble + 8 px gap + two 15 px label lines + 24 px padding
    // and the 2 px border. At 92 the second line was clipped on a 412 px phone.
    return SizedBox(
      height: 104,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 2),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, i) {
          final c = items[i];
          return Container(
            width: 92,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(AppTheme.rLg),
              border: Border.all(color: AppTheme.line),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                IconBubble(icon: c.icon, tint: c.tint, wash: c.wash, size: 38),
                const SizedBox(height: 8),
                Flexible(
                  child: Text(
                    c.name,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.caption.copyWith(
                        color: AppTheme.textPrimary,
                        fontSize: 11,
                        height: 1.35),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Quiet consent line at the bottom of the first screen.
class _TermsLine extends StatelessWidget {
  const _TermsLine();

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 6,
      runSpacing: 2,
      children: [
        const Icon(Icons.verified_user_outlined,
            size: 15, color: AppTheme.textMuted),
        Text(
          'بالمتابعة أنت توافق على شروط الاستخدام وسياسة الخصوصية',
          textAlign: TextAlign.center,
          style: AppTheme.caption.copyWith(color: AppTheme.textMuted),
        ),
      ],
    );
  }
}

/// Original blueprint-style line art for the hero: a millimetre grid, a house
/// with a pitched roof and its openings, and a tower crane — the three shapes
/// that say "construction" without a single borrowed pixel.
class _BlueprintArt extends CustomPainter {
  const _BlueprintArt();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Warm glow behind the house so the navy does not read as flat.
    final glowRect = Rect.fromCircle(
      center: Offset(w * 0.26, h * 0.72),
      radius: w * 0.36,
    );
    canvas.drawCircle(
      glowRect.center,
      glowRect.width / 2,
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0x2EE8A33D), Color(0x00E8A33D)],
        ).createShader(glowRect),
    );

    // Blueprint grid: the paper the drawing sits on.
    final grid = Paint()
      ..color = Colors.white.withValues(alpha: 0.05)
      ..strokeWidth = 1;
    for (double x = 0; x <= w; x += 18) {
      canvas.drawLine(Offset(x, 0), Offset(x, h), grid);
    }
    for (double y = 0; y <= h; y += 18) {
      canvas.drawLine(Offset(0, y), Offset(w, y), grid);
    }

    final ink = Paint()
      ..color = AppTheme.accent.withValues(alpha: 0.95)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.1
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final faint = Paint()
      ..color = Colors.white.withValues(alpha: 0.30)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // The ground the whole drawing stands on.
    final groundY = h * 0.90;
    canvas.drawLine(
        Offset(w * 0.02, groundY), Offset(w * 0.98, groundY), faint);

    // House: walls, then a roof whose eaves meet the wall tops exactly.
    final wallTop = h * 0.52;
    final left = w * 0.10;
    final right = w * 0.46;
    canvas.drawRect(Rect.fromLTRB(left, wallTop, right, groundY), ink);
    canvas.drawPath(
      Path()
        ..moveTo(w * 0.05, wallTop)
        ..lineTo((left + right) / 2, h * 0.16)
        ..lineTo(w * 0.51, wallTop),
      ink,
    );
    // Door and two windows, openings only.
    canvas.drawRect(
        Rect.fromLTRB(w * 0.24, h * 0.70, w * 0.32, groundY), faint);
    canvas.drawRect(
        Rect.fromLTRB(w * 0.14, h * 0.60, w * 0.20, h * 0.70), faint);
    canvas.drawRect(
        Rect.fromLTRB(w * 0.36, h * 0.60, w * 0.42, h * 0.70), faint);

    // Tower crane: mast, jib, counterweight, hoist cable and the load.
    final mastX = w * 0.80;
    canvas.drawLine(Offset(mastX, groundY), Offset(mastX, h * 0.16), ink);
    canvas.drawLine(
        Offset(w * 0.66, h * 0.16), Offset(w * 0.94, h * 0.16), ink);
    canvas.drawLine(Offset(mastX, h * 0.16), Offset(mastX, h * 0.06), ink);
    canvas.drawRect(
        Rect.fromLTRB(w * 0.87, h * 0.17, w * 0.94, h * 0.27), faint);
    // Hoist cable and the block hanging from the jib.
    canvas.drawLine(
        Offset(w * 0.70, h * 0.16), Offset(w * 0.70, h * 0.48), faint);
    canvas.drawRect(
        Rect.fromLTRB(w * 0.665, h * 0.48, w * 0.735, h * 0.60), ink);
    // Mast bracing: three closed rungs, never touching the ground line.
    for (double y = h * 0.30; y < h * 0.84; y += h * 0.18) {
      final next = y + h * 0.18;
      canvas.drawLine(Offset(mastX - 5, y), Offset(mastX + 5, next), faint);
      canvas.drawLine(Offset(mastX + 5, y), Offset(mastX - 5, next), faint);
    }
  }

  @override
  bool shouldRepaint(covariant _BlueprintArt oldDelegate) => false;
}
