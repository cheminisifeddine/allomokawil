import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/app_scope.dart';
import '../../core/theme/app_theme.dart';
import '../../data/repository.dart';
import '../../models/enums.dart';
import '../../models/worker.dart';
import '../../widgets/ui.dart';
import '../../widgets/skeletons.dart';
import '../../core/l10n/snack.dart';
import '../../core/l10n/error_copy.dart';
import '../../core/l10n/write_outcome.dart';
import '../../data/verification_write_outcome.dart';

/// Contractor verification: upload auto-entrepreneur/artisan card + ID +
/// selfie. This is the trust gate that powers "verified contractor" badges.
class VerificationScreen extends StatefulWidget {
  /// The data layer, taken by the caller when one is supplied.
  ///
  /// Null in the app, where the screen builds its own from [AppScope] — the
  /// normal path and the one every user takes. The seam exists for the same
  /// reason `MyPortfolioScreen.repo` does: this screen's write path can only be
  /// tested against a **multipart upload**, and `http.MultipartRequest` builds
  /// its own client instead of the one handed to [ApiClient]. A `MockClient`
  /// never sees it, and under `TestWidgetsFlutterBinding` a real socket to
  /// loopback deadlocks in the fake-async zone. Injecting the repository keeps
  /// the production call site a single `const VerificationScreen()`.
  final Repository? repo;

  const VerificationScreen({super.key, this.repo});

  @override
  State<VerificationScreen> createState() => _VerificationScreenState();
}

class _VerificationScreenState extends State<VerificationScreen> {
  late final Repository _repo;
  Future<WorkerProfile>? _profile;
  final List<(String, XFile?)> _docs = [
    ('auto_entrepreneur_card', null),
    ('selfie', null),
    ('national_id_front', null),
  ];

  /// Proof of skill — optional, and deliberately NOT part of the progress bar.
  /// A certificate is what separates two contractors who both have no reviews
  /// yet, but demanding one to appear in the marketplace would keep capable
  /// artisans out, so the slot is offered and never required.
  final List<XFile?> _certs = [null, null];

  bool _busy = false;

