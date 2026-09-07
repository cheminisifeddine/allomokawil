# Allo Mokawil — Product Blueprint (Houzz-inspired)

How Houzz structures a home-design marketplace, and how each pattern maps to
**Allo Mokawil** for the Algerian market. All implementation is original Flutter
code / our own backend — Houzz is used as a *product model*, not a codebase.

## The marketplace loop (Houzz)

1. Client posts a project (needs, budget, photos).
2. Pros discover & bid with quotes.
3. Client reviews quotes → accepts one.
4. Work happens → client leaves a 1-5★ review.
5. Ratings feed the next discovery cycle.

## Screen map → Allo Mokawil implementation

| Houzz | Allo Mokawil | Status |
|---|---|---|
| Home: photo inspiration feed | Home: category strip + top-rated pros + post-project CTA | ✅ `customer/customer_home_screen.dart` |
| Pro search / filters | Contractor search + wilaya + specialty filters | ✅ `browse/browse_screen.dart` |
| Pro profile (portfolio, reviews) | Contractor profile (bio, specialties, price range, portfolio, reviews) | ✅ `worker/worker_profile_screen.dart` |
| Post a project | Post project (title, category, wilaya, budget, urgency, photos) | ✅ `project/project_new_screen.dart` |
| My projects (status tabs) | My projects (open/in-progress/completed/cancelled) | ✅ `project/projects_screen.dart` |
| Project detail + bids | Detail + quotes list + accept/reject/complete | ✅ `project/project_detail_screen.dart` |
| Message threads | Conversations + text/image chat (offline queue) | ✅ `chat/*` |
| Pro verification | Contractor doc-upload verification → "verified" badge | ✅ `verify/verification_screen.dart` |
| Reviews | Post-completion 1-5★ + comment | ✅ `review/review_screen.dart` |
| Role gate | customer vs worker dual homes | ✅ `scaffold/role_home.dart` |

## Locale & design decisions (Algerian-first)

- **RTL-first**, Cairo font, `locale: ar`.
- **58 wilayas** + 16 service categories, cached offline.
- **Low-digital-literacy UX**: ≥56px touch targets, emoji category tiles,
  big high-contrast buttons, minimal chrome, Arabic rationale prompts before
  camera/gallery/notification permissions.
- **DZD** budgets; quote floor 1000 DZD.

## Deliberate differences (better for Algeria)

- **Verification doc pile** instead of paid leads: contractor badge via
  auto-entrepreneur/artisan card + ID + selfie.
- **Offline-friendly**: taxonomy + queued chat sends survive poor connectivity.
- Budget caps and pay-per-lead/commission plans carry over from the web model for
  the TAM that can't pay a subscription.