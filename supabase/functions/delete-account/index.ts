// P2-07c. Server-only irreversible deletion of the authenticated caller.
// Environment: SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_SERVICE_ROLE_KEY.
// Never copy the service-role key to Flutter, analytics, or logs.
// Auth user deletion cascades completed workouts, tombstones, 90-day receipts
// and the private per-owner cursor through their auth.users foreign keys.
import { createClient } from "npm:@supabase/supabase-js@2.95.0";

type Json = Record<string, unknown>;

const reply = (status: number, body: Json) =>
  new Response(JSON.stringify(body), {
    status,
    headers: {
      "content-type": "application/json; charset=utf-8",
      "cache-control": "no-store",
      "x-content-type-options": "nosniff",
    },
  });

function validRequest(method: string, authorization: string | null, body: unknown) {
  if (method !== "POST" ||
      !authorization?.startsWith("Bearer ") ||
      authorization.length < 30 ||
      !body || typeof body !== "object" || Array.isArray(body)) {
    return false;
  }
  const document = body as Json;
  return Object.keys(document).sort().join(",") === "account_id,confirm" &&
    document.confirm === "DELETE MY ACCOUNT" &&
    typeof document.account_id === "string" &&
    /^[0-9a-f-]{36}$/i.test(document.account_id);
}

/// Dependency-injected handler enables offline, fully stubbed Deno security
/// tests. Production still uses exactly createClient and Deno environment.
export function createDeleteAccountHandler({
  makeClient = createClient,
  getEnv = (key: string) => Deno.env.get(key),
}: {
  makeClient?: typeof createClient;
  getEnv?: (key: string) => string | undefined;
} = {}) {
  return async (request: Request): Promise<Response> => {
  if (request.method !== "POST") {
    return reply(405, { error: "method_not_allowed" });
  }

  const authorization = request.headers.get("authorization");
  const raw = await request.text().catch(() => "");
  if (raw.length > 512) return reply(400, { error: "invalid_request" });
  let body: unknown;
  try {
    body = JSON.parse(raw);
  } catch {
    return reply(400, { error: "invalid_request" });
  }
  if (!validRequest(request.method, authorization, body)) {
    return reply(400, { error: "invalid_request" });
  }

  const url = getEnv("SUPABASE_URL");
  const anon = getEnv("SUPABASE_ANON_KEY");
  const serviceRole = getEnv("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !anon || !serviceRole) {
    // Secrets/config never appear in the response.
    return reply(503, { error: "service_unavailable" });
  }
  const bearer = authorization!.slice(7);
  const requestedOwner = (body as Json).account_id as string;
  try {
    // All user-bound operations use the caller's JWT, never the admin client.
    const caller = makeClient(url, anon, {
      global: { headers: { Authorization: authorization! } },
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { data: userData, error: userError } = await caller.auth.getUser(bearer);
    const user = userData.user;
    if (userError || !user || user.is_anonymous ||
        !user.email_confirmed_at || user.id !== requestedOwner) {
      return reply(401, { error: "verified_account_required" });
    }

    // The RPC consults the *Auth session row*. A JWT with recently refreshed
    // iat but an old session_id is not a fresh OTP re-verification. Missing
    // sessions (including revoked/sign-out sessions) cannot pass.
    const { data: recent, error: recentError } = await caller.rpc(
      "authorize_account_deletion",
    );
    if (recentError || recent !== true) {
      return reply(403, { error: "fresh_verification_required" });
    }

    // One privileged server-side operation deletes the user. FK ON DELETE
    // CASCADE removes owned workout data in the same Postgres transaction.
    // Default hard delete (never soft delete); do not delete one table first.
    const admin = makeClient(url, serviceRole, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { error } = await admin.auth.admin.deleteUser(user.id, false);
    if (error) {
      // Client must treat ANY failure as uncertain and keep the local bound
      // partition locked until explicit same-owner sign-in/recovery.
      return reply(503, { error: "deletion_not_confirmed" });
    }
    return reply(200, { schema_version: 1, deleted: true });
  } catch {
    // Network errors may have happened AFTER the server committed deletion.
    // Never claim a rollback or return the original exception or identifiers.
    return reply(503, { error: "deletion_not_confirmed" });
  }
  };
}

// Importing the handler for tests MUST NOT start a listening server.
if (import.meta.main) {
  Deno.serve(createDeleteAccountHandler());
}
