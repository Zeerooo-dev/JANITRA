import { managePins, pinDigest } from "./index.ts";
import type { SupabaseContext } from "@supabase/server";

const actor = "00000000-0000-0000-0000-000000000001";
const target = "00000000-0000-0000-0000-000000000003";
const secret = "12".repeat(32);
const body = {
  action: "set",
  kind: "employee",
  user_id: target,
  agency_id: "10000000-0000-0000-0000-000000000001",
  site_id: "30000000-0000-0000-0000-000000000001",
  pin: "0042",
  password: "test-password",
};
function check(ok: unknown, why: string) {
  if (!ok) throw new Error(why);
}
function request(data: object) {
  return new Request("http://localhost/manage-pins", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      authorization: "Bearer test-session",
    },
    body: JSON.stringify(data),
  });
}
function context(
  options: {
    allowed?: boolean;
    password?: boolean;
    mfa?: boolean;
    mfaComplete?: boolean;
    assuranceFailure?: boolean;
    verified?: boolean;
  } = {},
) {
  const calls: { name: string; args?: Record<string, unknown> }[] = [];
  return {
    calls,
    ctx: {
      jwtClaims: { session_id: actor },
      supabase: {
        auth: {
          getUser: async () => ({
            data: {
              user: {
                id: actor,
                email: "manager@example.test",
                is_anonymous: false,
                email_confirmed_at: options.verified === false
                  ? null
                  : "2026-10-12T00:00:00Z",
              },
            },
            error: null,
          }),
          mfa: {
            getAuthenticatorAssuranceLevel: async () => ({
              data: {
                currentLevel: options.mfaComplete ? "aal2" : "aal1",
                nextLevel: options.mfa ? "aal2" : "aal1",
              },
              error: options.assuranceFailure ? new Error("unavailable") : null,
            }),
          },
          signInWithPassword: async () => {
            calls.push({ name: "password" });
            return {
              data: { user: options.password === false ? null : { id: actor } },
              error: options.password === false ? new Error("denied") : null,
            };
          },
        },
      },
      supabaseAdmin: {
        rpc: async (name: string, args: Record<string, unknown>) => {
          calls.push({ name, args });
          if (name === "actor_session_state") {
            return { data: "active", error: null };
          }
          return {
            data: name === "can_manage_pin" ? options.allowed !== false : {
              configured: true,
              changed_at: "2026-10-12T00:00:00Z",
              can_reset: true,
            },
            error: null,
          };
        },
      },
    } as unknown as SupabaseContext,
  };
}

Deno.test("PIN enrollment sends only a peppered digest to Postgres", async () => {
  const { ctx, calls } = context();
  const response = await managePins(request(body), ctx, secret);
  check(response.status === 200, "enrollment failed");
  const write = calls.find((call) => call.name === "set_pin_credential")!;
  check(
    /^[0-9a-f]{64}$/.test(String(write.args?.p_digest)),
    "missing protected digest",
  );
  check(write.args?.p_digest !== body.pin, "raw PIN reached database");
  check(
    !JSON.stringify(write.args).includes("test-password"),
    "password reached database",
  );
  const result = await response.json();
  check(
    !("pin" in result) && !("pin_hash" in result) && !("p_digest" in result),
    "credential returned",
  );
});
Deno.test("PIN digests bind purpose, account and separate secret; preserve leading zeroes", async () => {
  const a = await pinDigest(secret, "employee", target, "0042");
  check(
    a === await pinDigest(secret, "employee", target, "0042"),
    "not deterministic",
  );
  check(
    a !== await pinDigest(secret, "supervisor", target, "0042"),
    "purpose not separated",
  );
  check(
    a !== await pinDigest(secret, "employee", actor, "0042"),
    "identity not separated",
  );
  check(
    a !== await pinDigest("34".repeat(32), "employee", target, "0042"),
    "secret not used",
  );
  check(
    a !== await pinDigest(secret, "employee", target, "42"),
    "leading zero lost",
  );
});
Deno.test("exactly four numeric characters required before any write", async () => {
  for (const pin of [42, "123", "12345", "12a4", " 1234", "１２３４"]) {
    const { ctx, calls } = context();
    check(
      (await managePins(request({ ...body, pin }), ctx, secret)).status === 400,
      "bad PIN accepted",
    );
    check(
      calls.every((c) => c.name === "actor_session_state"),
      "bad PIN reached credential RPC",
    );
  }
});
Deno.test("denied scope stops before reauthentication and write", async () => {
  const { ctx, calls } = context({ allowed: false });
  check(
    (await managePins(request(body), ctx, secret)).status === 403,
    "wrong scope status",
  );
  check(
    calls.map((c) => c.name).join(",") === "actor_session_state,can_manage_pin",
    "unsafe work after scope denial",
  );
});
Deno.test("missing server secret fails closed", async () => {
  const { ctx, calls } = context();
  check(
    (await managePins(request(body), ctx, "")).status === 503,
    "missing secret accepted",
  );
  check(
    !calls.some((call) => call.name === "set_pin_credential"),
    "unprotected credential written",
  );
});
Deno.test("wrong password cannot issue a PIN", async () => {
  const { ctx, calls } = context({ password: false });
  check(
    (await managePins(request(body), ctx, secret)).status === 401,
    "wrong password status",
  );
  check(
    !calls.some((call) => call.name === "set_pin_credential"),
    "PIN written despite password failure",
  );
});
Deno.test("configured MFA must be completed before PIN management", async () => {
  const { ctx, calls } = context({ mfa: true });
  check(
    (await managePins(request(body), ctx, secret)).status === 403,
    "AAL1 accepted with MFA",
  );
  check(
    !calls.some((call) =>
      call.name === "password" || call.name === "set_pin_credential"
    ),
    "MFA bypass",
  );
});

Deno.test("completed MFA still permits password-confirmed PIN management", async () => {
  const { ctx, calls } = context({ mfa: true, mfaComplete: true });
  check(
    (await managePins(request(body), ctx, secret)).status === 200,
    "verified MFA denied",
  );
  check(
    calls.some((call) => call.name === "set_pin_credential"),
    "verified request did not write",
  );
});

Deno.test("assurance check failure cannot silently bypass MFA", async () => {
  const { ctx, calls } = context({ assuranceFailure: true });
  check(
    (await managePins(request(body), ctx, secret)).status === 401,
    "failed check allowed",
  );
  check(
    !calls.some((call) => call.name === "set_pin_credential"),
    "failed check wrote PIN",
  );
});
Deno.test("unverified account cannot read or manage PIN status", async () => {
  const { ctx, calls } = context({ verified: false });
  check(
    (await managePins(request({ ...body, action: "status" }), ctx, secret))
      .status === 401,
    "unverified allowed",
  );
  check(calls.length === 0, "unverified actor reached admin RPC");
});
Deno.test("status requires scope but no password and returns only configuration metadata", async () => {
  const { ctx, calls } = context();
  const response = await managePins(
    request({ ...body, action: "status", pin: null, password: null }),
    ctx,
    "",
  );
  check(
    response.status === 200 &&
      calls.map((c) => c.name).join(",") === "actor_session_state,pin_status",
    "wrong status route",
  );
});
Deno.test("standalone PIN verification is not an exposed action", async () => {
  const { ctx, calls } = context();
  check(
    (await managePins(request({ ...body, action: "verify" }), ctx, secret))
      .status === 400,
    "standalone verify exposed",
  );
  check(calls.length === 0, "verification reached database");
});