  bool _scopeReady = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // AppScope is an InheritedWidget, so it cannot be read in initState.
    if (_scopeReady) return;
    _scopeReady = true;
    // See [VerificationScreen.repo]. Production always takes the AppScope path.
    _repo = widget.repo ?? Repository(AppScope.of(context).api);
    _profile = _repo.myProfile();
  }

  /// Re-issues the profile request behind the error state.
  void _retry() {
    _refresh();
  }

  /// Re-reads the profile, replacing whatever the screen is drawing.
  ///
  /// Not `setState(() => _profile = _repo.myProfile())`, which is how both
  /// this screen and its error state were written: `myProfile()` returns a
  /// `Future`, and an arrow function returning that future hands the `Future`
  /// to `setState` as the result of the state change. In debug that trips
  /// "setState() callback argument returned a Future" and aborts the frame; in
  /// release the future is discarded and the state change still applies, so the
  /// one path that repairs a failed read is the one that throws on the way.
  ///
  /// The assignment is an expression statement inside a block body, so the
  /// closure returns void and the read is never dropped.
  void _refresh() {
    setState(() {
      _profile = _repo.myProfile();
    });
  }

  Future<void> _pickCert(int index) async {
    final picker = ImagePicker();
    final file = await picker.pickImage(source: ImageSource.gallery);
    // The gallery is another app, and it can be answered minutes later or
    // never. The guard goes **before** the null check rather than inside the
    // `if`, because a `setState` on a disposed `State` is the crash and the
    // null check is only the reason it usually does not happen.
    if (!mounted) return;
    if (file != null) {
      setState(() => _certs[index] = file);
    }
  }

  Future<void> _pickFor(int index) async {
    final picker = ImagePicker();
    final file = await picker.pickImage(source: ImageSource.gallery);
    if (!mounted) return;
    if (file != null) {
      setState(() {
        _docs[index] = (_docs[index].$1, file);
      });
    }
  }

  Future<void> _submit(WorkerProfile worker) async {
    if (_docs.any((d) => d.$2 == null)) {
      _$toast('أرفق كل المستندات المطلوبة');
      return;
    }
    setState(() => _busy = true);
    // The profile as the screen is drawing it **right now**, captured before
    // the upload starts.
    //
    // This is the whole fix. The re-read below used to ask «is the status
    // pending or verified?», and a brand-new contractor is stored as
    // `pending` — so the answer was yes for a man who had sent nothing, and
    // he was told his ID card had reached the reviewer. The question the
    // predicate may ask is what *changed*, which needs the row as it was
    // before the tap. See `data/verification_write_outcome.dart`.
    final before = worker;
    try {
      final documents = <Map<String, dynamic>>[];
      for (final d in _docs) {
        final url = await _repo.uploadDocument(File(d.$2!.path));
        documents.add({'document_type': d.$1, 'document_url': url});
      }
      // Uploaded one at a time on purpose: certificates can be several
      // megabytes each and a mobile uplink drops parallel uploads.
      for (final c in _certs) {
        if (c == null) continue;
        final url = await _repo.uploadDocument(File(c.path));
        documents.add({'document_type': 'certificate', 'document_url': url});
      }
      await _repo.submitVerification(worker.id, documents);
      if (!mounted) return;
      // Stay put and re-read the profile. The point is that he SEES the
      // dossier turn into "under review" — popping straight back home was how
      // a successful upload came to look like nothing had happened.
      //
      // **A 200 is not proof that the filing happened, and the sentence below
      // used to claim it was.** Found 4 Oct 2026 on production: the Worker
      // answers `{"ok":true}` for a document row it could not read a URL out
      // of, and the queue goes to *zero* across that call —
      //
      //   POST /api/mobile/workers/146/verification
      //     {"documents":[{"document_type":"selfie"}]}     -> 200 {"ok":true}
      //   GET  /api/mobile/my/profile -> verification_pending_docs: 0
      //
      // `ok` is a status with no field this app can check, so the old branch
      // took it at its word and printed "sent, awaiting review" to a man whose
      // three photos are in R2 and in no queue. He waits 48 hours; nobody ever
      // looks. Re-submitting does not help: the filing replaces the last one
      // identically, so the second attempt is also "accepted" and also empty.
      //
      // The verdict therefore runs on **every** filing, not only on the
      // ambiguous one — the same re-read, the same predicate, the same
      // sentences ([resolveVerificationWriteOutcome], [dossierOutcomeCopy]).
      // The unconfirmed path below stays exactly as it was: it has a failure to
      // explain, this one has only a 200 that proved nothing.
      _showRechecking();
      final outcome = await resolveVerificationWriteOutcome(
        before: before,
        fetch: _repo.myProfile,
      );
      if (mounted) _refresh();
      _showCommitResult(dossierOutcomeCopy(outcome));
      setState(() {
        _busy = false;
        _profile = _repo.myProfile();
      });
      return;
    } catch (e) {
      if (isWriteUnconfirmed(e)) {
        // The dossier is the row, and the profile on screen is the pre-tap copy
        // of it. Re-read and compare the two, so the verdict is about *what
        // moved* rather than about a value every contractor in the product
        // already carries.
        _showRechecking();
        final outcome = await resolveVerificationWriteOutcome(
          before: before,
          fetch: _repo.myProfile,
        );
        if (mounted) _refresh();
        // A dossier sentence, not `writeOutcomeCopy`: the shared line claims
        // «وجدناه في القائمة», which is meaningless here — the profile was on
        // screen the whole time. What changed is the document queue.
        _showCommitResult(dossierOutcomeCopy(outcome));
        return;
      }
      _$toast(errorCopy(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _$toast(String msg) => showNote(context, msg);

  /// «نتحقّق الآن من القائمة…» — the line that replaces the one sentence it is
  /// about to contradict.
  ///
  /// It is a recheck line, not an error line, because the failure has not been
  /// classified yet and the user is owed an answer rather than an apology.
  void _showRechecking() {
    _$toast(recheckNote(notifications: false));
  }

  /// The classified answer, drawn in place of the recheck line.
  ///
  /// `ScaffoldMessenger` **queues** by default: a second `showSnackBar` while
  /// one is visible waits for the first to time out, so the contractor would
  /// read «نتحقّق الآن من القائمة…» for its full four seconds *after* the check
  /// had already finished, and the verdict — the only answer to «did my ID card
  /// reach you?» — would arrive last and behind it.
  ///
  /// That question is the trust gate of the whole marketplace: a man who is told
  /// a check is running stops and waits, and a man told four seconds later that
  /// his papers arrived has already given up on the alternative. So the queue is
  /// removed first and only the answer is left on screen.
  ///
  /// Both sentences on this screen that can cover another now route through
  /// here. The one that **cannot** cover another is deliberately left alone: the
  /// «أرفق كل المستندات المطلوبة» line in [_submit], drawn before anything is
  /// in flight, has nothing above it to replace, and hiding there would blank a
  /// message nobody is covering.
  void _showCommitResult(String copy) => showVerdict(context, copy);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('توثيق الحساب')),
      body: FutureBuilder<WorkerProfile>(
        future: _profile,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const SkeletonFormPage(fields: 4);
          }
          if (snap.hasError) {
            return EmptyView(
              icon: Icons.error_outline_rounded,
              title: 'تعذّر جلب ملفك',
              message: errorCopy(snap.error),
              actionLabel: 'إعادة المحاولة',
              onAction: _retry,
              danger: true,
            );
          }
          final worker = snap.data!;
          final status = worker.verificationStatus;
          final verified = status == VerificationStatus.verified;
          // Deliberately NOT `status == pending`: a brand-new profile is stored
          // as pending too, so keying off the status alone would tell a man who
          // has sent nothing that he is under review. Documents actually
          // sitting in the queue are what make it true.
          final underReview = worker.dossierUnderReview;
          final rejected = status == VerificationStatus.rejected;
          final done = _docs.where((d) => d.$2 != null).length;
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: ListView(
                // The page column, by its own name. This was
                // `fromLTRB(18, 12, 18, 28)` — three of the four edges ARE
                // the house token (`gutter`, `s28`), and the top one silently
                // disagreed by 4 dp, so this screen's first card sat 4 dp lower
                // than every other page column in the app.
                padding: AppTheme.pagePad,
                children: [
                  if (verified)
                    const _VerifiedBanner()
                  else if (underReview)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _PartsStatusCard(worker: worker),
                        const SizedBox(height: 16),
                        _UnderReviewPanel(onRefresh: _retry),
                      ],
                    )
                  else ...[
                    // Read the real per-part state back BEFORE the form: he
                    // needs to know which half of the dossier is already
                    // accepted before he is asked to send anything again.
                    _PartsStatusCard(worker: worker),
                    const SizedBox(height: 16),
                    if (rejected) ...[
                      const _RejectedBanner(),
                      const SizedBox(height: 12),
                    ],
                    Text(
                      'لكي تظهر للموكلين وتحصل على شارة "موثّق"، أرفق المستندات التالية.',
                      style: AppTheme.body,
                    ),
                    const SizedBox(height: 12),
                    // Reassuring note: says why the documents are needed.
                    AppCard(
                      color: AppTheme.infoWash,
                      borderColor: AppTheme.infoWash,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.lock_outline_rounded,
                              size: 20, color: AppTheme.info),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'نطلب هذه المستندات للتحقق من هويتك فقط ولحماية كل الأطراف. '
                              'تبقى صورك خاصة ثم تُحذف بعد المراجعة، ولا تظهر لأي طرف آخر.',
                              style: AppTheme.bodySoft.copyWith(
                                  fontSize: AppTheme.fsMeta, color: AppTheme.info),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    _ProgressCard(done: done, total: _docs.length),
                    const SectionTitle('المستندات المطلوبة',
                        icon: Icons.folder_open_rounded),
                    _DocCard(
                      index: 0,
                      label: 'بطاقة المقاول (auto-entrepreneur)',
                      icon: Icons.badge_outlined,
                      tint: AppTheme.navy,
                      wash: AppTheme.lineSoft,
                      file: _docs[0].$2,
                      onPick: () => _pickFor(0),
                    ),
                    _DocCard(
                      index: 1,
                      label: 'صورة شخصية (سيلفي)',
                      icon: Icons.photo_camera_front_outlined,
                      tint: AppTheme.accentDeep,
                      wash: AppTheme.accentWash,
                      file: _docs[1].$2,
                      onPick: () => _pickFor(1),
                    ),
                    _DocCard(
                      index: 2,
                      label: 'بطاقة التعريف (وجه)',
                      icon: Icons.credit_card_outlined,
                      tint: AppTheme.info,
                      wash: AppTheme.infoWash,
                      file: _docs[2].$2,
                      onPick: () => _pickFor(2),
                    ),
                    const SizedBox(height: 6),
                    const SectionTitle('شهادات ودبلومات (اختياري)',
                        icon: Icons.workspace_premium_rounded),
                    Text(
                      'إن كانت بحوزتك شهادة تكوين أو دبلوم حرفة فأضفها هنا. '
                      'تظهر في ملفك وترفع ثقة أصحاب المشاريع بك، خاصة إن كنت جديداً بلا تقييمات.',
                      style: AppTheme.bodySoft
                          .copyWith(fontSize: AppTheme.fsMeta, height: AppTheme.lhRoomy),
                    ),
                    const SizedBox(height: 12),
                    for (var i = 0; i < _certs.length; i++)
                      _DocCard(
                        index: null,
                        label: i == 0 ? 'شهادة تكوين أو دبلوم' : 'شهادة إضافية',
                        icon: Icons.workspace_premium_rounded,
                        tint: AppTheme.accentDeep,
                        wash: AppTheme.accentWash,
                        file: _certs[i],
                        onPick: () => _pickCert(i),
                      ),
                    const SizedBox(height: 12),
                    PrimaryButton(
                      label: 'إرسال المستندات',
                      icon: Icons.upload_file_outlined,
                      loading: _busy,
                      onPressed: () => _submit(worker),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        const Icon(Icons.schedule_rounded,
                            size: 15, color: AppTheme.textMuted),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'تُراجع المستندات خلال 24-48 ساعة. تُحذف صور المستندات من الخادم بعد المراجعة.',
                            style: AppTheme.caption.copyWith(fontSize: AppTheme.fsBadge),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// What a contractor sees after a successful submission.
///
/// This is the receipt: what we received, that a second upload is not needed,
/// and when to expect an answer. Without it the app answered "did my documents
/// arrive?" with three empty slots.
class _UnderReviewPanel extends StatelessWidget {
  const _UnderReviewPanel({required this.onRefresh});

  final VoidCallback onRefresh;

  static const List<(IconData, String)> _received = [
    (Icons.badge_outlined, 'بطاقة المقاول (auto-entrepreneur)'),
    (Icons.photo_camera_front_outlined, 'صورة شخصية (سيلفي)'),
    (Icons.credit_card_outlined, 'بطاقة التعريف (وجه)'),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppCard(
          color: AppTheme.infoWash,
          borderColor: AppTheme.infoWash,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const IconBubble(
                icon: Icons.hourglass_top_rounded,
                tint: AppTheme.info,
                wash: AppTheme.surface,
                size: 44,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('مستنداتك قيد المراجعة',
                        style: AppTheme.label.copyWith(
                            fontSize: AppTheme.fsLead, color: AppTheme.info)),
                    const SizedBox(height: 8),
                    Text(
                      'استلمنا مستنداتك ولا تحتاج لإعادة إرسالها. '
                      'يراجعها فريقنا خلال 24-48 ساعة.',
                      style: AppTheme.bodySoft.copyWith(
                          fontSize: AppTheme.fsMeta,
                          height: AppTheme.lhRoomy,
                          color: AppTheme.info),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const SectionTitle('ما استلمناه', icon: Icons.inventory_2_outlined),
        AppCard(
          child: Column(
            children: [
              for (var i = 0; i < _received.length; i++) ...[
                Row(
                  children: [
                    const Icon(Icons.check_circle_rounded,
                        size: 20, color: AppTheme.success),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(_received[i].$2, style: AppTheme.body),
                    ),
                    Text('تم الاستلام',
                        style: AppTheme.caption.copyWith(
                            fontSize: AppTheme.fsBadge,
                            color: AppTheme.success)),
                  ],
                ),
                if (i != _received.length - 1)
                  const Divider(height: 20, color: AppTheme.lineSoft),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        SecondaryButton(
          label: 'تحديث الحالة',
          icon: Icons.refresh_rounded,
          onPressed: onRefresh,
        ),
        const SizedBox(height: 16),
        Text(
          'ستصلك إشعار عند القبول أو إن احتجنا تصحيحاً. '
          'لا يمكن الإرسال مرة أخرى وأنت قيد المراجعة.',
          style: AppTheme.caption.copyWith(fontSize: AppTheme.fsBadge),
        ),
      ],
    );
  }
}

/// Shown when a reviewer refused an earlier submission. The form below is the
/// resubmission path, so this banner only has to say what happened.
class _RejectedBanner extends StatelessWidget {
  const _RejectedBanner();

  @override
  Widget build(BuildContext context) {
    return AppCard(
      color: AppTheme.dangerWash,
      borderColor: AppTheme.dangerWash,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const IconBubble(
            icon: Icons.report_gmailerrorred_rounded,
            tint: AppTheme.danger,
            wash: AppTheme.surface,
            size: 44,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'لم تُقبل مستنداتك السابقة. تأكد أن الصور واضحة وأنها كلها لك، ثم أعد الإرسال.',
              style: AppTheme.body.copyWith(
                  fontSize: AppTheme.fsMeta, color: AppTheme.danger),
            ),
          ),
        ],
      ),
    );
  }
}

class _VerifiedBanner extends StatelessWidget {
  const _VerifiedBanner();

  @override
  Widget build(BuildContext context) {
    return AppCard(
      color: AppTheme.successWash,
      borderColor: AppTheme.successWash,
      child: Row(
        children: [
          const IconBubble(
            icon: Icons.verified_rounded,
            tint: AppTheme.success,
            wash: AppTheme.surface,
            size: 44,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text('حسابك موثّق. يمكنك استقبال المشاريع.',
                style: AppTheme.label
                    .copyWith(fontSize: AppTheme.fsSmall, color: AppTheme.success)),
          ),
        ],
      ),
    );
  }
}

/// Which half of the dossier the reviewer has already accepted.
///
/// The reviewer approves documents one row at a time, so a profile can sit in
/// `pending` with its identity already approved and its contractor card
/// refused. The all-or-nothing status flag cannot describe that, and the screen
/// used to fall back to a blank form — a man who had sent everything correctly
/// was asked for it all again with no explanation. These two rows read the two
/// flags the API already returns (`is_identity_verified`,
/// `is_certificate_verified`) so the screen says which part is done.
///
/// Deliberately no inference: an unverified part that has documents waiting
/// reads «بانتظار التحقق», and a part nothing was ever sent for reads
/// «لم تُرسل» — a brand-new contractor account used to read "awaiting
/// verification" for documents he had never uploaded, which is a claim about a
/// review that does not exist. `verification_pending_docs` is what separates
/// the two.
///
/// **And a fourth word when the count never arrived**: «غير معروف». The queue
/// size is nullable, because the server does not send it on every route (5 Oct,
/// live: absent from 0/96 browse rows, present on `/api/mobile/my/profile`),
/// and "the queue is empty" is as much a claim about the server as "the
/// queue is under review". Both directions of guessing were once drawn from
/// the same missing number.
class _PartsStatusCard extends StatelessWidget {
  const _PartsStatusCard({required this.worker});

  final WorkerProfile worker;

  /// True once anything at all has reached the reviewer.
  ///
  /// [WorkerProfile.hasFiledDocuments] rather than a raw `> 0`, because the
  /// count is nullable: an unmeasured queue is not an empty one.
  bool get _sent => worker.hasFiledDocuments;

  /// True when the server never sent a queue size for this row.
  ///
  /// This is the third state the card used to be missing. Measured 5 Oct, the
  /// key is absent from **0 of 96** browse rows and present on
  /// `/api/mobile/my/profile` — so on the routes that feed this card today it
  /// is false, and that is the honest reading to record rather than a lie to
  /// paper over. The state exists so that when a second route is ever wired to
  /// this card, the screen says "I was not told" instead of "nothing was
  /// sent" on the server's behalf.
  bool get _unknown => worker.dossierCountUnknown;

  @override
  Widget build(BuildContext context) {
    final underReview = worker.dossierUnderReview;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            children: [
              Icon(Icons.fact_check_outlined, size: 20, color: AppTheme.navy),
              SizedBox(width: 8),
              Expanded(child: Text('حالة ملفك', style: AppTheme.label)),
            ],
          ),
          const SizedBox(height: 6),
          _part(
            icon: Icons.badge_outlined,
            label: 'الهوية (بطاقة التعريف + سيلفي)',
            ok: worker.identityVerified,
          ),
          const Divider(height: 18, color: AppTheme.lineSoft),
          _part(
            icon: Icons.workspace_premium_rounded,
            label: 'بطاقة المقاول والشهادات',
            ok: worker.certificateVerified,
          ),
          const SizedBox(height: 10),
          Text(
            _unknown
                ? 'لم نتمكن من قراءة حالة وثائقك من الخادم. ارفع وثائقك من الأسفل، وسيتغيّر هذا الجدول عند تحديثه.'
                : !_sent
                ? 'لم تُرسل أي وثيقة بعد. ارفع وثائقك من الأسفل، وسيتغيّر هذا الجدول بعد الإرسال وقبل المراجعة.'
                : (underReview
                    ? 'وصلت وثائقك وهي قيد المراجعة. تُقبل المستندات واحداً واحداً، وسيتغيّر هذا الجدول مع كل قبول.'
                    : 'تُقبل المستندات واحداً واحداً. أي جزء لم يُقبل بعد يمكنك إعادة رفعه من الأسفل.'),
            style: AppTheme.caption.copyWith(
                fontSize: AppTheme.fsBadge, height: AppTheme.lhRoomy),
          ),
        ],
      ),
    );
  }

  Widget _part({
    required IconData icon,
    required String label,
    required bool ok,
  }) {
    // Four honest states, not two. An accepted part is true on any route; an
    // unaccepted part needs the queue count to say *why* it is unaccepted, and
    // a route that does not send that count cannot supply the reason.
    final (String text, IconData mark, Color colour) = ok
        ? ('موثّقة', Icons.check_circle_rounded, AppTheme.success)
        : _unknown
            ? ('غير معروف', Icons.help_outline_rounded, AppTheme.textMuted)
            : _sent
                ? ('بانتظار التحقق', Icons.hourglass_empty_rounded,
                    AppTheme.textMuted)
                : ('لم تُرسل', Icons.upload_file_rounded, AppTheme.textMuted);
    return Row(
      children: [
        Icon(icon, size: 20, color: ok ? AppTheme.success : AppTheme.textMuted),
        const SizedBox(width: 10),
        Expanded(child: Text(label, style: AppTheme.body)),
        const SizedBox(width: 8),
        // A real [StatusPill], not a hand-rolled copy of one. This row and the
        // `_DocCard` pills below it are direct children of the same `ListView`
        // (`:271`), so a worker scrolls between them and watches the pill
        // change: this used to be `symmetric(horizontal: 10, vertical: 5)`
        // with a 13 dp icon and a 5 dp gap, sitting beside a `StatusPill` at
        // `pillPad` (10x6) with a 14 dp icon and a 6 dp gap — same radius, same
        // caption size, 1 dp of slop between neighbours. R4 could not see it
        // (it counts literals per file and there was nothing off-grid left to
        // count) and `pill_inset_test.dart` could not see it (it compares the
        // three pills that already were one component). The word, the colour
        // and the icon are one decision, so this row now makes it once.
        //
        // `fsBadge` (11) was the one thing the copy got that `StatusPill`
        // does not do: it is a *count/overline* size, while the three pills
        // this one now sits beside are all `fsCaption` (12.5). Two verdicts in
        // one scroll view reading at 11 and 12.5 is the same "unfinished"
        // signal as the 1 dp, so the caption is the shared one.
        //
        // The **border** is the only thing this row had that `StatusPill` did
        // not, and it earns its place: `surfaceAlt` on a white card is 1.06:1,
        // so without the outline «لم تُرسل» is a grey ghost with no edge. It is
        // a parameter on the shared pill, not a second pill.
        StatusPill(
          label: text,
          icon: mark,
          color: colour,
          wash: ok ? AppTheme.successWash : AppTheme.surfaceAlt,
          border: ok ? AppTheme.success : AppTheme.controlLine,
        ),
      ],
    );
  }
}

/// "You completed n of 3 documents" progress readout.
class _ProgressCard extends StatelessWidget {
  final int done;
  final int total;

  const _ProgressCard({required this.done, required this.total});

  @override
  Widget build(BuildContext context) {
    final complete = total > 0 && done == total;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                complete
                    ? Icons.check_circle_rounded
                    : Icons.upload_file_rounded,
                size: 20,
                color: complete ? AppTheme.success : AppTheme.navy,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  complete
                      ? 'كل المستندات جاهزة للإرسال'
                      : 'أكملت $done من $total مستندات',
                  style: AppTheme.label,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppTheme.rPill),
            child: LinearProgressIndicator(
              value: total == 0 ? 0 : done / total,
              minHeight: 8,
              backgroundColor: AppTheme.line,
              color: complete ? AppTheme.success : AppTheme.accent,
            ),
          ),
        ],
      ),
    );
  }
}

