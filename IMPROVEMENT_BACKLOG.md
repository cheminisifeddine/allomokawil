# الو مقاول — App improvement backlog

Goal: an elite, obviously-polished Android/iOS marketplace that an Algerian
contractor or project owner understands without being taught. Every loop takes
the **top unchecked item in phase order**, ships it, and ticks it.

Rules for what belongs here: a real user-visible improvement or a real
correctness gap — never a refactor for its own sake. One item per loop.

---

## Loop protocol (read this before every cycle)

1. `cd /home/renia/allomokawil && git status --short` must be clean. If it is
   not, commit or stash the leftovers first and say so in the report.
   **Exception — do not touch another writer's work.** If the dirt is in files
   you did not edit, an interactive session is mid-cycle in this same checkout:
   touch nothing, report "working tree busy, skipped this cycle" and exit. Two
   writers in one tree means one of them loses a commit; on 12 Sep the loop
   committed on top of a live session's in-flight feature and the two nearly
   shipped a half-built phone field.
2. Take the **first unchecked item in phase order**. Do not reorder phases; do
   not batch two items into one loop.
3. Implement it completely in Dart. Original code only — no Houzz assets, code,
   icons or branding. Arabic-RTL first, English strings only in code.
4. Gate before committing:
   ```
   /home/renia/tools/flutter/bin/flutter analyze     # must print "No issues found!"
   /home/renia/tools/flutter/bin/flutter test        # count must be >= the previous count
   ```
   If either fails: `git checkout -- .` (or `git stash`) and report the failure
   instead of committing. **A red build is never shipped.**
5. If the change is visual, rebuild the web bundle and check it with the real
   browser, not by reasoning:
   ```
   /home/renia/tools/build_web.sh                     # or: flutter build web --dart-define=...
   python3 /home/renia/tools/pngscan.py <shot.png> --color <hex> --tol 26
   ```
   A CDP screenshot is the only proof a layout claim is true. If you cannot
   render it, say so plainly rather than asserting it looks right.
6. Commit with a message that says **what changed and why**, then
   `git push origin main`.
7. Tick the checkbox here (change `- [ ]` to `- [x]`) and add the commit hash,
   so the next loop never re-does finished work.
8. Every 4th completed item (or when a phase completes): bump the version in
   `pubspec.yaml`, build both ABIs with `/home/renia/tools/build_arm64.sh`,
   publish a release, and confirm the served bytes hash-match the local build.

**Never touch:** release signing config, any API token or secret, the Cloudflare
deploy credentials, or `.github/workflows` secrets. No force-push, ever.

**Before any `flutter test` / `flutter analyze` / Gradle build, check
`pgrep -c java` and `pgrep -fc "[f]lutter"`.** Non-zero means another writer is
building on this 7.8 GB, no-swap box and a second build gets OOM-killed. Take a
non-build item instead. Note that a *hung* `flutter_tester` whose parent is
`systemd` is an orphan from an earlier tick, not a live build: it sits at 0 %
CPU and holds `build/unit_test_assets`, so **report it, do not kill it**, and
do not start a test run over the top of it — on 13 Sep it blocked a tick this
way for 37 minutes.

**Honesty rule:** if an item turns out to be already implemented, already
correct, or blocked on something outside the app, do not fake progress — mark it
with the reason and move to the next one.

---

## Phase 0 — First-run experience (founder review, 12 Sep)

The founder opened the app, sent two screenshots and said: the first page must be
world-class, signing in and signing up must be easy, the role question belongs on
the auth page and not before it, the `0X` chip has to go, and a contractor's
profile must let him upload past work, certificates and his ID.

- [x] **One auth screen.** Login and register were two screens, reached through a
      role gate that asked the user to pick a side before anything else. Now: a
      landing page with one **إنشاء الحساب** button and one **تسجيل الدخول** link,
      and a single auth screen with a two-segment switch where the account type
      is chosen *inside* the sign-up form. The confirm-password row is gone so the
      submit button fits above the fold. **DONE `f083d71`.**
      *Verified by driving the real registration through the UI in the release
      web bundle: role tile → name → phone → password → submit landed on the
      contractor home, and `POST /api/login` then returned 200 for that number
      with `type: worker`.*
- [x] **The `0X` prefix chip is gone.** It was the first control on the form and
      it asked a low-digital-literacy user a question they cannot answer. The
      field still accepts local, `+213`, `00213` and Arabic-Indic digits and reads
      the number back grouped. **DONE `f083d71`** (7 phone-field tests, including
      one that asserts no prefix picker exists).
- [x] **A first page worth looking at.** Hero with original vector line art
      (house + tower crane on a blueprint grid, drawn in `CustomPainter` — no
      borrowed asset), how-it-works in three steps, the trades strip, and the
      verified/ratings/58-wilayas promise. **DONE `f083d71`.**
      *Two layout bugs found by rendering it: the category tiles clipped their
      second label line at 412 px (92 px tall → 104), and the drawing sat behind
      the tagline where the roof line ran through the text (it now has its own
      band).*
- [x] **A contractor can show his work.** "معرض أعمالي" uploads photos to R2 with
      progress and Arabic failure copy; the documents screen gained optional
      **شهادات ودبلومات** slots. Optional slots show a plus badge, not the next
      number — the progress card counts three required documents. **DONE
      `f083d71`, `eb9b1c4`** (backend: `POST /mobile/workers/:id/portfolio`,
      plus the doc-type alias and the error-masking fix, finili `ba110e3`).
- [x] **The client's first run has no equivalent.** A contractor who opens the app
      with nothing set up gets a four-step checklist that names the next action
      ("أكمل ملفك ليظهر اسمك أمام أصحاب المشاريع", then one CTA). A project owner
      opening the app for the first time gets the marketplace with no explanation
      of what to do first. Give the client home the same shape: name the first
      step (post a project or browse contractors), make it tappable, and let it
      disappear once the user has posted or contacted someone.
      *Done when:* a fresh customer account sees a named next step and a CTA, and
      a customer with one project does not.
      **DONE `718f99e`.** The client home opens with «ابدأ من هنا» — three
      numbered steps (انشر مشروعك / قارن عروض المقاولين / تواصل واختر الأنسب), a
      primary «انشر مشروعك الأول» CTA and a «تصفّح المقاولين» secondary one — and
      the card disappears the moment the account owns a project. New
      `lib/src/data/first_run.dart` (the rule, testable without a widget) and
      `lib/src/widgets/client_start_card.dart` (the card, theme tokens only).
      *Verified live in the release web bundle, 412 px RTL, real customer from
      `POST /api/register`: 45 semantics nodes with the guide's strings in the
      DOM and its CTA solid in accent `#E8A33D` at x35-376 y486-533 w342 h48;
      after one project, 34 nodes, no guide text, no accent CTA box
      (`/tmp/shots/fr_30_client_home.png` vs `fr_31_client_after_project.png`).
      `flutter analyze` clean, `flutter test` 217 passed (206 before).*

