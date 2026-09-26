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

**Note (13 Sep 15:52) — `flutter test` leaks a tester, and the orphan rule has a
cost.** pid 226342 was spawned by the 15:13 gate run, watched that run finish
and commit `7f46d08` at 15:18, and was still alive at 15:52: `ppid` 1, 0.0 %
CPU, `wchan ep_poll`, holding fd 9 = `build/unit_test_assets`, waiting on a
stdin pipe whose writer is gone. It will not exit on its own. Per the rule above
it was reported, not killed, so this tick took the audit-only path and lost no
work — that is now the third tick this class of block has cost. The open
question for the founder: may a tick reap a `flutter_tester` that is older than
30 minutes, `ppid=1`, 0 % CPU and pointed at this repo's own
`build/unit_test_assets`? If yes, unblocking is `kill 226342`, one command,
today.

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

- [x] **Chat: timestamps, day separators, send state.** Image messages too.
      **Done** `5e73ec0`: one shared clock (`lib/src/data/chat_time.dart`, local
      time from the D1 UTC stamp, Arabic اليوم/أمس/weekday labels, one divider per
      day and never on a null stamp), `Message.sendState`, spinner/tick/red
      «لم تُرسل — أعد المحاولة» under every bubble (image bubbles included) with
      per-message and per-composer retry, inbox rows on the same clock. 9 tests
      in `test/chat_timeline_test.dart`, shot `/tmp/shots/chat_delivery.png`
      (danger ink counted under the refused bubble). 378 total. Found by pixel
      scan: the retry line was centred mid-thread because a Container with
      `alignment:` expands to its widest constraint — fixed.
