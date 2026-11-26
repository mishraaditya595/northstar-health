# Catalogue source

This folder is the source of the shared exercise, workout template and program catalogue. The server serves it and phones download it, so changing it never needs an app update.

Before you edit anything here, read [docs/CATALOG.md](../docs/CATALOG.md), and especially "Changing content after launch". In short:

- Edit the JSON, then run `python3 scripts/catalog_build.py check` and `publish`. Never edit a generated migration by hand.
- Users' copied workouts, added programs and past sessions never change when this content changes.
- IDs are permanent: never delete, rename or reuse one. An exercise's `mode` never changes; add a new ID instead.
- Use `rollback --to N` to undo a bad release.
- Raise `minAppCatalogSchema` only for a breaking format change, which also needs an app update.
