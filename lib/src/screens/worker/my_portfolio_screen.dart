import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/app_scope.dart';
import '../../core/theme/app_theme.dart';
import '../../data/photo_count_copy.dart';
import '../../data/portfolio_allowance.dart';
import '../../data/portfolio_write_outcome.dart';
import '../../data/repository.dart';
import '../../data/stale_gallery_copy.dart';
import '../../models/worker.dart';
import '../../widgets/a11y.dart';
import '../../widgets/net_image.dart';
import '../../widgets/ui.dart';
import '../../widgets/skeletons.dart';
import '../../core/l10n/snack.dart';
import '../../core/l10n/error_copy.dart';
import '../../core/l10n/write_outcome.dart';
import '../../core/l10n/strings.dart';

/// "My work gallery" — the contractor's own past-work uploader.
///
/// Why it exists: the public profile already RENDERED a portfolio grid, but
/// nothing in the app could put a picture into it, so every contractor profile
/// showed an empty gallery and clients had no reason to trust one over another.
/// A contractor now opens this from their profile, adds photos of finished jobs
/// from the camera or the gallery, and sees them appear on the same grid the
/// clients see.
///
/// Each photo is uploaded to R2 and then registered against the profile, one at
/// a time: on a phone on a mobile network, uploading four photos in parallel is
/// how a weak uplink drops all four.
class MyPortfolioScreen extends StatefulWidget {
  /// The data layer, taken by the caller when one is supplied.
  ///
  /// Null in the app, where the screen builds its own from [AppScope] — the
  /// normal path and the one every user takes. The seam exists because the
  /// screen's write path can only be tested against a **multipart upload**,
  /// and `http.MultipartRequest` builds its own client instead of using the
  /// one handed to [ApiClient]: a `MockClient` never sees it, and under
  /// `TestWidgetsFlutterBinding` a real socket to loopback deadlocks in the
  /// fake-async zone. Injecting the repository is the same route
  /// `ReviewScreen` takes for the same class of reason, and it keeps the
  /// production call site a single `const MyPortfolioScreen()`.
  final Repository? repo;

  /// The wall clock the freshness band is measured against.
  ///
  /// `readAgeAr` renders «قبل 12 دقيقة» from the *difference* to now, so a
  /// screen that always reads `DateTime.now()` labels the same band differently
  /// as the hours pass. That is right for a person and fatal for a golden gate,
  /// which pins pixels: the notifications baseline drifted 171 px on an hour
  /// boundary and took the whole `flutter test` gate red with it. Tests hand in
  /// a fixed clock; production leaves this null and reads the real time.
  final DateTime Function()? clock;

  const MyPortfolioScreen({super.key, this.repo, this.clock});

  @override
  State<MyPortfolioScreen> createState() => _MyPortfolioScreenState();
}

class _MyPortfolioScreenState extends State<MyPortfolioScreen> {
  late final Repository _repo;
  bool _scopeReady = false;

  WorkerProfile? _worker;
  List<String> _images = const [];

  bool _loading = true;
  bool _busy = false;
  String? _error;

  /// When the photos on screen were last read successfully.
  ///
  /// Written where the read **settles**, not where it is issued, and refreshed
  /// on **every** success: a screen that stamps only its first successful read
  /// answers the second outage with the age of the first one, and tells a
  /// contractor his gallery was read «قبل ساعتين» when it was fetched this
  /// very second.
  DateTime? _readAt;

  /// The once-a-minute tick that re-labels the band. See [_armAgeTick].
  ///
  /// Null in production until the band exists, and null again the moment it is
  /// withdrawn — this screen holds **no** timer in the healthy state, which is
  /// the one structural difference from the nine siblings in this family and is
  /// the reason the field lives next to [_readAt] rather than with the other
  /// loading flags. Every one of those arms its tick the moment its first read
  /// settles and then guards inside it; here the thing being aged is born in a
  /// **failure**, so the tick is derived from [_stale] instead of from the
  /// lifecycle.
  Timer? _ageTimer;