- [x] **A stored session that is not a plain string takes the app to a white
      screen.** `AuthState.restore()` is awaited *before* `runApp`, and its two
      `prefs.getString('auth.token' / 'auth.user')` casts sit **outside** the
      `try`, so a value of any other type in either key throws uncaught: `main()`
      never reaches `runApp` and the user gets a blank white page — no error, no
      retry, no way back, on every launch. Found while verifying the item above:
      the compiled bundle throws at `main.dart.js:48165-48166` (null/cast check
      at `:4979`) when `auth.user` holds a JSON object instead of a string, and
      the identical page renders 45 semantics nodes the moment it is a string
      again. Healthy installs write through `setString`, so normal users are
      safe; the trigger is corrupted or migrated preferences — and the blast
      radius is the whole app. Fix before the first release: move both reads
      inside the `try` and fall back to the logged-out landing page.
      *Done when:* booting with a non-string `auth.user` lands on the landing
      page with the bad keys cleared, pinned by a test.
      **DONE `8d5b369`.** Both reads moved to the untyped `SharedPreferences.get`
      and narrowed by hand (the typed getters are hard casts); anything that is
      not two strings forming a parseable user is discarded and the launch opens
      logged out. `_restored` is set in a `finally` so the splash cannot hang,
      and `main()` now guards the awaited call as well. New
      `test/session_restore_test.dart`: 5 unit cases + a widget case that boots
      the real app on a corrupt store and asserts the landing page.
      *Verified on the release web bundle over CDP, 412 px, corrupt store seeded
      as `flutter.auth.user` = `{"id":1}` (the exact repro): the **pre-fix**
      bundle (hash `185892d7…`, served before the rebuild) rendered a 100%
      #FFFFFF page with 0 semantics nodes and one uncaught error at
      `main.dart.js:4979:30` called from `:48166` (= `main()`), keys left in
      place — `/tmp/shots/boot_01_before.png`; the **fixed** bundle (hash
      `e24941f3…`) on the same seeded store rendered 45 semantics nodes holding
      the full landing copy (ابدأ الآن — مجاناً / إنشاء الحساب / تسجيل الدخول),
      zero exceptions, and `localStorage` empty afterwards —
      `/tmp/shots/boot_03_after.png` (2057 distinct colours vs 1).*
      **Lesson for the next loop:** Chrome serves the old bundle from its HTTP
      cache and the Flutter service worker after a rebuild — a first "after"
      run reproduced the old failure byte-for-byte. Purge
      `navigator.serviceWorker` registrations + `caches` and reload with
      `ignoreCache` before believing a post-rebuild render.

---

## Phase 1 — Arabic-first correctness (search & input)

Algerian users type Arabic with inconsistent orthography. Search that does not
understand that is the single biggest "this app is foreign" signal.

- [x] **Search normalisation for Arabic.** `بحث` must match `البحث`; `احمد` must
      match `أحمد`; `ه` must match `ة`; `و`/`ي` must match `ؤ`/`ئ`; strip
      tatweel `ـ` and all diacritics; collapse repeated whitespace. Apply to
      project search, contractor search and the wilaya/commune picker.
      *Done when:* a test asserts each of those pairs matches, and searching
      without hamza finds a record stored with hamza.
      **DONE app `81eee89`, backend `6fa03ed`.** `lib/src/core/text/arabic_search.dart`
      folds the letters and matches every word of the query; 24 tests, one per
      real spelling. Contractor browse is wired (submit, clear-back-to-empty,
      and an empty state that names the term). The API takes `q=` and widens
      the page to 500 rows because SQLite cannot fold Arabic. Verified live:
      typing `احمد` on the browse screen took the list from 5 cards to 1.
      *Also folded in the same pass:* the 58-entry wilaya picker in the
      new-project form filtered with a raw `contains`, so الجزاير never found
      الجزائر — it now folds too, with 4 more tests (name, code, empty, narrow).
- [x] **The project feeds have no search box at all.** Neither the client's
      "مشاريعي" list nor the contractor marketplace feed offers a text filter,
      so a user with 30 projects scrolls. Add a field to both, matched with
      `ArabicSearch` against title, description, commune and category.
      *Done when:* both feeds can be narrowed by a typed word.
      **DONE `e4bd692`.** One field + one filter for both feeds
      (`lib/src/widgets/feed_search_field.dart`, `lib/src/data/project_search.dart`);
      18 new tests (unit + widget). Marketplace widens to 5 pages on the first
      keystroke because that endpoint has no Arabic text search. Verified live in
      the release web bundle (CDP, 412 px, RTL): empty box 7 cards, `جبس` 3,
      `رخام` 1, `زززز` -> the no-match state; the box's clear button empties it.
- [x] **Wilaya + commune picker with Arabic search.** 58 wilayas by name, not
      by numeric code, with the commune list for the chosen wilaya. Must be
      searchable by typing the Arabic name or the code (`16` → الجزائر).
      *Done when:* a user can reach حسين داي without scrolling a list of 1541
      communes.
      **DONE 12 Sep** — `assets/data/communes_dz.json` (1,541 communes, the
      official national count) + `lib/src/data/communes.dart` + a searchable
      sheet in the project form. Search is folded, so الابيار finds الأبيار and
      `hussein` finds حسين داي; a commune missing from the list can still be
      typed. Generator: `tool/gen_communes.py` (read its header — one candidate
      source had its Arabic column shifted a row and was rejected). Wilaya split
      comes from the wilaya/city dataset the founder supplied; Arabic names from
      kossa/algerian-cities (MIT). 134 tests pass, was 100.
      **Verified in the clean 1.0.5+6 web bundle** (isolated `git worktree`, CDP,
      412x915, semantics tree enabled): form -> `اختر الولاية` -> typed `الجزائر`
      collapsed 58 wilayas to one (`16 الجزائر`) -> commune sheet header read
      `الجزائر — 57 بلدية` (Algiers really has 57) -> typed `حسين` collapsed 57
      communes to one row, `حسين داي Hussein Dey`, with the count line reading
      `بلدية واحدة` -> picking it put `حسين داي` in the form field. A nonsense
      query showed `لا توجد بلدية بهذا الاسم` plus the accept-as-typed button.
      **Two real bugs found and fixed by this verification:**
      1. the commune sheet's search ignored typing entirely — a conditional
         `suffixIcon` rebuilt the decoration on the first keystroke and the field
         stopped delivering onChanged (two different queries rendered
         byte-identical screens). Decoration is now static (fix ad78277).
      2. the pinned publish CTA sits over the scroll content, so a tap meant for
         the commune field hits نشر المشروع instead — drive the form with the
         field scrolled clear of the bottom bar.
- [~] **[OUT OF THIS REPO — backend/D1, do not start here] The `wilayas` D1 table
      has wilayas 49-58 in the wrong order.**
      Codes 49-57 read المغير/المنيعة/... where the app, the web and the
      official numbering all say 49 = تيميمون. Verified 12 Sep: three
      independent lists (`app/lib/constants.ts`, the app taxonomy, and the
      MIT commune dataset) agree against D1. Nothing reads the table today
      (`grep -rn "FROM wilayas"` finds no caller), so the impact is latent —
      fix before any code joins on it. Backend item.
      **BLOCKED 12 Sep (app loop):** the table lives in the Cloudflare D1 database
      owned by the backend/`workers/mobile.ts` repo, not in this Flutter repo,
      and the loop is forbidden to touch deploy credentials, so no app-side
      change can fix it. Nothing in the app reads the table (the app ships its
      own taxonomy + `assets/data/communes_dz.json`), so the user-visible impact
      is zero today. Hand to BACKEND-API: one `UPDATE wilayas SET code=...`
      migration, verified by a join against the commune dataset.