/// One document slot: whole card is tappable, thumbnail + status once chosen.
class _DocCard extends StatelessWidget {
  /// 1-based position among the REQUIRED documents, or null for the optional
  /// certificate slots. An optional slot must not carry the next number: the
  /// progress card counts three documents, so a "4" reads as a fourth duty.
  final int? index;
  final String label;
  final IconData icon;
  final Color tint;
  final Color wash;
  final XFile? file;
  final VoidCallback onPick;

  const _DocCard({
    this.index,
    required this.label,
    required this.icon,
    required this.tint,
    required this.wash,
    required this.file,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    final chosen = file != null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppCard(
        onTap: onPick,
        padding: AppTheme.cardPad,
        borderColor: chosen ? AppTheme.success : AppTheme.line,
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(AppTheme.rSm),
              child: SizedBox(
                width: 58,
                height: 58,
                child: chosen
                    ? Image.file(
                        File(file!.path),
                        semanticLabel: 'الصورة المختارة',
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Center(
                          child: IconBubble(
                              icon: icon, tint: tint, wash: wash, size: 58),
                        ),
                      )
                    : IconBubble(icon: icon, tint: tint, wash: wash, size: 58),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 20,
                        height: 20,
                        alignment: Alignment.center,
                        decoration: const BoxDecoration(
                          color: AppTheme.navy,
                          shape: BoxShape.circle,
                        ),
                        child: index == null
                            ? const Icon(Icons.add_rounded,
                                size: 14, color: Colors.white)
                            : Text('${index! + 1}',
                                style: AppTheme.caption.copyWith(
                                    fontSize: AppTheme.fsCaption, color: AppTheme.onNavy)),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          label,
                          style: AppTheme.label,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (chosen)
                    const StatusPill(
                      label: 'تم الاختيار',
                      color: AppTheme.success,
                      wash: AppTheme.successWash,
                      icon: Icons.check_circle_rounded,
                    )
                  else
                    StatusPill(
                      label: index == null ? 'أضف شهادة' : 'اضغط للإضافة',
                      color: AppTheme.info,
                      wash: AppTheme.infoWash,
                      icon: Icons.add_a_photo_outlined,
                    ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            Icon(
              chosen ? Icons.sync_rounded : Icons.touch_app_rounded,
              size: 22,
              color: chosen ? AppTheme.navy : AppTheme.textMuted,
            ),
          ],
        ),
      ),
    );
  }
}