  /// Whether the photos under the band are the ones the server last sent.
  ///
  /// **The field that was missing, and the whole reason this screen belonged
  /// to the family.** `_error` is set by two different failures and only one of
  /// them may keep the grid:
  ///
  ///  * a **first** read that failed has no photos at all, so there is nothing
  ///    to date and the full-screen error is the whole answer;
  ///  * a **re-read** that failed has a whole grid of finished jobs already on
  ///    screen, and those are real — the honest state is the photos with one
  ///    line saying they might be old.
  ///
  /// One nullable string cannot carry that difference, which is why this is a
  /// separate getter rather than another `if (_error != null)`.
  bool get _stale => _error != null && _images.isNotEmpty;

  /// Whether there is anything to draw at all.
  ///
  /// **The defect this whole item is about, stated as one predicate.** The
  /// builder used `_loading` for this, which asks "is a read in flight?" and
  /// answers a different question: "is there anything to draw?". The two came
  /// apart on the two ordinary failures of this screen:
  ///
  ///  * a **pending** re-read replaced twelve photographs of finished jobs with
  ///    a shimmer for the length of a round trip, after the contractor pressed
  ///    «تحديث» and did nothing wrong;
  ///  * a **failed** re-read replaced them with the same shimmer **forever**,
  ///    because `_loading` goes false and `_error` is set but the grid was
  ///    already thrown away.
  ///
  /// A first read is the only state with genuinely nothing to draw, and this
  /// screen is the family's one member where that is also the only state where
  /// losing the pictures is survivable — they are his own work, and the one
  /// surface in the product he is the author of.
  ///
  /// It is deliberately **not** `_worker != null`: that would send a *first*
  /// read that failed back to the skeleton, because nothing landed and
  /// `_loading` is false — the grid would be gone and the error with it, so a
  /// man whose connection dropped on the first open would be left with grey
  /// boxes and no way out. The screen the constructor builds is "a read is
  /// still in flight", and the three settled states — photos, a first-read
  /// failure, a re-read failure — all belong in the body.
  bool get _settled => _worker != null || !_loading;

  /// How many photos the plan allows, once the server has answered.
  ///
  /// Null until it does, and the gallery is **not** gated while it is null: an
  /// allowance read that has not arrived yet must not close the screen a
  /// contractor opened to see his work. The gate is a courtesy to the plan, not
  /// the guard on the door — BACKEND-API is the only thing that can actually
  /// refuse an upload, and until it does, failing open is the honest state.
  PortfolioAllowance? _allowance;