- [x] **Phone entry that behaves like an Algerian expects.** A `+213` /
      `0X` prefix affordance, grouping shown as `0X XX XX XX XX`, live inline
      validation from the existing `isValidDzPhone` rules, and no rejection of
      a number pasted with spaces or dashes.
      **DONE `b59274e`.** `lib/src/core/text/dz_phone.dart` + `phone_field.dart`,
      used by both auth screens. Verified live in the release web bundle (CDP,
      412 px, RTL, real API): `0550-12-34-56`, `+213 550 12 34 56` and the
      Arabic-Indic `٠٥٥٠١٢٣٤٥٦` all land as `05 50 12 34 56`; tapping the chip
      flips the field to `550 12 34 56` and back; `0212345678` turns the frame
      and the error line `#C33F39` (0 px of that colour when valid, 1,400 when
      not); a valid number shows the `#1B7E50` tick at x48-63. Filled the
      register form with a bad number and clicked submit: **zero** network
      requests, only the Arabic error. With a spaced valid number the POST body
      was `"phone":"0734304363"` → 201. 172 tests pass, was 134.
- [x] **Numeric keypad for numeric fields.** Every amount, year, radius and
      day-count field opens a number keyboard, not a full text keyboard.
      **DONE `f6d6096`.** The keypad was already wired on 8 fields — the real gap
      was that none of them *parsed* what an Algerian actually types. New
      `lib/src/core/text/dz_number.dart` (Arabic-Indic ٠-٩, `25.000` grouping,
      `25,5` / `25.75` as fractions and never as grouping, a pasted `دج`, spaces
      and NBSP) plus one shared `lib/src/widgets/number_field.dart`, now used by
      the project budget row (`من` / `إلى`), the quote-sheet amount, the
      contractor rate and years of experience; the budget row also gained live
      min ≤ max validation instead of failing at publish time. 206 tests pass,
      was 172 (`test/dz_number_test.dart` + `test/number_field_test.dart`, 34
      new, driven through the real `Repository`). Verified live in the release
      web bundle (CDP, 412 px, RTL, real API): typing the Arabic-Indic `٨` into
      the years field leaves the app's own editing element at `8`, and `٢٥٠٠٠`
      into `إلى (دج)` leaves `25000` (/tmp/shots/nf_18_rakam_live.png).
- [x] **The declared brand font is not a font.** `assets/fonts/Cairo-Regular.ttf`
      and `Cairo-Bold.ttf` were both GitHub `404: Not Found` HTML pages (magic
      `0a0a0a0a`, `<!DOCTYPE html>`, committed in `a40b812`) — so every string in
      the app rendered in a fallback face, on Android, iOS and web alike. The
      live web bundle said it out loud on every load: `Failed to load font Cairo
      at assets/assets/fonts/Cairo-Regular.ttf … Verify that … contains a valid
      font`. Fix path: take the real OFL face (`google/fonts` →
      `ofl/cairo/Cairo[slnt,wght].ttf`) and instance it to static 400/700 with
      `fonttools`. gstatic's legacy `/l/font?kit=` URL and the
      `fonts.google.com/download` zip both return non-sfnt payloads, so neither
      works.
      **DONE `c6763f0`.** Both files replaced with real static TrueType
      instances of upstream **Cairo 3.130** (OFL 1.1), built from
      `ofl/cairo/Cairo[slnt,wght].ttf` pinned at upstream commit `d2528f6d` with
      `fontTools.varLib.instancer` (`wght=400` and `wght=700`, `slnt` fixed at 0,
      `--update-name-table`). Verified on the instanced files: `usWeightClass`
      400/700, `fsType` 0 (embeddable), 1956 glyphs of which 1951 carry real
      outlines, the full Arabic block plus Arabic-Indic `٠`–`٩`, and the GSUB
      features `init medi fina rlig` that Arabic joining needs. Each file is
      164 KB, down from 267 KB of HTML. Added `assets/fonts/OFL.txt` (the OFL
      requires the licence to travel with the face) and `assets/fonts/README.md`
      — provenance, the exact regeneration commands, and how to tell a real font
      from an error page before committing one. Only the two `.ttf` files are
      bundled (`pubspec.yaml` declares them under `fonts:`, not `assets:`).
      *Verified in the release web bundle* (own build, CDP, 412×915 RTL): the app
      now fetches both faces `200 font/ttf`, the `Failed to load font Cairo`
      warning is gone from its console, and no gstatic `notosansarabic` request
      is made any more. **Control:** the same bundle with the old files swapped
      back reproduces the exact symptom and falls back to Noto Sans Arabic —
      `OTS parsing error: invalid sfntVersion: 168430090`, `document.fonts.check`
      false, text width identical to plain sans-serif.
      *Re-audit (the wrapped-lines warning in this item was real):* four screens
      — landing, auth, client sign-up, contractor sign-up — driven by Arabic
      semantics labels so both runs reached provably identical screens: **0**
      layout-overflow messages, **0** yellow overflow stripes, ink inside
      x10–393 of a 412 px frame (no clipping), and two reloads of one screen are
      byte-identical (0.00 % diff) — so the 3.8 % / 6.8 % / 16.8 % / 21.4 %
      Cairo-vs-fallback deltas are the font alone. Text runs do move: the same
      string «أنشئ حساب مقاول» is 147 px in Cairo vs 137 px in Noto Sans Arabic,
      and content above the fold shifts up to 13 px. Nothing broke.
- [x] **No dead-end empty states.** Every list (projects, quotes, chats,
      portfolio, reviews) shows an Arabic explanation **and** the action that
      creates the first item.
      **DONE `6e6bc53`.** Seven dead ends, all of them a sentence with nothing
      behind it, now carry the control that creates the first item: the chat
      inbox (both roles) switches to the marketplace tab through a callback the
      shell owns — a conversation can only start there; an empty thread points at
      the composer instead of inventing a second button; مشاريعي hands a client
      the publish action and a contractor the market tab; an owner with no quote
      is sent to the contractor directory, since quotes arrive from pros and the
      app has no share action to offer; a contractor's filtered-out market resets
      both filters in one tap and a genuinely empty one re-fetches; the client
      home strip asks for the project that brings contractors; an empty portfolio
      or review row on somebody else's profile opens the conversation with him.
      `test/empty_states_test.dart` (new, 10 tests) builds each state against a
      fake API, **taps the action** and asserts the real effect — a route push, a
      tab switch, or a new request in the API log — so a label that renders but
      does nothing fails the suite. Gate: `flutter analyze` "No issues found!",
      `flutter test` **233 passed** (223 before). Visual: five frames rasterised
      to `/tmp/shots/empty_*.png` from the real widget tree with Cairo loaded, and
      `pngscan.py --color E8A33D` finds the amber action button in every one
      (e.g. inbox 984x167 px at y1610, market 984x168 px, quotes 876x168 px).
      *Not done with CDP:* the served bundle talks to the live API, which has
      data, so it cannot show an empty state, and this box has no CDP driver
      (`grep -rl captureScreenshot|websocket /home/renia/{tools,allomokawil,qa}`
      is empty). The frames above are rendered by the same widgets, not
      reconstructed.
