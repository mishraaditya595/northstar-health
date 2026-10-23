# Independent AI code review protocol

Reviewer must inspect diff, code paths and tests, not rely on implementation agent's summary. Implementer never self-approves or merges.

**Blocker:** data loss, fabricated metrics, sensitive data disclosure, unsafe permissions, missing transactional writes, incorrect clinical inference.  
**High:** false successful save, incorrect units/source/timestamp, double imports, unhandled permission revoke, crashes, tablet overflow, inaccessible workout controls.  
**Medium:** contrast issues, missing theme/empty tests, unnecessary rebuilds, poor local boundaries or undocumented dependencies.

Review every changed feature against: [ ] Android phone [ ] iPhone [ ] Android tablet [ ] iPad/split view [ ] dark/light [ ] keyboard and large text [ ] loading/empty/error/permission denied [ ] offline and restart [ ] unit/source/time integrity [ ] privacy [ ] performance [ ] tests/CI [ ] updated docs/ADRs.

Findings include file/line, reproduction, expected impact, smallest correction and regression test. Explain which tests were **not** run. No blanket approval based only on green static analysis. Real plugin changes require real-device permission and lifecycle checks.

**Watch review additions:** independently validate native session ownership, idle/screen-off recording, app termination/relaunch recovery, offline event queue, idempotency, time-zone/clock drift, duplicated sample reconciliation, watch battery budget and package/distribution compatibility. See [WEARABLES.md](WEARABLES.md).

**ObjectBox review additions:** confirm committed `objectbox-model.json`, code-generation consistency, stable UIDs across renames, safe updates, migration/backups, transactional set+outbox writes, isolates and lifecycle cleanup. See [OBJECTBOX.md](OBJECTBOX.md).