  /// How many photos are in flight, so the button can say so instead of sitting
  /// silent through a slow mobile upload.
  int _uploadedThisRun = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // AppScope is an InheritedWidget, so it cannot be read in initState.
    if (_scopeReady) return;
    _scopeReady = true;
    // See [MyPortfolioScreen.repo]. Production always takes the AppScope path.
    _repo = widget.repo ?? Repository(AppScope.of(context).api);
    _load();
  }

  /// The wall clock, injectable for tests. See [MyPortfolioScreen.clock].
  DateTime _now() => (widget.clock ?? DateTime.now)();

  /// Starts — or **stops** — the tick that keeps the band's age honest.
  ///
  /// Called from *both* ends of [_load] and derived from [_stale] rather than
  /// from the branch that reached it, because those are the only two places
  /// the band's existence can change, and a tick that outlived a withdrawn band
  /// would rebuild a healthy gallery once a minute for nothing. Cancel-first,
  /// then arm: one call site, and exactly one live timer whichever path [_load]
  /// took, so a «تحديث» that fails and then succeeds cannot leave two of them
  /// running.
  ///
  /// **The arm site is the load-bearing part of this tick.** [_armAgeTick] on
  /// the *success* path is copied from nine siblings and is wrong here: on
  /// success `_error` is null, so [_stale] is false and there is no band to
  /// age. The band is drawn by the **catch** — a re-read that failed with
  /// photos already on screen — which is the only way this screen reaches the
  /// state it exists to render. A tick armed the sibling way would be armed
  /// exactly when there is nothing to say and cancelled exactly when there is.
  void _armAgeTick() {
    _ageTimer?.cancel();
    _ageTimer = null;
    if (!mounted || !_stale) return;
    _ageTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (!mounted) return;
      // A `setState` with no fields changed is the whole mechanism: the band
      // composes `staleGalleryLineWithAgeAr(..., now: _now())` in `build`, so
      // re-running the build is what re-reads the clock. Not written in `build`
      // — a timer made in `build` is a new timer every frame, and the tick
      // multiplies.
      //
      // The re-check is belt to [_armAgeTick]'s braces: a pending re-read clears
      // `_error` only when it settles, so for the length of a round trip the
      // band is on screen and should keep ageing; a settled success has already
      // cancelled the timer, and this only keeps the two ends agreeing.
      if (!_stale) return;
      setState(() {});
    });
  }

  @override
  void dispose() {
    // Three callers push this route (worker home twice, profile once) and it is
    // a pushed route rather than an IndexedStack child, so an uncancelled timer
    // outlives the trip back and fires `setState` on a dead State — the same
    // "A Timer is still pending" failure every widget test in this repo inherits
    // from whoever adds the timer first.
    _ageTimer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final worker = await _repo.myProfile();
      final images = await _repo.portfolioImages(worker.id);
      if (!mounted) return;
      setState(() {
        _worker = worker;
        _images = images;
        _loading = false;
        // The clock *now*, not the moment the request was issued, so a read in
        // flight for forty seconds is dated when it actually landed.
        _readAt = _now();
      });
      // Re-armed, not armed: a «تحديث» that succeeds withdraws the band, so this
      // call is the *cancel* in the normal case, and the re-arm only after a
      // later read fails again.
      _armAgeTick();
      // Read **after** the gallery is on screen, so a plan that never loads is
      // a missing progress line and not a spinner that never resolves. The two
      // are separate requests and the gallery is the one the contractor came
      // for.
      await _loadAllowance(images.length);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = errorCopy(e);
      });
      // **The arm site that matters.** A failed re-read with photos on screen is
      // the one state this screen was written for, and it is born here. See
      // [_armAgeTick].
      _armAgeTick();
    }
  }

  /// Reads the plan's portfolio allowance, failing open.
  ///
  /// A contractor whose plan cannot be read keeps the whole screen he had
  /// before this existed: the gate appears when the server answers and never
  /// takes away a working gallery. A plan call that throws is not an error the
  /// contractor did anything about, so it is swallowed and the limit stays
  /// unknown.
  Future<void> _loadAllowance(int used) async {
    try {
      final status = (await _repo.subscription()).current;
      if (!mounted) return;
      setState(() {
        _allowance =
            PortfolioAllowance.fromLimit(status.portfolioLimit, used: used);
      });
    } catch (_) {
      // Unknown limit, on purpose. See [_allowance].
    }
  }

  /// Asks where the photo comes from, in the two words a user knows.
  Future<void> _addPhoto() async {
    if (_busy) return;
    // The add tile and the button below both hide on a full gallery, so this
    // is the third gate rather than the first: it is here because a limit the
    // user can only discover by hitting it is the defect the project cap had.
    final allowance = _allowance;
    if (allowance != null && allowance.isFull) return;
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppTheme.rXl)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('أضف صورة من أعمالك',
                  textAlign: TextAlign.center,
                  style: AppTheme.h2.copyWith(color: AppTheme.textPrimary)),
              const SizedBox(height: 4),
              Text('صورة واضحة للعمل بعد الانتهاء تجلب لك عروضاً أكثر.',
                  textAlign: TextAlign.center,
                  style: AppTheme.caption
                      .copyWith(color: AppTheme.textSecondary, height: 1.6)),
              const SizedBox(height: 16),
              PrimaryButton(
                label: 'الكاميرا',
                icon: Icons.photo_camera_rounded,
                onPressed: () => Navigator.pop(ctx, ImageSource.camera),
              ),
              const SizedBox(height: 10),
              SecondaryButton(
                label: 'من معرض الصور',
                icon: Icons.photo_library_rounded,
                onPressed: () => Navigator.pop(ctx, ImageSource.gallery),
              ),
            ],
          ),
        ),
      ),
    );
    if (source == null) return;
    await _pickAndUpload(source);
  }

  Future<void> _pickAndUpload(ImageSource source) async {
    // `imageQuality` keeps a 12-megapixel photo from becoming a 6 MB upload on a
    // 3G connection; the gallery only needs to look good, not be printable.
    final picked = await ImagePicker().pickImage(
      source: source,
      imageQuality: 78,
      maxWidth: 1600,
    );
    if (!mounted) return;
    if (picked == null) return;

    final worker = _worker;
    if (worker == null) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    // The URL, read out here and nowhere else. It is the only name the server
    // can be asked about, and it exists on the phone for exactly one window:
    // between the upload answering and the registration being posted. A write
    // that fails after that point is the case below, and if the URL were read
    // out of the `try` it would be exactly the sentence the old code could not
    // say.
    String? uploadedUrl;
    try {
      final url = await _repo.uploadDocument(File(picked.path));
      uploadedUrl = url;
      await _repo.addPortfolioImage(worker.id, imageUrl: url);
      if (!mounted) return;
      setState(() {
        _images = [..._images, url];
        _uploadedThisRun++;
        // The count that decides the gate is the server's, and the server has
        // just been told about one more photo. A local counter would agree with
        // the server until the first failed upload, and then never again.
        final a = _allowance;
        if (a != null) {
          _allowance = PortfolioAllowance(limit: a.limit, used: _images.length);
        }
      });
      showNote(context, 'تمت إضافة الصورة إلى معرض أعمالك');
    } catch (e) {
      if (!mounted) return;
      // Two different failures share one `catch`, and the old code called both
      // of them «تعذّر رفع الملف»:
      //
      //  * the **upload** failed — nothing is in R2, and the picture exists
      //    only in the phone's gallery, where the user still has it. Retrying
      //    is exactly right and costs one more attempt.
      //  * the **registration** failed — the picture *is* in R2 under a URL
      //    this phone is holding, and what never answered is the POST that
      //    names it on his profile. Retrying uploads the same room a second
      //    time under a *different* key, registers a second row, and spends a
      //    second slot of his plan's `portfolio_limit` on one photo.
      //
      // The transport layer already refuses to guess which of the two happened
      // and says so in `S.errWriteUnconfirmed`; this is the answer to that
      // sentence, and the honest one comes from the server rather than from us.
      if (isWriteUnconfirmed(e)) {
        if (uploadedUrl == null) {
          // The **upload** is what never answered, so there is no name to ask
          // the server about and nothing in the gallery could ever match one.
          // `S.errWriteUnconfirmed` ends with «تحقّق من القائمة قبل إعادة
          // المحاولة» and here that instruction is a dead end: no amount of
          // refreshing shows a picture the app has no URL for. What is true is
          // that nothing is on his profile yet and the picture is still in the
          // phone's gallery, so the honest sentence is the upload one and the
          // retry it offers costs one more attempt. The worst case is an
          // orphaned object in R2 nobody ever names — the cheap failure.
          setState(() => _error = S.errUpload);
        } else {
          await _settleUnconfirmed(uploadedUrl);
        }
        return;
      }
      setState(() => _error = errorCopy(e, fallback: S.errUpload));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Answers «did that photo reach my profile?» after the app refused to guess.
  ///
  /// The gallery on this screen *is* the list [S.errWriteUnconfirmed] tells the
  /// user to check, so it is re-read and the fresh one is put on screen — a
  /// stale grid would be asking him to confirm something the app is displaying
  /// but cannot see. The three answers are the app's shared ones, so this
  /// screen cannot drift into saying something the other six do not.
  ///
  /// The first toast is «نتحقّق الآن من القائمة…» and the second is the outcome,
  /// which is a second sentence about the same photo while the first is still on
  /// screen. That is deliberate and is what the other write screens do: the
  /// re-read is a network round trip the user would otherwise sit through
  /// looking at a screen that appears to be doing nothing, and a check that
  /// takes two seconds needs to be visible before it takes them.
  Future<void> _settleUnconfirmed(String uploadedUrl) async {
    showNote(context, recheckNote(notifications: false));
    final workerId = _worker!.id;
    final result = await resolvePortfolioWriteOutcome(
      uploadedUrl: uploadedUrl,
      fetch: () => _repo.portfolioImages(workerId),
    );
    if (!mounted) return;
    // Put the server's own gallery on screen before saying anything about it.
    // A landed photo is then visible without a refresh, a missing one is
    // visibly absent, and the counts the header draws come from the same list
    // the answer talks about.
    final fresh = result.gallery;
    if (fresh != null) {
      setState(() {
        _images = fresh;
        // **The stamp travels with the rows, in this `setState` and nowhere
        // else.** `_readAt` is written in exactly one other place — the success
        // path of `_load()` — and a re-read that lands is just as much a read of
        // the gallery as that one is. Leaving it stale here made the next band
        // lie: the contractor adds a photo, the registration stalls, the
        // re-read answers with the server's own four rows, and the following
        // failed «تحديث» raised a band dating **09:48** over a grid read at
        // **11:55**. «الصور المعروضة قبل ساعتين» is a specific claim about
        // *these* photographs, and it is false — the pictures it was measuring
        // have been gone for two hours.
        //
        // It is worse here than on the nine siblings, and this is why. On a
        // market or a directory, a stale age over fresh rows is mildly
        // confusing. On a gallery an age is a **commercial** claim: the band
        // exists so a contractor can tell whether the work he is looking at is
        // what he finished this morning or what he has not touched since the
        // spring. He reads the line as evidence about the photographs in front
        // of him and then spends an evening re-uploading pictures the server
        // has already told him about.
        //
        // `_now()` and not the moment the request was issued, for the reason
        // every other stamp on this screen does it that way: a re-read on a
        // cell network can take forty seconds, and dating it at issue time
        // under-reports the age by exactly the case where the number matters.
        _readAt = _now();
        // Counted here rather than after the setState, because the header that
        // prints it is built by this very call and a counter bumped after it
        // would not reach the screen until some other rebuild.
        if (result.outcome == WriteOutcome.landed) _uploadedThisRun++;
        // The plan's count is re-read from the server's own gallery for the
        // same reason, and NOT decremented when a photo is missing: the server
        // is the only thing that knows whether the earlier write spent a slot,
        // and a gate computed from a guess is how a paid contractor gets
        // locked out of a gallery that has room.
        final a = _allowance;
        if (a != null) {
          _allowance = PortfolioAllowance(limit: a.limit, used: fresh.length);
        }
      });
    }
    // `hideCurrentSnackBar` first, and this is load-bearing rather than
    // cosmetic. Two `showSnackBar` calls in a row **queue**: the second waits
    // for the first to time out, so the answer to «did my photo arrive?» would
    // sit behind «checking the list now…» for its full duration and the user
    // would have already looked away. The subscription screen already does it
    // this way for the same two-sentence pattern.
    showVerdict(context, writeOutcomeCopy(result.outcome));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('معرض أعمالي'),
        actions: [
          IconButton(
            // Still gated on the read, and that is right: a second «تحديث»
            // while one is in flight is a second GET on a connection that has
            // already failed once. The *grid* is no longer gated on it, which
            // is the half that was wrong.
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'تحديث',
          ),
        ],
      ),
      // `_settled`, not `_loading`. See [_settled]: the skeleton was
      // showing for a pending re-read and for a failed one, and on a gallery
      // that is the screen throwing away the contractor's own work. A shimmer
      // belongs to a *first* read, which is the only state with nothing to
      // draw.
      body: !_settled
          ? const SkeletonGrid()
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 620),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(18, 10, 18, 28),
                  children: [
                    // The band **replaces** the danger card when the grid is
                    // still on screen, and this is the half that is easy to
                    // get wrong. `_error != null` used to mean "nothing to
                    // draw", so the red card was the whole answer; now that a
                    // failed re-read keeps its photos, the red card would sit
                    // above twelve photographs saying «تعذّر…» as if the gallery
                    // itself were the problem — loud, alarming, and about the
                    // wrong thing. The band is the family's own colour for
                    // exactly this state: the data is real, the read is not.
                    //
                    // A **first** read that failed has no photos, so `_stale`
                    // is false and the red card with its retry is untouched.
                    if (_error != null && !_stale) ...[
                      AppCard(
                        color: AppTheme.dangerWash,
                        borderColor: AppTheme.danger,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.error_outline_rounded,
                                size: 20, color: AppTheme.danger),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(_error!,
                                  style: AppTheme.caption.copyWith(
                                      color: AppTheme.danger, height: 1.6)),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                    ],
                    if (_stale) ...[
                      _StaleGalleryBanner(
                        line: staleGalleryLineWithAgeAr(
                          _error!,
                          _readAt,
                          now: _now(),
                        ),
                      ),
                      const SizedBox(height: 14),
                    ],
                    if (_images.isNotEmpty)
                      _Header(
                        count: _images.length,
                        uploaded: _uploadedThisRun,
                        allowance: _allowance,
                      ),
                    if (_images.isNotEmpty) const SizedBox(height: 12),
                    _Gallery(
                      images: _images,
                      busy: _busy,
                      onAdd: _addPhoto,
                      // Null means the plan has not answered, and the tile stays:
                      // an allowance that has not loaded is not a full gallery.
                      showAdd: !(_allowance?.isFull ?? false),
                    ),
                    const SizedBox(height: 18),
                    // One sentence where the button was, so a full gallery says
                    // which limit it hit instead of showing nothing. A missing
                    // control on its own reads as a broken screen.
                    if (_allowance?.isFull ?? false)
                      _FullNotice(allowance: _allowance!)
                    else
                      PrimaryButton(
                        key: const Key('portfolio-add'),
                        label:
                            _busy ? 'جارٍ رفع الصورة...' : 'أضف صورة من أعمالك',
                        icon: _busy
                            ? Icons.cloud_upload_outlined
                            : Icons.add_a_photo_outlined,
                        loading: _busy,
                        onPressed: _busy ? null : _addPhoto,
                      ),
                    const SizedBox(height: 14),
                    // The photo-tips card was removed on the founder's call — the
                    // portfolio screen shows the gallery and the add button, and
                    // nothing else competes with them.
                  ],
                ),
              ),
            ),
    );
  }
}

