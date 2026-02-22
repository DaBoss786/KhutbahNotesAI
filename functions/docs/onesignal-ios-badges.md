# OneSignal iOS Badge Strategy

For iOS push notifications, every OneSignal send path should increment the app badge by 1.

## Current implementation

- Shared helper: `withOneSignalIosBadgeIncrement(...)` in `functions/src/index.ts`.
- Helper injects:
  - `"ios_badgeType": "Increase"`
  - `"ios_badgeCount": 1`
- All current push sends use this helper:
  - Jumu'ah reminders
  - Summary ready
  - Weekly actions
  - Admin test push endpoint

## App-side behavior

- Badge clearing on app open is handled by OneSignal's default iOS behavior.
- Do not set `OneSignal_disable_badge_clearing` to `YES` in any app `Info.plist`.

## Future push routes

- Any new OneSignal push route should build payloads through `withOneSignalIosBadgeIncrement(...)` so iOS badge increment behavior is inherited by default.
