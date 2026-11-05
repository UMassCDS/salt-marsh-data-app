# Saved upload payloads

The exact JSON body the app sends to `POST /api/mobile/field-outings`, built through the real sync code for a fixed set of scenarios (`test/support/payload_scenarios.dart`).

- `current/` is checked by `test/contracts/payload_fixtures_test.dart`. If the app's upload body changes, that test fails; regenerate on purpose with `UPDATE_PAYLOADS=1 flutter test test/contracts`, and review the diff.
- `v<version>/` folders are what a released app sent. They are frozen: never edit them. The backend replays every folder in CI, so a backend change cannot reject or mis-store what an installed app still sends.

## v0.7.0

Derived from `current/`. The tag's `sync_service.dart` builds the same body except that vegetation records have no `accuracy_m` and no `location_quality`, so those two keys are removed. Checked against the source of the `v0.7.0` tag.

## Freezing a release

At release time copy `current/` to `v<version>/` unchanged.
