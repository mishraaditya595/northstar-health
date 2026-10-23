# Health data safety and privacy contract

- Never invent health readings, diagnoses, predictions or readiness scores.
- Observations must have metric, value, unit, start/end UTC time, timezone/calendar day where relevant, source platform, source ID, source app/device, last import time and validity.
- Missing, revoked, stale and zero are **different states**; never show unavailable as numeric zero.
- Deduplicate by source identity and interval; don't sum already aggregated HealthKit/Health Connect totals or compare incompatible device measurements without explanation.
- Permission request follows plain-language informed context, is scoped to needed metrics, and can be partially denied or revoked. Read and write permissions are different.
- iOS uses HealthKit and Android uses Health Connect (not deprecated Google Fit); review Apple/Google permission and policy requirements when implementing.
- No sensitive health readings, personal notes, account/device IDs, tokens or raw SDK payloads in analytics, error tracking, logs, CI screenshots or test fixtures.
- Real data storage needs migration, encryption/key-management threat modeling, retention, export and delete, secure backup, and local/offline behavior before rollout.
- Health platforms do not guarantee a watch has synced; display the **last source update** and never imply real-time availability without proof.
- The Flutter demo labels every sample fictional. Actual platform integration is explicitly outside this scaffold.

## Watch measurement provenance

Record device-local measurement time, originating watch platform and stable source/sample ID. A WatchConnectivity/Data Layer message is transport, not proof of persistence in the phone database. Preserve distinct consent boundaries for phone aggregation and watch sensors, and never assume a consumer watch provides medically reliable continuous vital monitoring. See [WEARABLES.md](WEARABLES.md) and [SYNC_PROTOCOL.md](SYNC_PROTOCOL.md).