/// Progress line: how many photos are on the profile right now.
class _Header extends StatelessWidget {
  final int count;
  final int uploaded;

  /// Null while the plan is still being read, in which case this card says
  /// what it has always said.
  final PortfolioAllowance? allowance;

  const _Header({
    required this.count,
    required this.uploaded,
    required this.allowance,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      color: AppTheme.successWash,
      borderColor: AppTheme.successWash,
      child: Row(
        children: [
          const IconBubble(
            icon: Icons.photo_library_rounded,
            tint: AppTheme.success,
            wash: AppTheme.surface,
            size: 42,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Both lines go through [CopyLine], and the 2 px gap moves
                // inside the second one. Measured on this app's own text
                // styles: `Text('')` in a `Column` still builds a line box
                // (20 px at `fsSmall`, 1.5), so a header whose count the copy
                // function could not answer drew a blank band between the
                // title row and the sentence under it. The `const
                // SizedBox(height: 2)` left as a sibling is the other half of
                // the same hole — 2 px of nothing that survives even after the
                // text collapses — so it belongs to the line it separated.
                CopyLine(
                  portfolioCountLineAr(count),
                  style: AppTheme.label.copyWith(
                      fontSize: AppTheme.fsSmall, color: AppTheme.success),
                ),
                CopyLine(
                  _subLine(),
                  gapAbove: 2,
                  style: AppTheme.caption.copyWith(
                      color: AppTheme.success,
                      fontSize: AppTheme.fsCaption,
                      height: 1.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The second line, in the order that answers the question he came with.
  ///
  /// What he has uploaded this sitting is the least useful thing to say once the
  /// plan matters, so the room left takes that slot, and the session count moves
  /// under it. A full gallery overrides both: the limit is the whole message.
  ///
  /// Null is silence by contract — a plan that never answered leaves this card
  /// saying exactly what it said before the allowance existed.
  String _subLine() {
    final a = allowance;
    if (a == null) {
      return uploaded > 0
          ? uploadedThisSessionAr(uploaded)
          : 'هذه الصور يراها كل صاحب مشروع في ملفك.';
    }
    if (a.isFull) return portfolioFullLineAr(a.limit);
    if (a.isUnlimited) return portfolioUnlimitedLineAr();
    return portfolioLeftLineAr(a.left!, a.limit);
  }
}

/// Stands in for the add button when the plan's gallery is full.
///
/// It offers the one action that lifts the limit, because a screen that only
/// says "no" leaves the contractor with nothing to do about it — the same
/// reasoning the 402 paywall on the bid button documents.
class _FullNotice extends StatelessWidget {
  const _FullNotice({required this.allowance});

  final PortfolioAllowance allowance;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      key: const Key('portfolio-full'),
      color: AppTheme.accentWash,
      child: Row(
        children: [
          const IconBubble(
            icon: Icons.lock_outline_rounded,
            tint: AppTheme.accentDeep,
            wash: AppTheme.surface,
            size: 42,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(portfolioFullLineAr(allowance.limit),
                    style: AppTheme.label.copyWith(
                        fontSize: AppTheme.fsSmall,
                        color: AppTheme.accentDeep)),
                const SizedBox(height: 2),
                Text('رقّي خطتك لتضيف صوراً أكثر إلى معرض أعمالك.',
                    style: AppTheme.caption.copyWith(
                        color: AppTheme.textSecondary,
                        fontSize: AppTheme.fsCaption,
                        height: 1.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The gallery grid, with its own "add" tile as the first cell — the natural
/// place to put a missing picture.
/// The band above a gallery that failed to re-read.
///
/// Deliberately the **accent** card and not the danger card, and that is the
/// whole argument of this class. Every other member of the family draws its
/// stale band in `accentWash` with the history icon: the rows underneath are
/// real, so the screen is not reporting a failure of the data, it is reporting
/// a failure of the *last update* to a real thing. Painting this one red would
/// say «the photos are broken» on a gallery whose photographs are fine.
///
/// The `Key`s are load-bearing, not decoration: every sibling pins its band by
/// key so a test can ask "is this band on screen?" without matching Arabic, and
/// a copy change in `stale_gallery_copy.dart` cannot quietly make the assertion
/// vacuous.
class _StaleGalleryBanner extends StatelessWidget {
  const _StaleGalleryBanner({required this.line});

  /// The composed sentence from [staleGalleryLineWithAgeAr].
  final String line;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      key: const Key('stale-gallery'),
      color: AppTheme.accentWash,
      borderColor: AppTheme.accent,
      padding: AppTheme.cardPadRail,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.history_toggle_off_rounded,
              size: AppTheme.s20, color: AppTheme.accentDeep),
          const SizedBox(width: AppTheme.s8),
          Expanded(
            child: Text(
              line,
              key: const Key('stale-gallery-line'),
              style: AppTheme.body.copyWith(
                color: AppTheme.accentDeep,
                height: 1.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Gallery extends StatelessWidget {
  final List<String> images;
  final bool busy;
  final VoidCallback onAdd;

  /// False when the plan's allowance is spent, so the grid does not keep
  /// offering a cell that goes nowhere.
  final bool showAdd;

  const _Gallery({
    required this.images,
    required this.busy,
    required this.onAdd,
    required this.showAdd,
  });

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      children: [
        if (showAdd) _AddTile(busy: busy, onTap: onAdd),
        for (var i = 0; i < images.length; i++)
          _PhotoTile(url: images[i], index: i),
      ],
    );
  }
}

class _AddTile extends StatelessWidget {
  final bool busy;
  final VoidCallback onTap;

  const _AddTile({required this.busy, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.accentWash,
      borderRadius: BorderRadius.circular(AppTheme.rMd),
      child: A11y.button(
          enabled: !busy,
          child: InkWell(
            onTap: busy ? null : onTap,
            borderRadius: BorderRadius.circular(AppTheme.rMd),
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppTheme.rMd),
                border: Border.all(color: AppTheme.accent, width: 1.4),
              ),
              child: Center(
                child: busy
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.4),
                      )
                    : const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add_rounded,
                              size: 28, color: AppTheme.accentDeep),
                          SizedBox(height: 2),
                          Text('أضف',
                              style: TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: AppTheme.fsCaption,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.accentDeep)),
                        ],
                      ),
              ),
            ),
          )),
    );
  }
}

class _PhotoTile extends StatelessWidget {
  final String url;
  final int index;

  const _PhotoTile({required this.url, required this.index});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppTheme.rMd),
      child: NetImage(
        url,
        semanticLabel: 'صورة من أعمالي ${index + 1}',
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const ColoredBox(
          color: AppTheme.lineSoft,
          child: Center(
            child:
                Icon(Icons.image_rounded, size: 26, color: AppTheme.textMuted),
          ),
        ),
        loadingBuilder: (context, child, progress) => progress == null
            ? child
            : const ColoredBox(color: AppTheme.lineSoft),
      ),
    );
  }
}
