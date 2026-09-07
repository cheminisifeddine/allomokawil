# Allo Mokawil (الو موكاول) — Mobile App

Houzz-style home-design & renovation marketplace for Algeria. Flutter app for
**Android + iOS**, built to full parity with the Web v1 (`/root/finili`) and its
API contracts.

## Run

```bash
flutter pub get
flutter run --dart-define=API_BASE_URL=https://api.allomokawil.dz
```

`API_BASE_URL` is injected at build time; no secret is committed
(see `lib/src/core/constants/app_config.dart`).

## Verify

```bash
flutter analyze   # → No issues found!
flutter test      # → All tests passed!
```

## Roles

- **customer (صاحب مشروع)** — dual home: search + top-rated pros, post a project.
- **worker (مقاول/حرفي)** — dual home: project marketplace + filters, own profile & verification.

## Structure

```
lib/
  main.dart                      # bootstrap: ApiClient + AuthState + restore
  src/app.dart                   # RTL MaterialApp, locale ar, role gate
  src/core/
    app_scope.dart               # DI scope (InheritedWidget)
    constants/app_config.dart    # API base URL (dart-define)
    network/api_client.dart      # typed GET/POST/PUT/DELETE + multipart upload
    security/auth_state.dart     # session persistence + role
    theme/app_theme.dart         # minimalist, big-touch, Cairo/Navy/Sand
    l10n/strings.dart            # Arabic UI strings
  src/data/
    taxonomy.dart                # 58 wilayas + 16 service categories (offline)
    repository.dart              # screen-facing API (mirrors web loaders/actions)
  src/models/                    # mirrors finili types.ts (chat/project/quote/...)
  src/screens/
    auth/                        # login, register(+role), role gate
    scaffold/role_home.dart      # role-aware home switch
    customer/ worker/            # dual home screens
    browse/ project/ chat/ verify/ review/
  src/widgets/                   # BigButton, CategoryGrid, ProjectCard, RatingStars...
assets/fonts/Cairo-*.ttf         # Arabic RTL font
```

## Mobile API contract

The app calls these endpoints (the backend must mirror them). All JSON, auth via
`Authorization: Bearer <token>`.

| Method | Endpoint | Purpose |
|---|---|---|
| POST | `/api/login` `/api/register` | auth → `{token, user}` |
| GET | `/api/mobile/workers/top?limit=` | top-rated pros |
| GET | `/api/mobile/workers/search?category=&wilaya=` | contractor search |
| GET | `/api/mobile/workers/:id` | contractor profile |
| GET | `/api/mobile/workers/:id/reviews` | contractor reviews |
| GET | `/api/mobile/workers/:id/portfolio` | portfolio image URLs |
| GET | `/api/mobile/my/profile` | signed-in worker's profile |
| POST | `/api/mobile/workers/:id/verification` | verify docs |
| GET | `/api/mobile/projects?category=&wilaya=&status=&page=` | browse (marketplace) |
| GET | `/api/mobile/projects/:id` | project detail |
| POST | `/api/mobile/projects` | create project |
| GET | `/api/mobile/my/projects?status=` | my projects |
| GET | `/api/mobile/projects/:id/quotes` | quotes for a project |
| POST | `/api/mobile/projects/:id/quotes` | submit quote (amount≥1000) |
| POST | `/api/mobile/projects/:id/quotes/:qid/accept` | accept quote / reject others |
| POST | `/api/mobile/projects/:id/complete` | mark completed → review |
| POST | `/api/mobile/projects/:id/review` | create review (1-5 stars) |
| GET/POST | `/api/mobile/conversations` | list / open conversation |
| GET | `/api/messages/:id?after=` | messages (poll) |
| POST | `/api/messages/:id` | send text/image |
| GET | `/api/notifications` `/api/unread` | notifications |
| POST | `/api/upload` | multipart upload → `{url}` |