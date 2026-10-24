# Phase 1 implementation notes

The [roadmap](../../ROADMAP.md) defines project milestones. These pages record
implemented behavior, data ownership, known QA gaps and review evidence rather
than replacing architecture decisions.

- [ObjectBox foundation](phase-1/objectbox-foundation.md) — session/set durability,
  revisions and offline backup policy (PR #5).
- [Exercise catalog and workout plans](phase-1/exercise-catalog-and-plans.md)
  — PR #7, transactional plan editor and catalog.
- [Plan editor hardening](phase-1/plan-editor-hardening.md) — follow-up to PR #7.

The data-policy source of truth remains [ObjectBox](../OBJECTBOX.md) and
[ADR-0003](../adr/0003-data-cloud-health.md).