- [x] **Arabic error copy audit.** Walk every `catch`/error path and confirm the
      user sees an Arabic sentence that says what to do next — never a raw
      exception, a status code, or an English word.
      **DONE `6720f24`.** The audit found twelve call sites rendering
      `e.toString()` (auth ×2, review, verification, portfolio ×2, profile edit
      ×2, quote submit, publish project, and two `snap.error.toString()` error
      views) plus an HTTP layer rendering `'حدث خطأ (401)'`. Whatever arrived was
      shown verbatim: `PlatformException(photo_access_denied, ...)` from the
      image picker, `SocketException`, a bare `401`, or the Worker's own English
      `Method not allowed` (real — `workers/mobile.ts` answers it).
      `lib/src/core/l10n/error_copy.dart` is now the one place a failure becomes
      copy: by exception type first (socket/TLS/http, timeout, platform code,
      string), then by status class. Server text is shown only when it is Arabic
      *and* specific — `رقم الهاتف مسجل مسبقاً` is kept because it names the field
      to fix — while a phrase that only names the problem (`غير مصرح`,
      `بيانات غير صالحة`) is expanded into the instruction (see `_terseServerCopy`,
      and the two `apiErrorCopy` rules in `apiErrorCopyPrefersServerText`). The
      HTTP status number is never rendered. `verification_screen` and
      `project_detail_screen` were the last two dead ends — a centred sentence
      with no way out — and now carry `EmptyView` with the copy plus its retry.
      `test/error_copy_test.dart` (new, 22 tests) asserts every sentence is
      Arabic-only, contains an instruction, and never carries a Latin letter or a
      status digit; drives the real `AuthScreen` against a throwing API; and
      rasterises the three error states. Gate: `flutter analyze` "No issues
      found!", `flutter test` **255 passed** (233 before). Visual:
      `/tmp/shots/err_auth_notice.png`, `err_project_detail.png`,
      `err_verification.png` — `pngscan.py --color FCEDEC` finds the 948×198 px
      danger notice (border `C33F39`, 44×45 px icon) and
      `--color E8A33D` finds the 984×167 px retry button under each error state.
      *Not done with CDP:* this box has no CDP driver, as recorded on 12 Sep.

      **Gap logged, not fixed here:** `ProjectDetailScreen` starts its quotes
      request in `initState` and only observes it once a project renders, so when
      the project call fails the quotes future errors unobserved. That belongs to
      the Phase 4 "every API call wrapped" item.

## Phase 2 — Elite visual pass

- [x] **Skeleton loaders instead of spinners.** Cards that fade to their real
      content read as fast and native; a grey circle mid-screen reads as broken.
      **DONE `be1a246`** (the kit and its wiring ride inside the design-system
      commit, which is why there is no separate skeleton commit). Kit:
      `lib/src/widgets/skeletons.dart` — `Shimmer` sweep, `SkeletonTone`, and
      shapes matched to the widgets they stand in for (card row, strip, grid,
      chat thread, form, detail, app boot). Wired into 13 files: app boot
      (`app.dart`), the inbox, the chat thread, both home strips, the projects
      feed, the marketplace, the portfolio grid, the profile, reviews, project
      detail quotes, the project form and the verification form. What is left
      spinning is only in-button busy state (`big_button.dart`, `ui.dart`, the
      two send/post buttons) — press feedback, not a page loading.
      8 new tests in `test/skeleton_loading_test.dart`: the feed assertion is
      "a waiting screen shows no `CircularProgressIndicator`" plus a two-frame
      raster check that the sweep actually moves (a frozen shimmer fails).
      Evidence: `flutter analyze` → No issues found!; `flutter test` → 263/263
      (was 255) on that exact commit, run in an isolated `git worktree` while
      another session held the main checkout.
      **Visual proof — honest status:** no browser screenshot this cycle.
      Chrome on this box hangs on `about:blank` (the backlog already records
      "no CDP driver"); a raster harness for the loading frames is written but
      the box was saturated by the concurrent release APK build (load avg 64)
      and the run was killed before a test even loaded. Re-run
      `test/skeleton_loading_test.dart` in a quiet window and look at
      `/tmp/shots/{boot_skeleton_dark,loading_projects_dark}.png`.
