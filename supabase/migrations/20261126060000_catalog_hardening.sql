-- Catalogue hardening (training library stage 9 security review, ADR-0010).
-- The service key never needs the catalogue tables: releases are published
-- and rolled back by migrations only, and clients read through the two RPCs.
revoke all on public.catalog_releases from service_role;
revoke all on public.catalog_live from service_role;

-- The builder caps a snapshot at 2 MiB of canonical JSON; the server now
-- refuses anything larger too. jsonb text adds whitespace, so the content
-- limit is looser than the size limit.
alter table public.catalog_releases
  add constraint catalog_releases_size_limit check (size_bytes <= 2097152),
  add constraint catalog_releases_content_limit
    check (octet_length(content::text) <= 4194304);
