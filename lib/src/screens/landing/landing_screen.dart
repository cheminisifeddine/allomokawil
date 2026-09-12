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
// The hero is a warm white panel: cream wash, navy ink, the founder's mark on
// its own cream tile, and one gold accent on the primary action. The earlier
// painted blueprint scene (grid + house + crane) is gone — in a 104 dp band it
// read as stray gold lines rather than as a drawing.
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
              padding: AppTheme.cardPad,
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
          colors: [Color(0xFFFFFCF6), AppTheme.accentWash],
        ),
        borderRadius: BorderRadius.circular(AppTheme.rXl),
        border: Border.all(color: AppTheme.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    // The mark is black-and-gold, so on the white canvas it
                    // sits on a cream tile with a hairline. The old dark plate
                    // and the glow were there to hide it on a dark panel.
                    Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(AppTheme.rSm),
                        border: Border.all(color: AppTheme.line),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(AppTheme.rSm),
                        child: Image.asset(
                          'assets/brand/icon.png',
                          width: 44,
                          height: 44,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        S.appName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.h1
                            .copyWith(color: AppTheme.navy, fontSize: 26),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  'كل خدمات البناء والتهيئة',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.h2
                      .copyWith(color: AppTheme.navy, fontSize: 19),
                ),
                const SizedBox(height: 6),
                Text(
                  'من البحث عن مقاول موثوق إلى تسليم العمل.',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.body.copyWith(
                      color: AppTheme.textSecondary,
                      fontSize: 13.5,
                      height: 1.6),
                ),
              ],
            ),
          ),
          // The three promises sit on their own white strip, which closes the
          // panel and keeps the labels on one baseline.
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              color: AppTheme.surface,
              border: Border(top: BorderSide(color: AppTheme.line)),
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
        Icon(icon, size: 20, color: AppTheme.accentDeep),
        const SizedBox(height: 6),
        Text(
          label,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTheme.caption
              .copyWith(color: AppTheme.navy, fontSize: 11.5, height: 1.3),
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
            padding: AppTheme.cardPadRail,
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
            padding: AppTheme.cardPadRail,
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
            padding: AppTheme.cardPadRail,
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
        padding: AppTheme.cardPad,
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
            padding: AppTheme.cardPadRail,
            decoration: AppTheme.cardDecoration,
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