- [x] **Chat image round-trip, live.** Upload a real photo to R2 through the app
      and fetch the stored object back from the API to prove the URL the bubble
      renders is the one the server kept.
      **DONE `38e5fb4`.** `test/live_chat_image_e2e_test.dart` drives
      `Repository.sendImage` — the app's own path, multipart `POST /api/upload`
      into R2 and then `POST /api/messages/:id` — with a 64x64 PNG built byte by
      byte inside the file (signature, IHDR, IDAT, IEND, no fixture, readable by
      `file(1)`), between two accounts created through the real sign-up
      endpoint. Then it asks the API, not the app, what it kept:
      `GET /api/messages/:id` returns exactly one image row carrying the same
      `image_url` the upload produced; a plain `HttpClient` (no app code, no
      auth, the way another phone or a browser reaches it) downloads that URL
      and gets `200`, `image/png`, 7,831 bytes, byte-for-byte equal to the local
      file; and a real `ChatScreen` mounted on that thread builds a
      `NetworkImage` whose URL is exactly the stored one.
      **The item paid for itself — it found a real bug, fixed in the same
      commit.** `ApiClient.uploadPhoto` sent every photo as
      `application/octet-stream` (`MultipartFile.fromPath`'s default), and the
      Worker stores the declared type on the R2 object, so `GET /api/images/...`
      answered `application/octet-stream` for a PNG: the first live run failed
      on exactly that assertion (`Expected: 'image/png' Actual:
      'application/octet-stream'`) while the bytes were already identical. A
      browser given that URL downloads the picture instead of showing it, and
      nothing downstream can tell a photo from a document. `photoMediaType()`
      now reads the type off the extension (jpg/jpeg/png/webp/gif/heic, unknown
      stays octet-stream rather than a guess) and, because all four upload paths
      share that one call, chat images, portfolio shots, the avatar and the
      verification documents all gain the right label. Re-ran live: `GET 200
      image/png 7831 bytes digest=a1c1aa9e`, the same digest that went up.
      `test/upload_content_type_test.dart` pins the fix offline — a loopback
      `HttpServer` receives the real multipart body for a PNG and an upper-case
      `IMG_2024.JPG`, plus the extension map.
      Gate: `flutter analyze` — No issues found!; `flutter test` **383 passed**
      (378 before).
      *Follow-up, not this repo:* objects already in R2 keep the wrong type, and
      the Worker's `file.type || "image/jpeg"` fallback can never fire because
      the client always declares one — hand BACKEND-API an extension-based
      fallback for `application/octet-stream`. *Live-only by design:* each run
      creates two real accounts and a few KB in R2.
- [x] **Notifications screen + unread badge** driven by the existing API, with
      Arabic copy per event type (new quote, quote accepted, new message,
      project completed). **Done** `001b178`, live API `45920a3e`: the centre
      lists newest-first with unread rows marked, a row opens the project it is
      about, and «تعليم الكل كمقروء» clears the pip. `POST
      /api/notifications/read` added (the pip had no way to clear); the five
      live types are mapped and any unknown type falls back to «إشعار» rather
      than the raw key. 11 tests (295 total); live E2E 27/27, production
      scrubbed. Next: colour contrast re-verification.
- [x] **Reviews flow after completion.** DONE `4a67eaa` — the star picker now
      survives the live `{"ok": true}` ack (it parsed the response as a full
      `Review`, so the int cast threw a `_TypeError` past the screen's
      `on Exception`: the rating was stored and the user saw a failure), and a
      closed job the client owns shows «قيّم المقاول` so the form is reachable
      after the completing tap instead of only during it. The same commit fixed
      the publish path: `urgency` went out as `urgency.name`, which the
      `projects.urgency` CHECK rejects for «خلال أسبوع» and «خلال شهر» — the
      live API answered 500. `UrgencyLevel.wire` is now the only writer.
      `test/review_submit_test.dart`, `test/project_publish_urgency_test.dart`,
      `test/live_review_e2e_test.dart` (live: project → quote → accept →
      complete → rate, avg 4.0 / 1 review; re-rate → 2.0 / 1 review, an edit,
      not a second row). No fake or seeded reviews anywhere in the fixtures.
      Next: verification flow end-to-end.
- [x] **Contractor portfolio upload** from camera/gallery to R2, with progress,
      retry, and Arabic permission rationale strings. **DONE `f083d71`** —
      `lib/src/screens/worker/my_portfolio_screen.dart`; camera and gallery both
      offered, the busy state names what is happening, and a failed upload keeps
      the picture on screen with a retry instead of dropping it.
- [x] **Verification flow end-to-end.** Upload the auto-entrepreneur card, ID
      front and selfie, then show the real pending/approved/rejected state
      instead of a static form.
      *Partly done (`f083d71`, `eb9b1c4`): the upload side works, the doc-type
      alias is fixed so the contractor card no longer fails the insert, and there
      are optional certificate slots. What remains is the status the user sees
      **after** submitting — the API stores `verification_status` but the screen
      does not read it back.*
      **DONE `34f2b55`.** The read-back turned out to need *two* levels, and the
      second one was missing. `7ddeff2` had already wired the first
      (`verification_pending_docs`, so a filed dossier stops looking empty), but
      the reviewer approves documents **one row at a time** and
      `worker_profiles.verification_status` only flips to `verified` once every
      row is approved — so a contractor whose ID and selfie were accepted while
      his contractor card was refused sat in `pending` with a zero-length queue,
      and the screen answered him with the same blank upload form a man who had
      sent nothing sees. The API was already sending the two flags that
      describe it (`is_identity_verified` / `is_certificate_verified`);
      `WorkerProfile` parsed them away. Now `identityVerified` /
      `certificateVerified` are read (absent keys default false, so an older
      backend can never claim a part is verified) and `_PartsStatusCard` shows
      two rows — الهوية (بطاقة التعريف + سيلفي) and بطاقة المقاول والشهادات —
      each marked **موثّقة** or **بانتظار التحقق**, above whichever receipt or
      form applies. No inference in the copy: `بانتظار التحقق` stays true
      whether the row is queued or refused, so it can never contradict the
      receipt panel.
      *Verified:* `flutter analyze` → **No issues found!**; `flutter test` →
      **398 passed / 0 failed** (383 before; 6 new in
      `test/verification_review_test.dart`, which now pins the wire flags, the
      missing-flag fallback and all four screen states). Pixels checked, not
      asserted: `/tmp/shots/18_verification_partial.png` (shot added to
      `test/design_shots_test.dart`, whose `_fakeApi` can now serve a chosen
      profile) — the accepted half's pill fills `#E7F5EE` at x108-310 y348-422
      with its icon in `#1B7E50` at x1016-1065, while the other half's pill is
      `#F6F7F9` with `#6C707A` content at x108-407 y483-557. The live API
      confirmed the contract first: `GET /api/mobile/my/profile` on
      `allomokawil.colisify.com` returns both flags and
      `verification_pending_docs`.
      *Left open, and it is not app-side:* nothing in the product ever writes
      `worker_profiles.verification_status = 'rejected'` (checked across
      `workers/` and `app/` in finili — the admin reject route only marks the
      **document** row), so `_RejectedBanner` is currently unreachable and the
      reviewer's `admin_notes` never leaves the admin UI. The app cannot show
      *why* a document was refused until the mobile API exposes the document
      rows. Hand to BACKEND-API.
- [x] **Project edit + cancel** for the owner, with the same validation as create.
      **DONE `c4f32d6` (app) + `795b0c4` (API).** A client could post a project
      from the app and never touch it again — no fix for a typo, no way out of a
      job he no longer wants — while the web app could do both.
      *App:* the owner's action row under his own project's quotes holds
      «عدّل المشروع» and «إلغاء المشروع», gated on what the API accepts (edit
      only while `open`, cancel only while not finished/cancelled) so no button
      can lie; cancelling confirms first and names what happens to the pending
      bids. `ProjectNewScreen(initial:)` turns the publish form into the edit
      form — prefilled, «عدّل مشروعك», «احفظ التعديل», PATCH instead of POST —
      with the same validation, not a copy of it, and the project's existing
      photos as removable tiles above the picker.
      *API (`finili/workers/mobile.ts`):* `PATCH /mobile/projects/:id`
      (owner-only, refused once the project leaves `open`, create's validation
      field for field, `images` kept when the key is absent) and
      `POST /mobile/projects/:id/cancel` (`status='cancelled'`, pending quotes
      → `withdrawn`, chosen contractor notified — the web action's own three
      writes). `PATCH` added to the CORS allow-methods list.
      *Verified:* `flutter analyze` → **No issues found!**; `flutter test` →
      **406 passed / 0 failed** (398 before; 8 new in
      `test/project_edit_cancel_test.dart` pinning the wire calls, the prefill
      and all four lifecycle states); `npx tsc --noEmit -p
      tsconfig.cloudflare.json` → clean. Pixels, not reasoning:
      `/tmp/shots/19_project_owner_actions.png` shows the edit label in
      `#16213E` at x603-679 y1761-1798 and the cancel label in `#C33F39` at
      x487-566 y2337-2369 inside a 1176x2550 capture, and
      `/tmp/shots/20_project_edit.png` is the prefilled form.
      *Open, and it is a handoff:* the mobile API change is committed and
      pushed but **not deployed** — `npm run deploy` in `finili` is DEVOPS'
      lane, the worker serves the live web app too, and this loop never touches
      the deploy credentials. Until that lands, the two new buttons on a
      project an owner opens will 404. One command, then the item is live.
- [x] **Offline behaviour.** Cache wilaya/specialty lists so the app opens with
      content on a dead connection, and queue a chat message for retry instead
      of losing it.
      *Closed 13 Sep — the chat half shipped in `4a3f1cd`, the taxonomy half is
      verified and pinned below.*
      The chat half: `4a3f1cd`. A refused send used to exist only as a list in
      memory inside the open thread, so tapping back or an Android kill lost it
      silently. Now `lib/src/data/chat_outbox.dart` writes the message to
      `SharedPreferences` **before** the first attempt and forgets it only after
      the server confirms the row; the thread restores and auto-flushes the
      queue, shows a `لا يوجد اتصال — ستُرسل رسائلك المحفوظة عند عودة الشبكة`
      strip with the queued bubbles and keeps the composer instead of replacing
      the screen with an error page, and the banner counts them; the inbox marks
      the conversation that still owes one (`queuedCountLabel`: 1 / 2 / 3-10 /
      11+); signing out drops the queue. Evidence: `flutter analyze` clean,
      `flutter test` **420 passed** (407 before this tick), renders
      `/tmp/shots/chat_queued_offline.png` + `/tmp/shots/inbox_queued.png`
      (badge pill #FDF3E3 at x105-233 y317-372 with the cloud glyph in
      #9B6415 and the count in #16213E; queue banner #FDF3E3 y3283-3474; two
      danger-red retry lines). Also `430d807`: the tap-target audit's ten hand
      measurements had rotted after a week of edits — re-read and rebased, the
      audit exits 0 again (11 measured pass).
      **Taxonomy half, 13 Sep — closed (`daed50a`), and it needed no cache.** The
      lists were never fetched: the 58 wilayas and 16 trades are compiled into
      `lib/src/data/taxonomy.dart`, and the 1,541 communes are a 54 KB
      `assets/data/communes_dz.json` read through `rootBundle` — a grep of `lib/`
      for a wilaya/commune/taxonomy request returns nothing. So a cold start on a
      dead connection already showed every list, but nothing in the suite said
      so, and one wire-up to the network would have turned a bundled list into a
      spinner that never fills. `test/offline_taxonomy_test.dart` pins it: five
      widget tests drive `BrowseScreen` and `ProjectNewScreen` against a
      `MockClient` whose every request throws `SocketException` (the dart:io
      error for "network is unreachable"), and `_attempts` proves the fetch was
      really tried and really failed — the browse filter keeps all 58 wilayas and
      its sheet, the 8 trade chips are reachable by scrolling the row, the
      publish form still lists all 16 trades, the wilaya picker searches
      ('وهرا' → وهران) and selects, and the commune picker fills from the bundled
      asset (>=1500 communes parsed with no signal). The screens are pumped with
      the real Arabic locale and theme, so the RTL layout walked is the shipped
      one. Gate: `flutter analyze` clean, `flutter test` **420 passed / 3
      skipped**.

## Phase 4 — Engineering hardening

- [~] **Stop the loop gate from seeding production.** *(app-side half done; the purge is a handoff)* `flutter test` runs the
      three `test/live_*_e2e_test.dart` files on every tick, and each one
      registers a fresh customer + worker on the LIVE API and leaves them there.
      `GET /api/mobile/workers/search` (authenticated, 13 Sep) returns **40**
      contractors, ~30 of them junk from previous loops — «test», «TEST»,
      «Yest», «مقاول (اختبار الصور)» x10, «مقاول (اختبار التقييم)» x3 — and they
      are listed in the same feed a real client browses, sorted by rating, so
      they sit at the bottom of it right now. Nothing deletes them: there is no
      DELETE route in `workers/mobile.ts` and no cleanup script, so cleaning the
      pile needs a `wrangler d1 execute` against production. Two things to do,
      founder-gated on the second: tag the live files and keep them out of the
      default gate (`dart_test.yaml` + `@Tags(['live'])`, run on demand), and
      get a one-off admin-only purge for the accounts already in the table.
      *Half done, 13 Sep (`32ecf86`) — the gate no longer seeds production.* The
      three `test/live_*_e2e_test.dart` files now carry `@Tags(['live'])` (`Tags`
      comes from `flutter_test`, so no new dependency), `dart_test.yaml` skips
      that tag with the reason printed in the run, and the register file's stale
      run hint names the tagged command. Verified with the skip live on an
      explicit path: `flutter test test/live_register_e2e_test.dart` prints
      `Skip: live: registers real accounts on the production API — run with
      'flutter test --tags live --run-skipped'` and `All tests skipped` in 0s, so
      no request left the box; the full gate is **420 passed, 3 skipped** (the
      three live suites are skipped — their 5 cases no longer count as passes,
      the 5 new offline-taxonomy cases take their place, so the count holds at
      420), and `--tags live --run-skipped` still reaches the loader. On demand:
      `flutter test --tags live --run-skipped`.
      **Remaining half, and it is a handoff:** the ~30 junk contractors are still
      in the production table and still in the feed a client browses. Removing
      them needs a `DELETE` route in `finili/workers/mobile.ts` or a
      `wrangler d1 execute`, i.e. BACKEND-API/DEVOPS with the Cloudflare
      credentials — this loop does not hold them.
- [x] **Golden/screenshot tests** for the main screens so a design regression
      fails CI rather than being noticed by the founder. **DONE `9fad004`.**
      The `/tmp` shots prove a screen looked right to the tick that rendered it
      and nobody else ever sees them, so a regression still had to reach the
      founder before the suite noticed. Eight main screens — landing, sign-in,
      customer home, worker home, browse, chat thread, notifications, project
      detail — are now captured by `_golden` in `test/design_shots_test.dart`
      against committed baselines in `test/goldens/` (412 KB for the eight, the
      real Cairo and MaterialIcons faces, 392x850 logical, dpr 1.0, Arabic
      locale) and compared by every default `flutter test`.
      `_golden` fails **before** the capture if the build threw, so a broken
      layout can never be baselined as correct. `test/goldens/README.md` says
      how to re-baseline (`--update-goldens`), where a failed run leaves its
      masked diff, and why an engine upgrade is a regeneration rather than a
      deletion of the test.
      *Verified:* `flutter analyze` -> **No issues found!**; `flutter test` ->
      **421 passed / 3 skipped** (420/3 before, the +1 is the new case) and a
      second full run against the fresh baselines compares byte-identical, i.e.
      the golden capture is deterministic on this box, not a flake waiting to
      block the loop. The baselines are not blank: `pngscan.py
      test/goldens/04_customer_home.png --color E8A33D` finds the publish tile
      at logical x18-373 y260-347, the same geometry the hierarchy item
      recorded for the live build.
      *Left open, deliberately:* a Flutter upgrade will fail all eight at once
      (that is the contract, not a bug), and the fixtures the new test renders
      are still duplicated between `test/design_shots_test.dart` and the other
      golden call sites if this is ever split into its own file.
      *Flake found and fixed 13 Sep, `b789c23`.* The claim above — "not a
      flake waiting to block the loop" — was wrong, and the gate went red on
      its own: the next `flutter test` after `9fad004` printed
      **420 passed / 3 skipped / 1 failed**, `goldens/15_notifications.png`
      "Pixel test failed, 0.05%, 171px diff". Cause: the rows on that screen
      carry a *relative* time, `relativeTimeAr(createdAt)` measures it against
      `DateTime.now()`, and the baseline was captured at 12:19 — so the hour
      boundary rewrote «قبل 11 ساعة» into «قبل 12 ساعة» and moved 171 px inside
      the label column (diff bbox x230-281 y152-280; the other seven baselines
      were untouched). Correct for a user, fatal for a pixel gate.
      `NotificationsScreen` now takes `clock:` (the same kind of seam as its
      existing `repo:`), `test/design_shots_test.dart` hands every capture the
      fixed `_pinnedClock = DateTime.utc(2026, 9, 13, 3, 0)` — UTC so the
      baseline does not also inherit the box's timezone — and two new tests
      guard it: one asserts the rendered labels are the pinned ones
      («قبل ساعة» for 01:12Z against 03:00Z), the other reads this harness back
      and fails if any `NotificationsScreen(` call site stops passing a clock.
      `15_notifications.png` re-baselined; the diff old->new is 1235 px confined
      to x230-304, i.e. the time column only, no layout moved.
      Full gate after the fix: `flutter analyze` -> No issues found!,
      `flutter test` -> **423 passed / 3 skipped / 0 failed**.
      *Left open, deliberately:* `12_chat` has the same class of dependency one
      layer deeper — `chatClock` prints local `HH:mm` by design, so under
      `TZ=Pacific/Kiritimati` or `TZ=Pacific/Midway` that baseline diffs 125 px
      in two clock labels while `15_notifications` passes. Not a layout bug and
      not fixable by re-baselining: it needs an injectable formatter in the
      thread, or the suite always run in CET. Written up in
      `test/goldens/README.md` either way.
- [x] **Every API call wrapped** so failure surfaces as an Arabic retryable
      state; assert no unhandled exception path remains.
      *Audited 13 Sep 12:37, read-only (no build this tick) — the defect is real
      and it is two layers deep.*
      **Layer 1 — the network layer can raise an `Error`, not an `Exception`.**
      `ApiClient._decode` (`lib/src/core/network/api_client.dart:139`) returns
      `_tryJson(res.body)`, and `_tryJson` (`:150`) swallows the `FormatException`
      and hands back the **raw string** for any 2xx body that is not JSON — a
      Cloudflare interstitial, a captive-portal page, an Algerian ISP proxy
      notice. Every repository method then casts that value unguarded:
      `lib/src/data/repository.dart:20` `as List`, `:46` and `:85`
      `as Map<String, dynamic>`, `:190`, `:198`, `:388` … 29 such casts in the
      file, each raising **`TypeError`**, which implements `Error`, not
      `Exception`.
      **Layer 2 — nine catch sites cannot see it.** `on Exception catch (e)` does
      not match `TypeError`. The nine: `auth_screen.dart:123` (login),
      `auth_screen.dart:169` (register), `review_screen.dart:59`,
      `verification_screen.dart:107`, `my_portfolio_screen.dart:155`,
      `project_detail_screen.dart:77`, `:126`, `:410`,
      `project_new_screen.dart:161`. Their `finally` blocks still clear the
      spinner, so the failure is not a permanent hang — it is **silence**: the
      request dies, `_error` stays null, and the user taps إنشاء الحساب and
      watches nothing happen, with no sentence telling him why. The same
      `TypeError` escapes from the unguarded model casts
      (`models/chat.dart:37-39`, `models/notification.dart:26-28`,
      `models/user.dart:26-29`, `models/quote_review.dart:30-44`,
      `models/project.dart:98-101`, `models/worker.dart:85-87`) whenever a
      fetched row carries a null or a string where an int/String is expected.
      *Already correct — do not re-do it:* `errorCopy`
      (`core/l10n/error_copy.dart:54`) takes `Object?` and always lands on
      Arabic, and all 18 `FutureBuilder` read paths (`hasError` → `EmptyView`
      with إعادة المحاولة) handle an `Error` correctly because `snap.hasError`
      is type-blind. The gap is the **action/write paths plus the network
      layer**, nothing else.
      *Planned edit for the next build-capable tick (mechanical, one commit):*
      1. `_decode`: a non-empty 2xx body that did not parse as JSON becomes
         `ApiException(S.errUnexpected, statusCode: …, cause: …)` instead of
         leaking the raw string upward.
      2. The 29 `as …` casts in `repository.dart` go through a shared
         `_asList`/`_asMap` pair that throws the same Arabic `ApiException` when
         the shape is wrong, so a drifted row is a sentence, not a `TypeError`.
      3. The nine `on Exception catch (e)` become `catch (e)` — `errorCopy`
         already accepts `Object?`, so nothing else moves.
      4. Regression tests: a stub `http.Client` answering 200 with `text/html`,
         and one answering 200 with a row missing `id`; both must surface an
         `ApiException` carrying Arabic copy, and the existing widget gate must
         still show the auth button re-enabling with a sentence on screen.
      *Why it did not ship this tick:* the build-safety gate. A `flutter_tester`
      orphan (pid 128251, ppid 1 = `systemd --user`, started 11:45:15, 52 min
      elapsed, 0.1 % CPU, 135 MB RSS) is holding
      `/home/renia/allomokawil/build/unit_test_assets`; `flutter test` over the
      top of it is exactly the 37-minute stall recorded earlier in this file. Per
      the protocol the orphan is **reported, not killed**, so this tick took the
      audit-only path and touched no Dart. It needs a human `kill 128251` (or the
      next tick, if it has exited by then) before item 3 can be implemented.
      **DONE `7f46d08`.** The orphan was gone by 15:04 and no other writer held
      the tree, so the four-step plan above shipped in one commit.
      1. `_decode` now throws `ApiException(S.errUnexpected, statusCode: …,
      cause: <first 200 chars of the page>)` for any non-empty 2xx body that did
      not parse as JSON; an empty 2xx stays `null`, so the ack endpoints are
      untouched.
      2. All 31 shape casts in `repository.dart` go through `_asList` / `_asMap`
      / `_asInt` / `_row` / `_rows`. `_row` also wraps the model call, so a
      drifted column (`id: null`, `user_wilaya: 16`) is a sentence, not a
      `TypeError`. `portfolioImages` still accepts the bare-URL-per-photo shape
      the API answers with (the mock in `home_hierarchy_test.dart` pins it) and
      drops anything else instead of raising.
      3. The nine `on Exception catch (e)` are `catch (e)` — `errorCopy` takes
      `Object?`, so a stray `Error` now lands on the same Arabic sentence.
      4. `auth_state` reads `{token, user}` through `_session()`: a 200 ack or a
      user row missing a column throws Arabic and leaves no half-session behind.
      *Verified:* `flutter analyze` -> **No issues found!** (a redundant `const`
      the previous subscription commit had added at
      `subscription_screen.dart:569` was dropped — that was the only issue);
      `flutter test` -> **447 passed / 3 skipped / 0 failed** (423/3 before; the
      new `test/api_shape_guard_test.dart` holds 14 cases). The widget case
      drives the real sign-in form against an HTML 200 and asserts the Arabic
      sentence is on screen and `PrimaryButton.onPressed` is non-null again —
      the button that used to do nothing now explains itself. No layout changed,
      so there is no screenshot for this item: the evidence is the widget tree,
      not pixels.
      *Also caught by the gate, worth knowing:* the first version of the guards
      dropped the bare-string portfolio rows and turned the contractor home's
      «3 صور» tile into «0 صور»; `home_hierarchy_test.dart` failed and the fix
      went in before the commit. That is why the whole suite runs every tick.
      *Left open, deliberately, and named so nobody re-audits it:* the only raw
      casts left in `lib/` are `data/communes.dart:56-64`, which parses the
      **bundled** `assets/data/communes_dz.json` (not an API call — a malformed
      asset is a build-time problem, and its `then` has no `onError`), and the
      model internals (`models/plan.dart`, `models/user.dart`, …), which are now
      only ever reached through `_row` / `_rows` / `_session`.
- [x] **Semantics labels** on interactive elements for TalkBack/VoiceOver.
      *Audited 13 Sep 15:52, read-only — no build this tick: a leaked
      `flutter_tester` (pid 226342) held `build/unit_test_assets`; see the
      protocol note.* Nothing was implemented, so the checkbox stays open; the
      next build-capable tick has the whole job below.
       *Tick 17:05, 13 Sep — implemented, runtime gate deferred.* Shipped
       `987e2a4` (pushed to `main`). New `lib/src/widgets/a11y.dart` holds the two
       shapes the house was writing by hand: `A11y.tap` (icon-only control, label
       required, label and tap action forced onto one node) and `A11y.button`
       (control that prints its own name -> role + `selected` only, so nothing is
       read twice), plus `A11y.rating`/`A11y.reviews` for the star row and the
       Arabic count forms (مراجعة واحدة / مراجعتان / 3 مراجعات / 12 مراجعة). All
       nine findings below are wired, and so are the shared widgets they run
       through: `SelectableTile`, `RatingStars`, the category strip tiles, both
       card avatars and the brand marks (decorative-only now), and every content
       image (project/portfolio photos, the picked verification card, chat
       photos). New `test/a11y_semantics_test.dart` reads the semantics tree the
       way TalkBack does (label + role + tap action + selected state) instead of
       grepping the source, over `ReviewScreen` and the shared widgets, on
       `MockClient` only.
       *Evidence:* `flutter analyze` over the 19 touched paths -> **No issues
       found!** (repo-wide analyze is not usable as evidence this tick: a
       concurrent Hermes session was mid-way through its own auth change).
       *Why the box stays open:* (a) the suite has never executed the new test
       file — another session held the box with a Gradle build (java pid 275872)
       for the whole tick and two concurrent builds on 7.8 GB with no swap is a
       coin flip; (b) part (i) below, the eight-golden-screen sweep, is still not
       written. Next tick: box free -> `flutter test` (full) -> add the sweep to
       `_golden` in `test/design_shots_test.dart` -> tick this box.
      *Already right (verified by reading the build methods):* the bottom nav
      sets `Semantics(button: true, label:, selected:)` on both the raised
      centre action and every destination (`app_tab_bar.dart:101`, `:161`), the
      bell does the same (`notifications_bell.dart:68`), the auth role switch
      sets `button` + `selected` (`auth_screen.dart:446`), all 11 `IconButton`s
      carry a `tooltip` (Flutter turns a tooltip into a label), the two chat
      composer actions are wrapped in `Tooltip`, the decorative hero
      `CustomPaint` emits no semantics node at all, and the publish form's
      first photo-remove is labelled `حذف الصورة`
      (`project_new_screen.dart:457`).
      *What TalkBack cannot reach today — nine findings, `lib/` read, not
      guessed:*
      1. `screens/review/review_screen.dart:207-224` — the five stars are bare
         `InkWell`s around an `Icon` (no `Text` inside), i.e. five unlabelled
         tappables: **the rating form is unusable with a screen reader.** Needs
         one button per star, label «n من ٥», `selected: n <= value`.
      2. `screens/project/project_new_screen.dart:960-978` — the *second*
         remove-photo control (red disc on the photo strip) is a raw
         `GestureDetector` with no label, while the identical action at `:457`
         is labelled. Same action, two behaviours.
      3. `screens/chat/chat_screen.dart:823-832` — an image bubble: a tappable
         that opens the photo, with no label and no `semanticLabel` on the
         `Image`.
      4. `widgets/ui.dart:453 RatingStars` — the rating on every card is five
         raw `Icon`s plus a bare `4.5` + `(3)`: TalkBack reads a number with no
         meaning and five junk nodes. Should be one node
         («التقييم ٤.٥ من ٥، ٣ مراجعات») with the icons excluded.
      5. `widgets/category_grid.dart:66` — the trade tile announces its text but
         never `button: true` / `selected:` (unlike `app_tab_bar`).
      6. `screens/worker/my_portfolio_screen.dart:312` — the add tile (label
         «أضف») goes silent while an upload is in flight: `onTap` becomes null
         and the child is a bare spinner, so the tile the user just tapped has
         no name and no button role while it works.
      7. `screens/worker/subscription_screen.dart:384` and `:737` — plan picker
         and payment-method picker: text without `button: true` / `selected:`.
      8. `screens/project/projects_screen.dart:280`,
         `screens/browse/browse_screen.dart:317`,
         `screens/project/project_new_screen.dart:858` — the filter pills, same
         shape as 7.
      9. `semanticLabel` occurs **zero** times in `lib/`: every
         `Image.network` / `Image.file` in the app is announced as "image" with
         no content.
      *Plan — one commit, next build-capable tick:*
      a. New `lib/src/widgets/a11y.dart`: `A11y.tap({required String label,
         bool? selected, bool enabled = true, required Widget child})` →
         `Semantics(button: true, …, child:)`, plus `A11y.rating(double,
         {int? count})` (the Arabic rating sentence) and the image-label helper.
         One helper, so no screen re-invents it — the house already uses this
         `Semantics(button: true, …)` shape in four places.
      b. Apply at the nine sites and set `semanticLabel` on photos with a real
         Arabic description, never a bare «صورة».
      c. New `test/semantics_coverage_test.dart`: `tester.ensureSemantics()` +
         `tester.semantics` (Flutter 3.47.2, so the modern API is there —
         `grep -rn "ensureSemantics\|SemanticsTester" test/` is currently **0
         hits**, the suite has never asserted a single semantics node). Assert
         (i) every node carrying a tap action on the eight golden-covered
         screens has a non-empty label, walked from the semantics tree rather
         than a hand list, (ii) the star picker exposes five labelled buttons
         with the right `selected` flags, (iii) `RatingStars` exposes exactly
         one node.
      *Tick 17:38, 13 Sep — read-only again (no build possible), and it found a **tenth
      control the nine-item audit missed, on a golden screen.***
      Build-safety gate blocked every build this tick: a release APK build is live
      (`/home/renia/tools/build_118.sh` -> `flutter build apk --release --split-per-abi`,
      pid 275691, 41 min elapsed, `aapt2` working at 0.6 % CPU), the box sits at **664 MB
      free with no swap** and load 7.8, so no `flutter test` was started — the loser of two
      concurrent builds here is somebody else's release.
      What this tick *did* establish by reading, not by asserting:
      * All nine findings are genuinely wired in `987e2a4`: **13** `A11y.*` call sites
        (`ui.dart` x2, `category_grid.dart`, `review_screen.dart` x2, `chat_screen.dart`,
        `my_portfolio_screen.dart`, `subscription_screen.dart` x2, `project_new_screen.dart`
        x2, `projects_screen.dart`, `browse_screen.dart`) and **10** `semanticLabel`s (was
        0). Both photo-removers are labelled (`project_new_screen.dart:457` and `:968`), so
        finding 2 is closed, not half-closed.
      * **The sweep as planned would go red on `01_signin`.** `auth_screen.dart:591`
        (`_RememberRow`, rendered only in sign-in mode) builds
        `Checkbox(value:, onChanged:, activeColor:, checkColor:, side:, shape:)` with **no
        `semanticLabel`**. `checkbox.dart:615` is literally
        `Semantics(label: widget.semanticLabel, checked: ...)`, and Flutter's own
        `test/material/checkbox_test.dart:183-196` pins that this node carries
        `hasCheckedState: true` **and** `hasTapAction: true`. So it is a tappable, unnamed
        toggle: the exact defect class this item exists to kill. The visible «تذكرني» is a
        *sibling* `Text` node (`S.rememberMe`, `strings.dart:52`), never read with it.
        *Fix for the next build-capable tick — one node, not two:* `MergeSemantics` around
        the row's existing `InkWell`, `semanticLabel: 'تذكرني'` on the `Checkbox`, and the
        visible `Text` wrapped in `ExcludeSemantics` (otherwise the sentence lands twice,
        which is worse than once).
      * Same class, off-golden, one line when someone is in that file: the service-radius
        `Slider` (`worker/profile_edit_screen.dart:250`) is named with its *value*
        («12 كم», from `slider.dart:1960-1962`) instead of its purpose — it passes the
        sweep, so it is polish, not a defect.
      * Next tick, in this order: (1) the checkbox fix above, (2) full `flutter analyze` +
        `flutter test`, (3) add the eight-screen sweep to `_golden` in
        `test/design_shots_test.dart`, (4) tick this box with the hash. Nothing else on the
        item is open.
      * Orphan watch: `flutter_tester` pid 226342, ppid 1033 = `systemd --user`, **2 h 26 m**
        old, 0.0 % CPU, still holding `build/unit_test_assets`. Reported, not killed, per
        the rule — but it is the second orphan and the **fourth tick** this class has cost.
        Founder question unchanged: may a tick reap a `flutter_tester` older than 30 min
        with `ppid` = systemd and 0 % CPU that is pointed at this repo's own
        `unit_test_assets`? One `kill 226342` answers it.
      *Tick 18:19, 13 Sep — done, gate green.* `3de834b`, pushed. The eight-golden-screen sweep
      lives in `test/design_shots_test.dart` ("no main screen has a tappable node with no name"):
      for each of the eight main screens it walks
      `tester.semantics.simulatedAccessibilityTraversal()` and fails on any node that has a tap
      action and is silent in all three channels a reader uses — `label`, `hint`, `tooltip`,
      read from the node's **data** (a merged node keeps its own label empty and carries the
      child's in its data, which is what the platform is handed; reading `node.label` is what made
      the first version report nine false positives).
       *Two more nameless controls than the hand audit found.* The sign-in remember-me row was the
      tenth: its `InkWell` node held the tap action, the `Checkbox` node was checked and nameless,
      and the visible «تذكرني» was a *sibling* text node. Fixed with one `MergeSemantics` naming
      the toggle, visible text `ExcludeSemantics`'d so the sentence is not read twice, and pinned
      by its own test — named once, tappable, and it announces its checked state. The eleventh is
      **filed, see below**.
       *What else had to be fixed to reach green:* `A11y.star` spelled its fixed «من 5» in ASCII
      while `A11y.rating` spelled «من ٥», so the star row contradicted its own score line (fixed,
      Arabic-Indic denominator); the eight `SemanticsHandle`s in `a11y_semantics_test.dart` were
      disposed from `addTearDown`, which runs *after* the framework's end-of-body handle check
      (`widget_tester.dart:453`), so that file had never once passed — all eight disposed inline
      now; `lib/src/app.dart:125` typed a raw `13.5` where the ladder's step is `fsMeta` (inherited
      red from `4c29d45`, one token, no pixel moves).
       *Evidence (real output):* `flutter analyze` -> **No issues found!**; `flutter test` ->
      **463 passed, 3 skipped, 0 failed** (was 451 passed / 11 failed at 17:0x). The goldens in the
      same file still match, so this item moved no pixel — the whole change is tree-level.
       *Filed, design-gated — the sign-in password box (`node 27`) has no accessible name, and no
      Dart API can give it one:* a Material text field takes its name only from its own
      decoration's hint Text (`input_decorator.dart` merges the hint up into the field node), and a
      hint is **painted**. Measured, not assumed: a `Semantics` label on the field's prefix icon
      does not merge — it adds a second, duplicate label node (the sweep's own dump showed it) —
      and a transparent hint names the box but puts a second `Text` in the tree, which broke
      `tap_target_test.dart`'s `find.text('الاسم الكامل')`. So the fix is one line in `authInput`
      and it is a **visual** decision (placeholder inside the field) that UI-UX owns; the sweep
      therefore fails on any nameless *control* and **pins** the one nameless *field* by node id
      and rect, so a new nameless box breaks the test instead of hiding.
       *Orphan watch (fifth tick, unchanged):* `flutter_tester` pid 226342, ppid 1033 =
      `systemd --user`, 0.0 % CPU, still holding `build/unit_test_assets`. Reported, not killed.
      Your one-word answer would end this recurring cost: may a tick `kill` a `flutter_tester` older
      than 30 min, parented by systemd, at 0 % CPU, pointed at this repo's own assets?
       *Next:* the item below (**Cold-start audit**) needs a *release* build and a real device, both
      founder-gated, so the first thing a tick can take unasked is Phase 4's **crash-free
      baseline**.
- [~] **Cold-start audit.** *(app-side half shipped `c90db36`; the device number
      is founder-gated — see the note below)* Measure and shorten
      time-to-first-meaningful-paint on the release build; report a real number
      from a real device/emulator.
      *Tick 20:45, 13 Sep — the shortening shipped and the launch now measures
      itself.* What was wrong was structural, not mysterious: `main()` awaited
      **two** storage reads before `runApp` — the stored session and the previous
      run's crash log — while `_RootGate` was already drawing `AppBootSkeleton`
      for exactly the unrestored state. So a cold start paid a platform-channel
      round trip to the preferences file plus a JSON decode of the session and of
      up to twenty crash lines before it was allowed to paint a frame it had a
      designed screen for. Now `runApp` runs first and `Boot.warmup` starts both
      reads behind it, together instead of one after the other; the gate swaps
      itself when the session lands, which is what the skeleton was built for.
      Each read keeps its own guard, since nothing awaits them any more.
      *Two supporting changes the reorder needed:* `CrashLog.loadLines(...,
      earlier: true)` puts a previous run's lines in front of anything this run
      has already caught (appending would leave a this-run record ahead of a
      last-run one, and the restore now lands after the frame, so a startup crash
      can already be in the list); `CrashReporter.restore()` passes it.
      *The number, and where it comes from.* New
      `lib/src/core/diagnostics/boot_trace.dart` is an engine-free phase
      recorder (injected clock, so the unit tests are exact) and `main()` prints
      one line per launch. Read back from the **release web bundle** over CDP on
      this box, 412x915@2, cold cache, 127.0.0.1:8128:
      `boot: 398ms to first frame | binding 16 · chrome 0 · hooks 0 · runApp 3 ·
      crash-log 12 · session 0` — i.e. `main()` now hands control to the engine
      **3 ms** after `runApp`, and the 12 ms of storage work that used to sit
      inside that number finishes after frame one. First-contentful-paint 5192 ms
      in the same run is the web bundle's own 3.6 MB `main.dart.js`, not the
      launch path, and it is not the number this item is about.
      *What is still owed, and why this box cannot produce it:* the item asks for
      **time-to-first-meaningful-paint on a release build, from a real device or
      emulator**. A release APK build and a real device are both founder-gated in
      this loop, so no tick can produce that number. The measurement is now one
      install away: the next release prints the line into logcat, so
      `adb logcat | grep 'boot:'` answers it in one command on a real phone.
      *Evidence for the shipped half (real output):* `flutter analyze` ->
      **No issues found!** (84.9 s); `flutter test` -> **482 passed / 3 skipped /
      0 failed** (was 472/3/0; `test/boot_trace_test.dart` 6 cases, and
      `test/boot_warmup_test.dart` 4 — session restored off-path, previous-run
      ordering with a startup crash already captured, a throwing restore still
      caught as `startup`, and the gate painting the skeleton before storage
      answers). The bundle was exercised for real, not reasoned about: the page
      was driven through headless Chrome, `PAGE_ERRORS=[]`, 2 Flutter host
      elements, and `/tmp/shots/boot_web.png` (557 sampled colours) shows the
      landing page rendered.
      *Caught by the gate, worth knowing:* the first version of the trace test
      asserted `msFor('session') == 96` against a frozen clock, which failed — the
      two reads are concurrent, so whichever marks first takes the whole delta.
      The assertion is now "both marks are present and the pair accounts for all
      the elapsed time", which is the real contract.
      *A second writer was live this tick:* `pgrep -c java` was 0 when this tick
      took its first measurement, and a Gradle build in
      `/home/renia/grokdent-fl/android/renia-calls` appeared mid-tick while the web
      bundle was compiling (163 MB free, no swap, both builds survived). Nothing
      was killed to free memory. Worth remembering: the build-safety check is a
      snapshot, not a lease.
      *Next, unasked:* with this item's Dart half shipped there is **no unchecked
      item left in any phase** — the only other open boxes are `[~]` handoffs that
      need BACKEND-API/DEVOPS credentials or the founder (`wilayas` D1 order; the
      ~30 junk production contractors). A future tick should therefore say so
      rather than invent work, and take a read-only audit or a handoff write-up.
      Also left running deliberately: `python3 -m http.server` on 127.0.0.1:8128
      serving `build/web`, so the next tick's render check does not rebuild.
- [x] **Crash-free baseline.** Wire a lightweight error reporter and confirm it
      receives a deliberately thrown test error end-to-end.
       *Implemented and pushed as `98a6ed9` (this tick) — one gate short of done.*
      `lib/src/core/diagnostics/crash_log.dart` is plain Dart with no engine in it: a bounded
      newest-last list of records, every stored field length-capped, a corrupt line dropped one
      at a time, and nothing in the file able to throw. `crash_reporter.dart` chains
      `FlutterError.onError` and `PlatformDispatcher.onError`, keeps the handler that was already
      installed (the debug red screen survives) and returns what it returned, so the engine's own
      reporting is untouched; writes go out serialised behind one future and a storage failure is
      swallowed instead of becoming a second crash. `main.dart` installs and restores the reporter
      before the first frame, and the existing boot guard now captures the startup failure it
      already logged.
       *Evidence that ran:* `flutter analyze` -> **No issues found!** (whole package, 125.4 s) and
      `dart run tool/crash_log_check.dart` -> **9/9 PASS, exit 0** (cap, round-trip, four junk
      lines, a 5000-char message clamped, schema cases). That script exists because the core is
      engine-free — it is the only reason this tick could ship anything at all while the orphan
      below held `build/unit_test_assets`.
       *Ticked — the owed gate ran green this tick.* Before starting it the box was checked
      for a competing build, per the hard rule: `pgrep -c java` -> **0**, no `dart` or `gradle`
      process anywhere, load 0.35, 3.8 GB free. The only `pgrep -fc "[f]lutter"` match is the idle
      orphan below — `/proc/226342/stat` reads utime 94 + stime 13 ticks, about **1.1 s of CPU
      across its entire 4h23m life**, i.e. not a build.
       *Evidence (real output, every command exit 0):* `flutter test test/crash_reporter_test.dart`
      -> **9/9 "All tests passed!"** (the file grew to nine: the real `PrefsCrashStore` round-trip
      is in there), and the whole-package gate `flutter test` -> **472 passed, 3 skipped, 0 failed**
      (was 463 / 3 / 0 — the delta is exactly these nine), `flutter analyze` -> **No issues
      found!** (70.5 s). The deliberately thrown `StateError('boom-42')` is in the passing set, so
      a real error is now proven end-to-end: it reaches the store line, the in-memory log, and the
      preferences store behind a mock. Nothing was red, so the revert rule never fired.
       *Orphan watch — closed, it is harmless (seventh tick).* `flutter_tester` pid 226342 (ppid
      1033 `systemd --user`, 0.0 % CPU, 78 MB) did **not** disturb the run: the suite went green
      with it alive. It holds open descriptors, not the directory — a test run deletes and
      re-creates `build/unit_test_assets` around it without an error. The earlier guess that it
      "held" those assets was wrong, so there is nothing to kill and no founder answer needed. It
      costs 78 MB of 7.8 GB and no CPU; left alone per the hard rule, watch retired.
       *Next:* the only other open item is **Cold-start audit** above, and both halves of it (a
      *release* build, a real device) are founder-gated — so a future tick has nothing unasked to
      take in Phase 4 and should say so rather than fake progress.

---

## Phase 5 — a write lands once, or the user is told it did not

Opened 13 Sep 21:52 because every phase above is ticked or handed off. The first
item came out of a read-only audit of the network layer, not from a wish list:
it is a correctness gap that duplicates a user's data.

- [x] **A timed-out write was re-sent to the other host.** `ApiClient` carries
      two base URLs (`allomokawil.colisify.com`, then
      `finili.medsaidkichene.workers.dev`) and `_withFailover` moved **every**
      verb to the second host on any transport failure — DNS, TLS, connection
      reset, and a response that never arrived inside the 20 s timeout. Both
      hosts answer from the **same Worker**, so the second attempt is not a
      retry of a request that failed, it is a second copy of a request that may
      already have succeeded: a 20 s stall on the primary during
      `POST /api/mobile/projects` created the project twice, and its owner saw
      two identical cards in «مشاريعي». Same exposure on every POST in
      `repository.dart` — quotes, chat messages, reviews, the verification pile,
      subscriptions. Nothing pinned the old behaviour; the three tests in
      `api_client_failover_test.dart` only covered GET.
      **DONE `5a7052a`.** Failover is now method-aware. `_neverReached` decides
      whether the failure *proves* the request never left the phone — a TLS
      handshake that never completed, or a transport-level failure (no name
      resolved, connection refused, no route) — and only then does a POST try
      the second host. Anything ambiguous (timeout, reset mid-flight) throws the
      new `S.errWriteUnconfirmed` — «انقطع الاتصال قبل تأكيد وصول طلبك. تحقّق من
      القائمة قبل إعادة المحاولة.» — so the user learns the outcome is unknown
      instead of being handed a duplicate. GET/PATCH/DELETE keep the old
      behaviour (PATCH writes a fixed field set to one row; DELETE is
      HTTP-idempotent). The host timeout is an injectable parameter now
      (`defaultTimeout` keeps the shipped 20 s) so the rule is testable without
      a test that waits twenty real seconds.
      *Evidence (real output):* `flutter analyze` -> **No issues found!** (42.7 s);
      `flutter test` -> **487 passed / 3 skipped / 0 failed** (was 482/3/0; the +5
      are the new cases — POST timeout reaches **one** host only, POST whose host
      does not resolve still fails over, refused connection still fails over, GET
      timeout still fails over, and the app's own `createProject` posts exactly
      once against a stalling host). The new sentence is inside the
      `error_copy_test.dart` invariant list, so it cannot lose its instruction or
      grow a Latin letter. No pixels moved: this is the transport layer, no
      screenshot applies.
      *Rejected alternative:* marking the POST with an `Idempotency-Key` and
      letting the backend dedupe — correct, but it needs the Worker to store and
      check the key, i.e. BACKEND-API, and the duplication was live today.
      *(Superseded by `c428929` on the app side: the five write screens now
      re-read and tell the user the truth. The Worker-side dedupe is still the
      only fix that makes a retry safe rather than merely honest.)*
- [x] **The screen must show the truth after an unconfirmed write, not just
      the sentence.** The new copy tells the user to check the list before
      retrying, but a screen that keeps its stale list is asking him to check
      something that is not on screen. The write screens (publish a project, bid,
      chat send, review, verification) should refetch their list the moment
      `errWriteUnconfirmed` is caught, so the user can see for himself whether
      the row landed. Small: one reload per write screen behind a typed check on
      the failure message, plus a test that a stalled publish refetches and shows
      the row when the API does have it.
- [x] **The outbox re-sent a message the server may already have.**
      `5a7052a` stopped the network layer re-sending a POST on a timeout and
      `c428929` made the write screens re-read. Both guarded the moment the
      failure happens; neither guarded the next one — the outbox. A chat
      message is written to the device *before* its first attempt, and on the
      next thread open the screen restored every queued record and **flushed**
      it. That flush is the re-send the network layer refused, performed by the
      app itself with no user action: type an address on a bad connection, the
      POST reaches the Worker and is stored, no answer comes back, close the app,
      reopen the thread — and the second copy is on its way. The contractor gets
      «العنوان: حسين داي» twice and the user did nothing wrong.
      The queue now records *why* a record is still there. `SendState.failed`
      is a fact (the server refused it) and re-sends as before;
      `SendState.unconfirmed` is not, and is persisted, skipped by the startup
      flush and by «send everything again», drawn with a neutral
      «لم يتأكّد وصولها — النتيجة غير معروفة» and **no** retry affordance (a
      retry line is the instruction that creates the duplicate), and kept in the
      banner behind a «تحقّق» button that *re-reads* instead of «إرسال», which
      would promise a re-send it must not make. A re-read that comes back empty
      clears the mark — the words are known absent, so a retry is real again.
      The mark is written *before* the re-read runs: if the phone dies during
      it, the next cold start must find a record that says do not send again.
      *Found in the same fix:* `_restoreQueued` appended the local bubble
      unconditionally, so a message the server had already stored appeared
      **twice** the moment the thread opened. An unconfirmed record the fresh
      read already accounts for now yields to the real row.
      *Evidence (real output):* `flutter analyze` -> **No issues found!**
      (8.2 s); `flutter test` -> **541 passed / 3 skipped / 0 failed** (was
      532/3; the +9 are the new cases, no existing test changed). The cold-start
      case is a true regression test: reverting the flush and the restore guard
      makes it fail with a second POST. Screenshot of the rendered thread
      (`/tmp/shots/chat_unconfirmed.png`) scanned for pixels: the danger red
      `#C33F39` of the retry line is **absent**, the muted `#6C707A` line is
      present under the bubble, the banner `#9B6415` at the bottom of the frame.
      **DONE `43e767f`** (remote `fbf6204`).
- [x] **The push helper that deleted 5 files from main, fixed at the source.**
      Found while auditing the previous cycle's own incident. `gh_push.py` is
      the *only* way to push from this box (`git push` has no credentials), and
      its path filter was a loaded gun: `local` was filled with ONLY the
      filtered paths, then every remote path absent from `local` was staged for
      deletion. A 5-file filter therefore staged the other **251 files** for
      deletion. That is exactly what commit `782b657` did to main; `fbf6204`
      put the files back.
      *Fixed in three parts, each one closing a real defect found by testing:*
        1. Deletions are computed from the **full** tracked set, always. A
           filter now narrows only what is uploaded and can never stage one.
        2. The file set comes from `git ls-files`, not a hand-rolled
           `.gitignore` matcher. The hand-rolled one was wrong twice: its
           `lstrip("./")` ate the leading dot of `.dart_tool`, and it read only
           the root `.gitignore`, missing the nested `android/.gitignore` and
           `ios/.gitignore` where Flutter keeps its generated-file exclusions
           — so it leaked `build/`, `.dart_tool/` and generated registrants
           into pushes.
        3. Deletions require `--allow-deletes`. Without it the script lists
           what it would remove and exits 3 instead of emptying a branch.
      *Evidence (real output, against a throwaway repo, main never touched):*
      a partial filter that changed 1 file reported **"Pushed 1 changed, 0
      deleted"** and left every other file on the remote — the old code would
      have deleted them. A genuine deletion without the flag refused with exit
      3 and named the file. The same deletion with `--allow-deletes` removed
      exactly that one file. An untracked `local.properties` was never uploaded.
      On this repo the walk set equals `git ls-files`: **256 files, both sides.**
      Also cleared a leaked `flutter_tester` from the previous cycle (orphan,
      PPID 1, 0% CPU) and re-synced the diverged local `main` to `origin/main`
      (trees byte-identical, so nothing lost, no force-push).
      *DONE `6945a75` (script fix; this doc commit follows).* Known gap, not fixed: a branch ref that does
      not exist yet returns 409/404, so the first push to a brand-new empty
      repo fails. Nothing in the loop does that. The credential has no
      `delete_repo` scope, so the throwaway test repo
      `cheminisifeddine/ghp-safety-test` (private, 2 files) needs deleting by
      hand.
      *The "known gap" above is now CLOSED — see the item immediately below.*
- [x] **Push helper: the first push to a repository or branch that does not
      exist yet.** The gap the previous cycle recorded and deliberately left.
      The ref read returned 404 (409 on an empty repo) and the script gave up,
      so the only way to push on this box could never open a new repository or
      branch. Four distinct defects, each found by running the case rather than
      by reasoning about it:
      1. **404/409 from the ref read is "create", not "stop".** `resolve_base()`
         now returns the base to build on *and* whether the ref itself exists.
         A new branch off main inherits main's tree, so the diff stays honest
         instead of reporting every file as new.
      2. **"Has a base" and "has a ref" are different facts.** My first attempt
         derived one from the other and every new branch died on
         `422 Reference does not exist` from the PATCH, *after* the blobs were
         already uploaded. Only a branch that existed when the push started is
         patched; anything else is created with POST.
      3. **The git-data API cannot seed an empty repository at all** — creating
         a blob answers `409 Git Repository is empty`, so the
         blob → tree → commit → ref chain cannot start. The orphan case now goes
         through the Contents API, which is the documented way in, and says how
         many files remain for a second run.
      4. **An empty commit cannot be built either** — GitHub answers
         `422 Invalid tree info` for a tree with no entries, with or without a
         base. So a new branch whose content already matches the parent is
         created AT the parent commit, which is what
         `git push origin main:BRANCH` does, and leaves no junk commit behind.
      *Also fixed while testing:* a path filter on a brand-new branch used to
      create a branch holding only the filtered files. The filter is now ignored
      for a new branch, with a printed NOTE, because a half-written branch that
      looks pushed is worse than a larger push.
      *Evidence (real output, against throwaway repos, allomokawil never
      touched):* a new branch off main was created and its commit's parent is
      **byte-identical to main's tip**; a first push to a completely empty repo
      seeded via the Contents API and the re-run pushed the remaining file;
      a new branch identical to its parent was created with no empty commit; a
      filtered push to an existing branch reported **"1 changed, 0 deleted"** and
      both files were still on the remote (the 782b657 bug stays fixed); a
      genuine deletion without `--allow-deletes` still refuses with **exit 3**
      and names the file, and with the flag removes exactly that one file; an
      untracked `local.properties` was never uploaded.
      **Then used on the real repo** — see the commit on `main` below.
- [ ] **[HANDOFF — BACKEND-API, needs Cloudflare credentials] Idempotent
      writes.** The app cannot make `POST /api/mobile/projects` safe to retry on
      its own. A `Idempotency-Key` request header, stored with the created row
      and checked before insert, would let the client fail over to the second host
      on a timeout without duplicating anything and without asking the user to
      guess.
      **App-side half: DONE and covered by tests** — audited this cycle rather
      than assumed. The client already refuses to re-send an unconfirmed write
      (`errWriteUnconfirmed`), and all five write paths re-read the server and
      tell the user which of three things is true — it landed, it is missing, or
      it is still unknown: `project_new_screen` (title match), `project_detail`
      (bid amount + worker id), `chat_screen` (content + sender, plus the
      permanent «لم يتأكّد وصولها» line and a «تحقّق» action that re-reads),
      `review_screen` (project + rating), `verification_screen` (pending or
      verified). `test/write_outcome_test.dart` and
      `test/write_unconfirmed_refetch_test.dart` cover the contract.
      **What is actually left is the server half only:** the header the Worker
      does not yet read. No Dart change can supply it, and the app is not
      missing anything until then. This item is not completed — it is
      correctly parked on BACKEND-API, which holds the Cloudflare credentials.

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
