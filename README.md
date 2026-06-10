# FitNet — IoT Smart-Scale Fitness Tracker

FitNet is a Flutter app built around an IoT smart scale (Raspberry Pi +
load sensor). The scale communicates over MQTT, readings are stored in
Firebase, and the app adds AI coaching, meal tracking, hydration, workouts,
and progress reports on top.

## App structure (5 tabs)

| Tab | Purpose |
| --- | --- |
| **Dashboard** | Overview only: smart-scale weight/BMI, Get Weight button, target weight, today's calories, water summary, quick actions |
| **AI Coach** | Chat, fastest food logging ("I ate a man2ouche for breakfast"), fitness advice, progress questions |
| **Meals** | Source of truth for meal history: manual add, AI photo/text scan, edit, delete, today's totals |
| **Progress** | Weight history & chart (IoT readings) + PDF report, hydration, body measurements |
| **More** | Profile (target weight → MQTT), fitness goals, workouts, nearby gyms, settings |

## IoT smart-scale flow (core feature)

1. User taps **Get Weight** → app publishes to `fitnet/get_weight`
2. Raspberry Pi reads the sensor → publishes to `fitnet/weight`
3. App updates weight/BMI, writes a document to the Firestore `weights`
   collection, and shows a background notification when the app is not in
   the foreground
4. `fitnet/reset` resets the displayed weight; the profile's target weight
   publishes to `fitnet/goal`

## Course topics demonstrated

- **Layouts** — reusable widgets in `lib/widgets/` (StatCard, NavCard,
  EmptyState, FriendlyErrorState) used across pages
- **Navigation** — named routes in `lib/routes/app_routes.dart`; screens
  communicate through arguments and `Navigator.pop` return values
  (ProfilePage and MealScanPage both return results)
- **Shared Preferences** — `lib/storage/app_preferences.dart`: theme mode,
  last selected tab, daily water goal
- **List views** — `ListView.builder` with empty states on Meals, Workouts,
  Fitness Goals, Measurements, and Weight History
- **SQLite** — `lib/storage/meal_cache.dart`: best-effort local mirror of
  meal summaries; Firestore stays the source of truth, the cache is only
  read when offline
- **Services / background tasks** — `lib/services/reminder_scheduler.dart`:
  OS-scheduled (zonedSchedule) water & workout reminders with an in-memory
  fallback; MQTT weight notifications are separate and untouched.
  Reminders use *inexact* Android scheduling on purpose (no extra
  permissions; may fire a few minutes late) and do not survive a device
  reboot (no boot receiver, to keep manifest permissions unchanged)
- **Broadcast/event listeners** — MQTT `client.updates` listener in
  `main.dart`, Firestore snapshot streams throughout
- **Firebase** — Auth (login/signup) + Firestore (users, weights, meals,
  workouts, goals, measurements, water logs)
- **Google Maps** — Nearby Gyms (`lib/nearby_gyms_page.dart`) with location
  permission handling and an external-maps fallback

## Gemini setup

The AI coach has an in-code fallback Gemini key for local development.

> **Security note:** the fallback key exists only so the course demo runs
> out of the box. Before any production use, rotate the key, restrict it in
> Google AI Studio, and pass it exclusively via `--dart-define` (local
> secret files are covered by `.gitignore`). The key is never logged or
> shown in the UI.

You can override it at run/build time:

```powershell
flutter run --dart-define=GEMINI_API_KEY=YOUR_KEY_HERE
```

Model overrides:

```powershell
flutter run --dart-define=GEMINI_API_KEY=YOUR_KEY_HERE --dart-define=GEMINI_PRIMARY_MODEL=gemini-2.5-flash-lite --dart-define=GEMINI_FALLBACK_MODEL=gemini-2.5-flash
```

Default models:

- Primary: `gemini-2.5-flash-lite`
- Fallback: `gemini-2.5-flash`
