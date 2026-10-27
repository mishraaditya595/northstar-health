// P2-07c: Offline security tests; no network, real Auth users or secrets.
// A 4xx response must never invoke the irreversible admin operation.
import { createDeleteAccountHandler } from "./index.ts";
import type { createClient } from "npm:@supabase/supabase-js@2.95.0";

const owner = "00000000-0000-4000-8000-0000000000a1";
const another = "00000000-0000-4000-8000-0000000000b2";
const token = "Bearer " + "z".repeat(80);

type Scenario = {
  method?: string;
  body?: unknown;
  bearer?: string | null;
  signedInOwner?: string;
  anonymous?: boolean;
  confirmed?: boolean;
  fresh?: boolean;
  userError?: boolean;
  rpcError?: boolean;
  adminError?: boolean;
  failAdminTransport?: boolean;
};

function caseHarness(s: Scenario = {}) {
  let deletes = 0;
  const deletionCalls: Array<{ id: string; softDelete: boolean }> = [];
  let adminClients = 0;
  let rpcCalls = 0;
  const makeClient = ((
    _url: string,
    key: string,
  ) => {
    if (key === "server-service-role") {
      adminClients++;
      return {
        auth: {
          admin: {
            deleteUser: async (id: string, softDelete: boolean) => {
              deletes++;
              deletionCalls.push({ id, softDelete });
              if (s.failAdminTransport) throw Error("transport ambiguity");
              return { error: s.adminError ? { message: "blocked" } : null };
            },
          },
        },
      };
    }
    if (key !== "public-anon") throw Error("unexpected key");
    return {
      auth: {
        getUser: async () => ({
          data: {
            user: {
              id: s.signedInOwner ?? owner,
              is_anonymous: s.anonymous ?? false,
              email_confirmed_at: s.confirmed === false ? null : "2026-10-27T00:00:00Z",
            },
          },
          error: s.userError ? { message: "invalid token" } : null,
        }),
      },
      rpc: async (name: string) => {
        if (name !== "authorize_account_deletion") throw Error("unexpected RPC");
        rpcCalls++;
        return { data: s.fresh !== false, error: s.rpcError ? { message: "rejected" } : null };
      },
    };
  }) as unknown as typeof createClient;

  const handler = createDeleteAccountHandler({
    makeClient,
    getEnv: (key) => ({
      SUPABASE_URL: "https://local.invalid",
      SUPABASE_ANON_KEY: "public-anon",
      SUPABASE_SERVICE_ROLE_KEY: "server-service-role",
    } as Record<string, string>)[key],
  });
  const request = new Request("http://localhost/delete-account", {
    method: s.method ?? "POST",
    headers: s.bearer === null ? {} : { authorization: s.bearer ?? token },
    ...((s.method ?? "POST") === "GET"
      ? {}
      : { body: JSON.stringify(s.body ?? { account_id: owner, confirm: "DELETE MY ACCOUNT" }) }),
  });
  return {
    run: () => handler(request),
    stats: () => ({ deletes, deletionCalls, adminClients, rpcCalls }),
  };
}

function expect(condition: boolean, description: string): void {
  if (!condition) throw Error(description);
}

for (const [name, scenario, expected] of [
  ["GET method", { method: "GET" }, 405],
  ["unexpected request property", { body: { account_id: owner, confirm: "DELETE MY ACCOUNT", admin: true } }, 400],
  ["incorrect confirmation", { body: { account_id: owner, confirm: "maybe" } }, 400],
  ["no bearer", { bearer: null }, 400],
  ["wrong account_id", { body: { account_id: another, confirm: "DELETE MY ACCOUNT" } }, 401],
  ["anonymous owner", { anonymous: true }, 401],
  ["unconfirmed email", { confirmed: false }, 401],
  ["Auth verification error", { userError: true }, 401],
  ["old Auth session", { fresh: false }, 403],
  ["fresh-session gate error", { rpcError: true }, 403],
] as const) {
  Deno.test("refused " + name + " cannot invoke admin deletion", async () => {
    const h = caseHarness(scenario);
    const response = await h.run();
    expect(response.status === expected, name + ": wrong HTTP status");
    expect(h.stats().deletes === 0, name + ": refused request deleted an account");
    expect(h.stats().deletionCalls.length === 0, name + ": forbidden admin call arguments");
    expect(h.stats().adminClients === 0, name + ": admin client instantiated on refusal");
    expect(response.headers.get("cache-control") === "no-store", "sensitive response cache");
  });
}

Deno.test("successful response is exact receipt for verified owner", async () => {
  const h = caseHarness();
  const response = await h.run();
  expect(response.status === 200, "must confirm successful delete");
  expect(JSON.stringify(await response.json()) === '{"schema_version":1,"deleted":true}', "receipt changed");
  expect(h.stats().deletes === 1 && h.stats().adminClients === 1, "hard delete exactly once");
  expect(
    JSON.stringify(h.stats().deletionCalls) === JSON.stringify([{ id: owner, softDelete: false }]),
    "must call deleteUser(verified caller.id, false), never soft-delete or body-selected owner",
  );
  expect(h.stats().rpcCalls === 1, "fresh-session proof is mandatory");
});

Deno.test("verified alternate caller is the exact hard-delete target", async () => {
  const h = caseHarness({
    signedInOwner: another,
    body: { account_id: another, confirm: "DELETE MY ACCOUNT" },
  });
  const response = await h.run();
  expect(response.status === 200, "verified alternate caller accepted");
  expect(
    JSON.stringify(h.stats().deletionCalls) === JSON.stringify([{ id: another, softDelete: false }]),
    "admin deletion must target the independently verified Auth identity",
  );
});

Deno.test("admin failure or post-delete transport loss never claims success", async () => {
  for (const scenario of [{ adminError: true }, { failAdminTransport: true }]) {
    const h = caseHarness(scenario);
    const response = await h.run();
    expect(response.status === 503, "unknown server result must be 503");
    expect(JSON.stringify(await response.json()) === '{"error":"deletion_not_confirmed"}', "must not expose admin details");
  }
});
