# Independent AI code review protocol

Reviewer must inspect diff, code paths and tests, not rely on implementation agent's summary. Implementer never self-approves or merges.

**Blocker:** data loss, fabricated metrics, sensitive data disclosure, unsafe permissions, missing transactional writes, incorrect clinical inference.  
**High:** false successful save, incorrect units/source/timestamp, double imports, unhandled permission revoke, crashes, tablet overflow, inaccessible workout controls.  
**Medium:** contrast issues, missing theme/empty tests, unnecessary rebuilds, poor local boundaries or undocumented dependencies.

Review every changed feature against: [ ] Android phone [ ] iPhone [ ] Android tablet [ ] iPad/split view [ ] dark/light [ ] keyboard and large text [ ] loading/empty/error/permission denied [ ] offline and restart [ ] unit/source/time integrity [ ] privacy [ ] performance [ ] tests/CI [ ] updated docs/ADRs.

Findings include file/line, reproduction, expected impact, smallest correction and regression test. Explain which tests were **not** run. No blanket approval based only on green static analysis. Real plugin changes require real-device permission and lifecycle checks.