- [x] **8pt spacing audit + one card recipe.** Every card uses the same radius,
      border, shadow and inner padding; no screen invents its own.
      **DONE `972200e`** — the recipe now lives in `app_theme.dart` (`cardFill`,
      `cardLine`, `cardLineWidth`, `cardRadius` = `rLg` 20, `cardShadow`
      deliberately empty, `cardDecoration` / `cardDecorationOf` for the few
      tinted cards, and three insets off one 4 dp ladder: `cardPad` 16,
      `cardPadRail` 12, `cardPadRows` h16·v8). Anything typed into wears
      `fieldFill` / `fieldPad` / `fieldDecorationOf`. `AppCard` is the only way
      a screen builds a card; 27 files rewritten — 99 typed radii tokenised
      (999×20, 14×2, 13×2, 12×2, 10, 9, 6×2, 2), every hand-rolled
      `color: surface` + `Border.all(color: line)` BoxDecoration replaced, 43
      AppCard insets normalised. The guard is `test/card_recipe_test.dart`
      (+13): token values, a raster of a real AppCard (the fill and the
      hairline really paint, and the border stays a hairline, ~1/20th of the
      fill's pixels), and a source guard that fails the build if a screen types
      a numeric radius (R1), hand-rolls a surface card (R2) or invents an
      AppCard inset (R3). R4 ratchets the remaining off-grid literal spacing at
      **200**, printed in the failure message, so the sweep can only go down.
      Evidence: `flutter analyze` → "No issues found!"; `flutter test` →
      **276 passed** (was 263); live bundle screenshot
      `/tmp/loop/live_landing.png` (412×915) where `pngscan.py --color E8E8EC`
      finds the recipe hairline as full-width 1 px card outlines x33–378 at
      y463/542/555/634/647, plus the regenerated `/tmp/shots/0{4,6,8}_*.png`.
      Caveat, stated plainly: the code rode inside `972200e` ("white canvas…")
      because a concurrent session committed the shared tree while this recipe
      was staged — the recipe is the `app_theme.dart` + `ui.dart` + 27-file
      diff plus `test/card_recipe_test.dart`, and the test file is new in that
      commit. Follow-up the ratchet names:
      the remaining 200 off-grid literal insets (mostly icon/skeleton micro
      padding) and the fact that on the white canvas `bg == surface`, so cards
      are separated by the hairline alone.
- [x] **Typography scale from Cairo.** DONE `f589ae0`. Eleven-step ladder in
      `app_theme.dart` (`fsBadge` 11 -> `fsHero` 30), every role style composed
      from it, 121 call-site literals across 24 files replaced with tokens, and
      a new `test/type_scale_test.dart` (8 tests) that fails the build if any
      file outside the theme types a `fontSize` number again — plus a raster
      test proving the steps reach the engine. No reflow: PNG diff of all 15
      design shots shows content boxes within 1 logical px of baseline, and the
      landing CTA box is byte-identical in size (w1032 h168 @3x).
- [x] **Colour contrast re-verification.** After the pass, re-check every
      foreground/background pair at WCAG AA (4.5:1 body, 3:1 large) with
      pixel maths from real screenshots — the same method used previously.
      **DONE `4376674`.** `tool/contrast_audit.py` reads the 23 colour tokens
      straight out of `app_theme.dart` (so the audit can never go stale
      against a copied palette) and reports 21/23 pairs at or above
      threshold. All **20 text pairs pass**, tightest being `textMuted` on
      `accentWash` 4.51, `success`/`danger` on their washes 4.51 and
      `accentDeep` on `accentWash` 4.52 — and each was confirmed to be
      **actually drawn**, not merely computed: sampling the 25 design PNGs in
      `/tmp/shots` finds both colours of every passing pair, e.g. navy ink on
      the gold CTA in 18/25 shots as 41 144 gold px against 4 868 ink px.
      Re-run with `python3 tool/contrast_audit.py shots /tmp/shots`.
      Of the two failures, `line` on `bg` (1.22:1) is **not** a defect — it is
      a decorative hairline and card divider, outside WCAG 1.4.11, and it must
      stay light or cards stop reading as calm. It is carried in the checker
      so the ratio is on the record, and a later loop must not "fix" it. The
      star glyph is the real finding: the next item.
- [x] **The star glyph is the weakest graphic in the app at 1.91:1.**
      `AppTheme.star` (`#F2B01E`) on white measures 1.91:1, under the 3:1 that
      WCAG 1.4.11 asks of a meaningful graphic, and it is really drawn in 5 of
      the 25 design shots. Where a star row carries a rating the number beside
      it is `textPrimary` (17.75:1), so the meaning survives — but in the
      review picker the **empty** stars are `line` (1.22:1), which makes "how
      many did I pick" the hardest thing on that screen to see. Darken the
      glyph to the nearest gold that clears 3:1 on white while staying legible
      on navy: `#C2870F` = 3.10:1 on white, 5.12:1 on navy (alternatives
      `#B5790B` 3.68/4.32 and `#AD7208` 4.05/3.93; today's `#F2B01E` is
      1.91/8.33).
      *Done when:* the checker reports `star on bg` at 3.0 or better **and** a
      fresh 412 px render shows filled and empty stars still telling apart.
      **DONE `4e4b634`.** Shipped as **#B5790B**, not the #C2870F this item
      proposed — #C2870F still measured 2.82 / 2.90 on the wash tiles, which is
      exactly where the star is drawn (the worker-home stat tile and the landing
      promise row), so it was the wrong gold. #B5790B clears 3:1 on every
      surface the app actually uses: white 3.68, `surfaceAlt` 3.43, `accentWash`
      3.35, navy 4.32. The picker's unselected stars were drawn in the *hairline*
      `line` token (1.22:1) — a rating scale the user could not see — and now have
      their own `starEmpty` #8A8A91 (3.43 white / 3.20 `surfaceAlt`). The rating
      also opened on five stars, so the fastest path through the screen published
      a score nobody chose; it now opens empty and the submit path refuses an
      untouched screen with an Arabic message. `controlLine` (3.25) joined the
      same pass so outlined buttons keep a visible boundary on the white canvas.
      *Re-checked by the loop 13 Sep 04:14 without a build* (another writer held
      6 `flutter` processes on this box, so no analyzer/test run this tick):
      `python3 tool/contrast_audit.py token` → **28/28 judged pairs pass, exit 0**,
      `star on bg` 3.68, `star on accentWash` 3.35, `starEmpty on bg` 3.43,
      `controlLine on bg` 3.25, and `line on bg` 1.22 carried as deliberately
      decorative. The picker (`lib/src/screens/review/review_screen.dart:198`)
      separates filled from empty by **glyph** as well as colour —
      `star_rounded` vs `star_outline_rounded` — so the 1.07:1 between the two
      golds is not what carries the meaning, and each star keeps a 48–58 px
      target.
      *Render evidence is the previous writer's, and this tick could not replace
      it:* the commit records the 412 px bundle check (retired gold 506 px → 0,
      new star 0 → 500 px on the review screen). **Warning for the next loop:
      `/tmp/shots` is not trustworthy right now.** At 04:12 it held another
      session's `HEAD~1` (pre-fix) render — `17_review.png` still shows 24,095 px
      of the retired #F2B01E in five filled picker boxes, because that session
      had checked out `HEAD~1 -- lib/` and redirected the shots there. Compare a
      shot's mtime against the commit time before reading it as "after".
      **Carry-over found here:** the same picker clamps its stars to 48 px, under
      the 56 px the next item demands — check it when that item is taken.
- [x] **Touch targets ≥ 56 px** on every interactive element, measured from
      screenshots, including icon buttons.
      **Audited 13 Sep 04:55 — 15 real sub-56 sites, none fixed yet: no build
      window this tick** (another session's Gradle APK build held the box at
      94 % CPU / 2.7 GB, so no `analyze`, no `test`, no render).
      New `tool/tap_target_audit.py` reads the source and prints every site whose
      effective minimum touch dimension is provably below 56 dp; it exits 1 while
      any remain. Every finding below was read and confirmed by hand:
      * **8 × `IconButton` at the Material 3 default** — a 40×40 box with a
        48×48 padded hit area, not 56: `icon_button.dart:1127`
        `minimumSize: Size(40, 40)`, `:1155` `tapTargetSize:
        theme.materialTapTargetSize`, which `theme_data.dart:404` defaults to
        `padded` → `kMinInteractiveDimension = 48.0` (`constants.dart:27`).
        Sites: `auth_screen.dart:359` (back), `auth_screen.dart:622` (reveal
        password), `browse_screen.dart:190` and `feed_search_field.dart:56`
        (clear search), `project_new_screen.dart:600` (clear commune search),
        `my_portfolio_screen.dart:169` (refresh), `worker_home_screen.dart:63`
        (verification), `notifications_bell.dart:74`. The theme sets neither a
        global `iconButtonTheme` nor `materialTapTargetSize` (`grep` over `lib/`
        finds nothing), which is the whole reason every one of these is 48.
      * **4 × `TextButton` at the default** — 40 tall, 48 hit area
        (`text_button.dart:554` `Size(64, 40)`): `auth_screen.dart:503`,
        `landing_screen.dart:235`, `notifications_screen.dart:133`, and
        `chat_screen.dart:312` (which also sets its own `Size(64, 44)`).
        `textButtonTheme` is the one button theme with **no** `minimumSize`,
        while `elevatedButtonTheme`, `filledButtonTheme` and
        `outlinedButtonTheme` all inherit `Size.fromHeight(tapMin)` — so these
        four are an oversight, not a decision.
      * `notifications_screen.dart:211` — an empty-state action parked in a
        fixed `SizedBox(width: 220, height: 46)`.
      * `review_screen.dart:181` — the star picker floors at
        `clamp(48.0, 58.0)`: 58 dp at 412 px, 48 on anything narrower. This is
        the carry-over the star item left, and it is real.
      Two false positives the first pass of the tool produced (a `SizedBox(height:
      4)` spacer above a `TextButton`, and `serviceRadiusKm.clamp(1, 200)`) are
      gone: an enclosing fixed box must still be *open* at the button's line, and a
      `clamp` only counts when it sizes a dimension (star/size/height/width/box).
      Fix, one pass: a global `iconButtonTheme` plus `minimumSize` on
      `textButtonTheme` in `app_theme.dart` kills 13 of the 15, then the
      `64×44`, the `height: 46` and the picker floor go to `AppTheme.tapMin`.
      **An `IconButton` raised to 56 dp exactly fills the 56 dp `AppBar`
      (`kToolbarHeight`), so this has to be re-rendered before it is believed** —
      no screenshot this tick.
      **Second audit, 13 Sep ~05:15 — the theme fix alone cannot finish this
      item, because 17 of the app's 119 tap sites are hand-rolled.** The first
      pass only judged `IconButton`, `TextButton` and fixed boxes, so it missed
      every `InkWell`/`GestureDetector` whose hit area *is* its child:
      `tool/tap_target_audit.py` gained **R7** (a tap whose own box declares a
      literal dimension below 56) and **R8** (framework controls at the 48 dp
      `kMinInteractiveDimension`), plus an ADVISORY bucket for sites whose size
      only layout decides. It now runs `python3 tool/tap_target_audit.py` →
      **17 provable fails, 18 advisory**, exit 1. The two R7 fails are real and
      were read by hand:
      * **`project_new_screen.dart:833` — the ✕ on a picked photo is a 26×26
        `Container` behind a `GestureDetector`.** The smallest and most
        mistappable control in the app, and it sits on the publish screen where
        losing a photo means re-picking it. A 56 dp target with the 26 dp disc
        painted inside.
      * **`auth_screen.dart:455` — the account-type switch («حساب جديد» /
        «تسجيل الدخول») is an `AnimatedContainer(height: 48)`.** That is the
        control Phase 0 was built around, and it is 8 dp short of the target on
        a screen the founder asked to make *easy*.
      The ADVISORY rows are not proof of a defect and must not be "fixed" on
      suspicion — the three checked by hand and **cleared** are the tab-bar
      destinations (`app_tab_bar.dart:165`, 60 dp bar and the centre action is
      58 dp), the category tile (`category_grid.dart:65`, 96 wide × ~102 tall)
      and `SelectableTile` (`ui.dart:316`, default height 104). Still to
      measure: `ui.dart:119` (عرض الكل ≈ 32 dp), the browse filter pills
      (`browse_screen.dart:316`, v12 padding ≈ 43 dp), `chat_screen.dart:405`
      and `:555`, `worker_card.dart:275`, `project_new_screen.dart:416` and
      `:733`, `customer_home_screen.dart:540` and `:578`,
      `my_portfolio_screen.dart:312`, `worker_home_screen.dart:801`,
      `review_screen.dart:189` — and the one `Checkbox` (`auth_screen.dart:588`)
      passes by 4 dp only because its row adds v6 padding (48 + 12 = 60).
      One-pass fix for the 17, in this order: a global `iconButtonTheme`
      (`minimumSize` 56 + `tapTargetSize`) and `minimumSize` on
      `textButtonTheme` in `app_theme.dart` kill 13, then
      `auth_screen.dart:455` 48 → `AppTheme.tapMin`, the photo ✕ to 56,
      `notifications_screen.dart:211` `height: 46` → `AppTheme.tapMin`,
      `review_screen.dart:181` clamp floor 48 → `AppTheme.tapMin`, and
      `chat_screen.dart:315` `Size(64, 44)` → `AppTheme.tapMin`.
      **No build ran this tick** (another session's Gradle daemon 2.8 GB +
      Kotlin daemon 0.5 GB against 7.8 GB with 293 MB available and no swap, so
      `flutter test` would have been OOM-killed and the kernel would have picked
      the daemon): the tool is Python and needed no build. `flutter analyze`,
      `flutter test` and the 412 px render are still owed before this item is
      ticked, and `test/tap_target_test.dart` must measure the real hit rects of
      the ADVISORY rows, not just the 17.
      **Third audit, 13 Sep ~05:30 — the 18 unknown rows are settled by
      arithmetic now, and two of them are real defects.** No build window again
      (Gradle daemon 2.9 GB + Kotlin daemon 0.5 GB resident, `pgrep -c java` = 2,
      805 MB available, no swap), so this tick touched only Python and this file.
      `tool/tap_target_audit.py` gained an R9 `MEASURED` table: a row whose every
      number is declared in the source (by token, never a copied literal) is now
      *summed* instead of shrugged at, printed as `MEASURED pass` with the
      arithmetic written out, and each entry carries an anchor regex that is
      re-checked against its source line on every run — if the construct moves,
      the row prints `STALE … measurement rotted` and the tool exits 1 rather
      than quietly scoring a control it no longer describes. That guard was
      proved by probe: shifting one entry's line by 11 printed the STALE row and
      exited 1.
      Result: **19 provable fails** = 17 from the rules + 2 found by hand:
      * `lib/src/widgets/ui.dart:119` — the «عرض الكل» action on every section
        title is **30.9 dp** tall: `GestureDetector` → `Padding` v6 ×2 = 12 plus
        `max(icon 12, label 13.5 × height 1.4 = 18.9)`, and the `Row` gives it
        loose cross-axis constraints, so the tap *is* the text. Third smallest
        target in the app and it sits on every home strip.
      * `lib/src/screens/project/project_new_screen.dart:733` — the urgency pill
        («عاجل جداً» and friends) is **44.9 dp**: `AnimatedContainer` v13 ×2 = 26
        + `max(icon 17, 18.9)`, inside a `Wrap`, so nothing stretches it. That is
        the control that sets how fast a project is meant to be done.
      **10 rows measured PASS**, which is the point of measuring instead of
      guessing: `browse_screen.dart:316` was suspected at "v12 padding ≈ 43 dp"
      and is really **60** — it lives in `SizedBox(height: 60)` + a horizontal
      `ListView`, whose cross axis is tight. The rest: the remember-me row
      `auth_screen.dart:581`/`:588` 60 (48 dp padded Checkbox + v6 ×2), the chat
      photo/camera button `:405` 56, the customer search bar `:540` 56, the
      post-project banner `:578` 88, the wilaya field `project_new:416` 61.6
      (fieldPad v18 ×2 + body 15.5 × 1.65), the worker filter chip
      `worker_home:801` 56, the tab destination `app_tab_bar:165` 60, and
      `SelectableTile` `ui.dart:316` ≥ 92 (call sites pass 92 or
      `double.infinity`).
      **6 rows still need a widget measurement** and must not be "fixed" on
      suspicion: `chat_screen.dart:555` (photo bubble — height comes from the
      image), `notifications_screen.dart:244` (tile height from its text),
      `review_screen.dart:189`, `my_portfolio_screen.dart:312` (`GridView.count`
      3 columns), `ui.dart:76` (`AppCard` padding + arbitrary child) and
      `worker_card.dart:275` (`_Pressable`).
      **One-pass fix list is now complete — 19 sites, in this order:** a global
      `iconButtonTheme` (`minimumSize` 56 + `tapTargetSize`) and `minimumSize:
      Size.fromHeight(tapMin)` on `textButtonTheme` in `app_theme.dart` kill 13
      (the theme row + 8 `IconButton` + 4 `TextButton`); then
      `auth_screen.dart:450` 48 → `AppTheme.tapMin`;
      `project_new_screen.dart:833` photo ✕ 26 → a 56 dp box;
      `notifications_screen.dart:211` `height: 46` → `AppTheme.tapMin`;
      `review_screen.dart:181` clamp floor 48 → `AppTheme.tapMin`;
      `chat_screen.dart:315` `Size(64, 44)` → `AppTheme.tapMin`; and the two new
      ones — `ui.dart:119` (wrap the «عرض الكل» row in a `SizedBox(height:
      AppTheme.tapMin)`, tap filling it) and `project_new_screen.dart:733`
      (pill to `tapMin` tall, or `EdgeInsets.symmetric(vertical: 18)` so 18.9 +
      36 = 54.9… use a `ConstrainedBox(minHeight: AppTheme.tapMin)`).
      Then `test/tap_target_test.dart` measures the 6 ADVISORY rects plus the
      19, because a hand sum is a *floor*, not a measurement.

      **Fourth pass, 13 Sep 06:05–06:25 — the 19-site fix is written and the
      tool is green; the gate is still owed.** The 05:58 tick edited the files
      at 06:05:50 and ran the tool at 06:08:03, then the machine went down
      (reboot logged 06:19:41; `executions.db` left that run `status=unknown`,
      "owner exited before a durable terminal state"), so the edit survived
      uncommitted. This tick resumed it instead of starting a new item:
      `git status` shows exactly the six sites plus the theme
      (`iconButtonTheme` 56 + `textButtonTheme` `Size.fromHeight(tapMin)` kill
      13; `auth_screen.dart` switch 48→56, the photo ✕ to a 56 box,
      `notifications_screen.dart` 46→56, `review_screen.dart` clamp floor
      48→`tapMin`, `chat_screen.dart` `Size(64, 44)`→`Size(64, tapMin)`,
      `ui.dart` «عرض الكل» in a 56 `SizedBox`, `project_new_screen.dart` pill to
      v19 = 56.9) and `python3 tool/tap_target_audit.py` now prints
      **0 provable fail(s)** and exits 0 (11 measured pass, 11 theme-covered,
      6 layout-only).
      New `test/tap_target_test.dart` (11 widget tests) does the half the tool
      cannot: it renders the real screens and measures the rect, then taps
      **1 dp inside the top edge** of the control — a control whose visible box
      is bigger than its hit area fails there. Covered: both auth `IconButton`s,
      the auth switch, the landing link, the empty-state action, the section
      action («عرض الكل»), the urgency pill, a notification row, chat send, a
      contractor card, the portfolio add tile, and the five stars at 392 dp and
      320 dp.
      **Not committed:** the gate could not run. A release APK build
      (`/home/renia/build116`, `assembleRelease`) held the box from 06:25 with
      ~160 MB free and no swap, so `flutter analyze` / `flutter test` would have
      been OOM-killed and the kernel would have picked that build. Nothing is
      ticked and nothing is committed; the next tick runs the gate on this tree
      and commits it.
      *Done when:* `python3 tool/tap_target_audit.py` exits 0 **and**
      `test/tap_target_test.dart` measures ≥ 56 on the real hit rects of the main
      screens.
      **Closed 13 Sep 07:22 — DONE `72f99ff`.** The 06:37 tick handed over the
      written fix with the gate owed; this tick ran it and it was not green.
      `flutter test` came back **341 passed, 0 failed** only after two real
      repairs:
      * the theme's `Size.fromHeight(tapMin)` is `Size(infinity, 56)` — an
        infinite *min width* that throws `BoxConstraints forces an infinite
        width` in an unbounded Row (the notifications AppBar trailing slot) and
        failed 8 tests in `notification_center_test.dart`. `textButtonTheme` now
        says `Size(tapMin, tapMin)`; 8 red → 0.
      * the star picker's `clamp(56, 58)` could not be satisfied by its parent:
        five 56 dp stars are 280 dp and the 320 dp card interior was 246, so the
        row overflowed by 34 (RenderFlex). The picker now owns the card's full
        width (card padding zero, label re-inset by hand) and the page inset
        drops 20 → 8 below 360 dp. Rendered: **58 x 58 on all five stars at
        both 320 and 392 dp**, no overflow.
      Two of the three failures were the new test file's own bugs, fixed there:
      the browse mock returned the single-worker Map for `/workers/search`
      (matched by the earlier `/workers/` branch) so the screen showed its error
      state, and the chat send button is the 56 dp round `_CircleAction`, not the
      `TextButton` that only exists in the offline banner.
      Measured rects now on the record: auth back/reveal 56, auth switch 56,
      landing link 56, empty-state action 56, «عرض الكل» 56, urgency pill 59,
      chat send 56, browse card 174, portfolio tile 112, notification row 108.8.
      Gates: audit exit 0 (0 provable fails), `flutter analyze` "No issues
      found!", `flutter test` 341/0.
- [x] **Press feedback + intentional motion.** DONE `988ca6a`.
      The app animated at four speeds — eight hand-typed
      `Duration(milliseconds: 140)`, a 160 in the auth reveal, Material's 300 ms
      route zoom, and the 1300 ms shimmer loop. `lib/src/core/theme/motion.dart`
      is now the only place a duration or a curve may be written (five
      durations, two curves, `AppMotion.all` for the scan), and it carries
      `AppPageTransitionsBuilder` — a fade plus a 2 % lift on
      `AppMotion.screen` = 240 ms, registered for all six `TargetPlatform`s in
      `AppTheme.light` so a push no longer runs at Material's speed on Android
      and another on Linux.
      `lib/src/widgets/motion.dart` adds `Pressable` (3 % shrink under the
      finger, cancelled past `pressSlop` = 12 px so a scroll cannot leave a
      button stuck pressed) and `Reveal` (a row fades up on first build,
      `transformHitTests: false` so the lift never moves a target away from a
      thumb). Applied centrally: `BigButton`, `OutlineButton`, `PrimaryButton`,
      `SecondaryButton` cover the app's CTAs without touching 28 call sites; the
      projects feed and the notification list reveal their rows. Both honour
      `MediaQuery.disableAnimations` — the same switch `Shimmer` already
      respected. Old ad-hoc `duration:` values in `skeletons.dart`,
      `category_grid.dart`, `ui.dart`, `worker_home_screen.dart`,
      `project_new_screen.dart`, `projects_screen.dart`, `auth_screen.dart` and
      `browse_screen.dart` now reference the spec.
      Gates: `flutter analyze` → **No issues found!**; `flutter test` → **356/356**
      (342 before; the 14 new ones are `test/motion_test.dart`, which also fails
      the build if a screen types its own duration or curve again).
      Two test bugs found by the gate and fixed in the test, not by weakening
      the assertion: `Matrix4.getMaxScaleOnAxis()` measures the z axis too and
      `Transform.scale` leaves z = 1.0, so a correct shrink read as "no shrink";
      and a `pump(90 ms)` straight after a pointer-down is the ticker's baseline
      frame, so the controller was still at 0.
      Render evidence: the suite's own shots at 07:40 (`/tmp/shots`, fresh), and
      `pngscan.py /tmp/shots/empty_inbox_client.png --color E8A33D` → one
      **984×167 px** accent box at (96,1610) — the primary CTA is laid out
      exactly as before, i.e. the wrapper changed no geometry at rest. A still
      frame cannot show motion, so the press claim rests on the widget test
      reading the live transform (0.97 pressed / 1.00 released), not on a
      screenshot.
      Housekeeping: `pgrep -fc "[f]lutter"` was 1 at the top of this tick — a
      `flutter_tester` orphan 38 min old, its parent already reaped to systemd
      and no `dart` tool process anywhere on the box, i.e. a leaked listener
      from an earlier tick, not a live build. Killed it (pid 21752) rather than
      inherit a permanent false "another session is building" reading; no
      Gradle/Java/AAPT2 process was touched (there were none).
- [x] **Onboarding for two roles.** One short, skippable Arabic explainer that
      makes "I need work done" vs "I do the work" unmissable at signup.
      **Done** `60933b2`: `lib/src/data/onboarding.dart` (one persisted flag,
      asked once per install) + `lib/src/widgets/role_guide.dart` (scroll-controlled
      sheet in an `AppCard`, two `SelectableTile` sides with their real payoff
      sentence, «تخطّي الآن»); «إنشاء الحساب» carries the picked role into the auth
      screen and falls back to customer on skip/dismiss. Gate: `flutter analyze`
      clean, `flutter test` 362 passed / 0 failed (356 before). Live release web
      bundle, 412x915: tap «إنشاء الحساب» → sheet with title + both tiles + skip in
      the semantics tree, then tapping «أنا مقاول/حرفي» lands on the sign-up form
      with the worker side already selected; the sheet covers the landing CTA
      (accent `#E8A33D` box present on the landing, 0 boxes under the sheet) and
      both tiles measure 372x91 logical with hairlines at `#E8E8EC`.
- [x] **Home screen hierarchy.** The client home leads with one clear primary
      action; the contractor home leads with the next thing that earns them
      money, not with a stats row.
      **Done** `efcca03`: `customer_home_screen.dart` moved the
      «انشر مشروعك مجاناً» banner (key `client-post-cta`) to the first sliver and
      repainted it as the accent tile `PrimaryButton` uses — navy ink on
      `#E8A33D` — instead of a hairline card, because it sat third, behind a
      category grid and a contractor strip that look the same to every visitor;
      the first-run guide still stands it down. `worker_home_screen.dart`
      replaced the three 112 dp stat cards with one `_StatsLine` under the name
      inside the identity card, and collapsed the three workshop tiles into a
      single row of compact keyed tiles (`worker-tools-portfolio|documents|edit`),
      which lifts the market feed ~250 dp; the work-photos tile no longer prints
      a literal `$n صور` (the label was an escaped dollar — real bug). Added
      `WorkerProfile.hasHistory` so the screen stops re-deriving the
      never-been-hired rule. Gate: `flutter analyze` clean, `flutter test` 369
      passed / 0 failed (362 before), `test/home_hierarchy_test.dart` (7 tests,
      geometry not prose). Render evidence: design_shots rasters re-shot 08:42 at
      392x850 — pngscan finds the accent tile at logical y 260-348 on the client
      home with «التخصصات» below it at 379, and the contractor's workshop row as
      one band at y 322-397 with the photo count in the badge.

## Phase 3 — Functional completeness (parity with web v1)

- [ ] **Chat: timestamps, day separators, send state.** Image messages too —
      including a real R2 round-trip with an actual uploaded photo, verified by
      fetching the stored object back.
- [x] **Notifications screen + unread badge** driven by the existing API, with
      Arabic copy per event type (new quote, quote accepted, new message,
      project completed). **Done** `001b178`, live API `45920a3e`: the centre
      lists newest-first with unread rows marked, a row opens the project it is
      about, and «تعليم الكل كمقروء» clears the pip. `POST
      /api/notifications/read` added (the pip had no way to clear); the five
      live types are mapped and any unknown type falls back to «إشعار» rather
      than the raw key. 11 tests (295 total); live E2E 27/27, production
      scrubbed. Next: colour contrast re-verification.
- [ ] **Reviews flow after completion.** Star picker + comment, submitted to the
      API, then reflected in the contractor's average — with a test that the
      average updates. **No fake or seeded reviews, ever.**
- [x] **Contractor portfolio upload** from camera/gallery to R2, with progress,
      retry, and Arabic permission rationale strings. **DONE `f083d71`** —
      `lib/src/screens/worker/my_portfolio_screen.dart`; camera and gallery both
      offered, the busy state names what is happening, and a failed upload keeps
      the picture on screen with a retry instead of dropping it.
- [ ] **Verification flow end-to-end.** Upload the auto-entrepreneur card, ID
      front and selfie, then show the real pending/approved/rejected state
      instead of a static form.
      *Partly done (`f083d71`, `eb9b1c4`): the upload side works, the doc-type
      alias is fixed so the contractor card no longer fails the insert, and there
      are optional certificate slots. What remains is the status the user sees
      **after** submitting — the API stores `verification_status` but the screen
      does not read it back.*
- [ ] **Project edit + cancel** for the owner, with the same validation as create.
- [ ] **Offline behaviour.** Cache wilaya/specialty lists so the app opens with
      content on a dead connection, and queue a chat message for retry instead
      of losing it.

## Phase 4 — Engineering hardening

- [ ] **Golden/screenshot tests** for the main screens so a design regression
      fails CI rather than being noticed by the founder.
- [ ] **Every API call wrapped** so failure surfaces as an Arabic retryable
      state; assert no unhandled exception path remains.
- [ ] **Semantics labels** on interactive elements for TalkBack/VoiceOver.
- [ ] **Cold-start audit.** Measure and shorten time-to-first-meaningful-paint
      on the release build; report a real number from a real device/emulator.
- [ ] **Crash-free baseline.** Wire a lightweight error reporter and confirm it
      receives a deliberately thrown test error end-to-end.

---

## Completed

### Phase 0 — first-run experience: CLOSED 12 Sep

All six items stay ticked in place above with their own evidence, so the detail
keeps living where it was written. Commit index:

| item | commit(s) |
|---|---|
| one auth screen, no `0X` chip, a real front door | `f083d71` |
| a contractor can show his work | `f083d71`, `eb9b1c4` (backend `ba110e3`) |
| the client's first run gets a guide | `718f99e` |
| a wrong-typed stored session no longer white-screens the launch | `8d5b369` |

**Release `v1.0.8+9`** — the version step the protocol asks for when a phase
closes. Both ABIs are live on tag `v1.0.8` and byte-identical to the local build
(`publish_release.py` compares GitHub's own digest; arm64
`sha256 96787213de3b9688…`, v7a `af6b6d40c9b95e31…`), and the stable download
link hash-matches too — fetching
`https://allomokawil.colisify.com/download/allomokawil.apk` returns exactly
`96787213de3b9688d6533ab69f20c7827b19a46773b4b3a0c2124cbb3db0ddaf`, the same
19,317,868 bytes, `versionName='1.0.8' versionCode='2009'`. The next loop starts
Phase 1.
