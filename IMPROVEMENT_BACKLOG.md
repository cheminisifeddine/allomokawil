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
- [ ] **No dead-end empty states.** Every list (projects, quotes, chats,
      portfolio, reviews) shows an Arabic explanation **and** the action that
      creates the first item.
- [ ] **Arabic error copy audit.** Walk every `catch`/error path and confirm the
      user sees an Arabic sentence that says what to do next — never a raw
      exception, a status code, or an English word.

## Phase 2 — Elite visual pass

- [ ] **Skeleton loaders instead of spinners.** Cards that fade to their real
      content read as fast and native; a grey circle mid-screen reads as broken.
- [ ] **8pt spacing audit + one card recipe.** Every card uses the same radius,
      border, shadow and inner padding; no screen invents its own.
- [ ] **Typography scale from Cairo.** Define title/body/caption sizes once and
      remove every hardcoded `fontSize` at call sites.
- [ ] **Colour contrast re-verification.** After the pass, re-check every
      foreground/background pair at WCAG AA (4.5:1 body, 3:1 large) with
      pixel maths from real screenshots — the same method used previously.
- [ ] **Touch targets ≥ 56 px** on every interactive element, measured from
      screenshots, including icon buttons.
- [ ] **Press feedback + intentional motion.** Buttons visibly respond on press;
      screen transitions and list reveals use one consistent duration/curve
      instead of default jumps.
- [ ] **Onboarding for two roles.** One short, skippable Arabic explainer that
      makes "I need work done" vs "I do the work" unmissable at signup.
- [ ] **Home screen hierarchy.** The client home leads with one clear primary
      action; the contractor home leads with the next thing that earns them
      money, not with a stats row.

## Phase 3 — Functional completeness (parity with web v1)

- [ ] **Chat: timestamps, day separators, send state.** Image messages too —
      including a real R2 round-trip with an actual uploaded photo, verified by
      fetching the stored object back.
- [ ] **Notifications screen + unread badge** driven by the existing API, with
      Arabic copy per event type (new quote, quote accepted, new message,
      project completed).
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

(move ticks here with the commit hash when a phase closes)
