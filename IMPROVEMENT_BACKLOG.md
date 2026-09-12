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
- [~] **[CLAIMED — do not start] Wilaya + commune picker with Arabic search.** 58 wilayas by name, not
      by numeric code, with the commune list for the chosen wilaya. Must be
      searchable by typing the Arabic name or the code (`16` → الجزائر).
      *Done when:* a user can reach حسين داي without scrolling a list of 1541
      communes.
- [ ] **Phone entry that behaves like an Algerian expects.** A `+213` /
      `0X` prefix affordance, grouping shown as `0X XX XX XX XX`, live inline
      validation from the existing `isValidDzPhone` rules, and no rejection of
      a number pasted with spaces or dashes.
- [ ] **Numeric keypad for numeric fields.** Every amount, year, radius and
      day-count field opens a number keyboard, not a full text keyboard.
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
- [ ] **Contractor portfolio upload** from camera/gallery to R2, with progress,
      retry, and Arabic permission rationale strings.
- [ ] **Verification flow end-to-end.** Upload the auto-entrepreneur card, ID
      front and selfie, then show the real pending/approved/rejected state
      instead of a static form.
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
