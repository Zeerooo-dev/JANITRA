import type { SupabaseContext } from "@supabase/server";
import { personnelAuth } from "./index.ts";
import { manageIdentity } from "../_shared/manage_identity.ts";
import { identityDigest } from "../_shared/identity_security.ts";

const actor = "00000000-0000-0000-0000-000000000001",
  worker = "00000000-0000-0000-0000-000000000002";
const pepper = "a".repeat(64);
const check = (ok: unknown, why: string) => {
  if (!ok) throw new Error(why);
};
const request = (body: object) =>
  new Request("http://local.test", {
    method: "POST",
    headers: { authorization: "Bearer original-session" },
    body: JSON.stringify(body),
  });
function context(
  options: {
    known?: boolean;
    allowed?: boolean;
    authError?: boolean;
    state?: string;
    claim?: boolean;
    finish?: boolean;
    existing?: boolean;
    passwordConfirmed?: boolean;
    mfa?: boolean;
    passwordErrorStatus?: number;
    invited?: boolean;
  } = {},
) {
  const calls: { name: string; args: Record<string, unknown> }[] = [];
  const session = {
    access_token: `e30.${
      btoa(JSON.stringify({ session_id: worker }))
    }.signature`,
    refresh_token: "local-test-refresh",
  };
  const admin = {
    rpc: async (name: string, args: Record<string, unknown>) => {
      calls.push({
        name: name === "personnel_identity_command"
          ? String(args.p_action)
          : name,
        args,
      });
      let data: unknown = null;
      if (name === "actor_session_state") data = options.state ?? "active";
      else {switch (args.p_action) {
          case "rate":
            data = { allowed: options.allowed ?? true };
            break;
          case "login_lookup":
            data = options.known === false ? {} : {
              user_id: worker,
              login_email: "opaque@personnel.janitra.invalid",
            };
            break;
          case "claim_grant":
            data = options.claim === false ? {} : {
              user_id: worker,
              claim_id: worker,
              confirm_email: options.invited ?? false,
            };
            break;
          case "finish_grant":
            data = { completed: options.finish ?? true };
            break;
          case "reserve":
            data = {
              operation_id: worker,
              login_email: "opaque@personnel.janitra.invalid",
              existing_user_id: options.existing ? worker : null,
            };
            break;
          case "finish_provision":
            data = { user_id: worker };
            break;
          case "issue_grant":
            data = {
              identifier: "person.one",
              expires_at: "2026-10-18T06:00:00Z",
            };
            break;
        }}
      return { data, error: null };
    },
    auth: {
      admin: {
        updateUserById: async (id: string, attrs: Record<string, unknown>) => {
          calls.push({ name: "password_update", args: { id, ...attrs } });
          return {
            error: options.passwordErrorStatus
              ? { status: options.passwordErrorStatus }
              : null,
          };
        },
        createUser: async (attrs: Record<string, unknown>) => {
          calls.push({ name: "create", args: attrs });
          return { data: { user: { id: worker } }, error: null };
        },
      },
    },
  };
  const scoped = {
    auth: {
      signInWithPassword: async (args: Record<string, unknown>) => {
        calls.push({ name: "password_login", args });
        return options.authError
          ? { data: { user: null, session: null }, error: new Error("invalid") }
          : {
            data: {
              user: { id: options.passwordConfirmed ? actor : worker },
              session,
            },
            error: null,
          };
      },
      signOut: async () => {
        calls.push({ name: "signout", args: {} });
        return { error: null };
      },
      mfa: {
        getAuthenticatorAssuranceLevel: async () => ({
          data: {
            currentLevel: "aal1",
            nextLevel: options.mfa ? "aal2" : "aal1",
          },
          error: null,
        }),
      },
    },
  };
  return {
    calls,
    ctx: {
      supabase: scoped,
      supabaseAdmin: admin,
      jwtClaims: { session_id: actor },
    } as unknown as SupabaseContext,
  };
}

Deno.test("unknown username and wrong password have identical failures and both call Auth", async () => {
  const unknown = context({ known: false, authError: true }),
    wrong = context({ authError: true });
  const body = {
    action: "login",
    identifier: "person.one",
    password: "not-the-password",
  };
  const a = await personnelAuth(request(body), unknown.ctx, pepper),
    b = await personnelAuth(request(body), wrong.ctx, pepper);
  check(
    a.status === 401 && b.status === 401 && await a.text() === await b.text(),
    "enumeration response differs",
  );
  check(
    unknown.calls.some((c) => c.name === "password_login") &&
      wrong.calls.some((c) => c.name === "password_login"),
    "unknown identity skipped Auth",
  );
});
Deno.test("successful username login requires live authorization and returns no mapping fields", async () => {
  for (const state of ["active", "suspended", "revoked", "expired"]) {
    const { ctx, calls } = context({ state });
    const r = await personnelAuth(
      request({
        action: "login",
        identifier: "PERSON.ONE",
        password: "test-password",
      }),
      ctx,
      pepper,
    );
    check(
      r.status === (state === "active" ? 200 : 401),
      "invalid account received a session",
    );
    check(
      r.headers.get("cache-control") === "no-store",
      "session response may be cached",
    );
    check(
      !(await r.text()).includes("opaque@"),
      "internal alias exposed as a mapping",
    );
    check(
      calls.find((c) => c.name === "actor_session_state")?.args.p_actor ===
        worker,
      "wrong authorization actor",
    );
  }
});
Deno.test("rate limits and missing protection fail closed before Auth", async () => {
  for (const cfg of [{ allowed: false }, { allowed: true }]) {
    const { ctx, calls } = context(cfg);
    const r = await personnelAuth(
      request({ action: "login", identifier: "person.one", password: "test" }),
      ctx,
      cfg.allowed ? "" : pepper,
    );
    check(r.status === (cfg.allowed ? 503 : 429), "wrong failure");
    check(
      !calls.some((c) => c.name === "password_login"),
      "bypassed rate/protection gate",
    );
  }
});
Deno.test("setup claims first, updates only the claimed user, and confirms completion without exposing credentials", async () => {
  const { ctx, calls } = context();
  const code = "b".repeat(43);
  const r = await personnelAuth(
    request({
      action: "redeem",
      identifier: "person.one",
      code,
      password: "Chosen-password-123",
      user_id: actor,
    }),
    ctx,
    pepper,
  );
  check(r.status === 200, "setup failed");
  check(
    calls.map((c) => c.name).join(",") ===
      "rate,rate,claim_grant,password_update,finish_grant",
    "wrong setup order",
  );
  check(
    calls.find((c) => c.name === "password_update")?.args.id === worker,
    "client chose password target",
  );
  const sql = JSON.stringify(calls.filter((c) => c.name !== "password_update"));
  check(
    !sql.includes(code) && !sql.includes("Chosen-password-123"),
    "plaintext credential reached SQL",
  );
  check(
    await r.text() === '{"completed":true}',
    "setup leaked a session or credential",
  );
});
Deno.test("invalid grant never changes a password and unfinished activation is never success", async () => {
  const denied = context({ claim: false }),
    unfinished = context({ finish: false });
  for (const c of [denied, unfinished]) {
    const r = await personnelAuth(
      request({
        action: "redeem",
        identifier: "person.one",
        code: "b".repeat(43),
        password: "Chosen-password-123",
      }),
      c.ctx,
      pepper,
    );
    check(r.status === 401, "unfinished setup reported success");
  }
  check(
    !denied.calls.some((c) => c.name === "password_update"),
    "unclaimed code changed a password",
  );
});
Deno.test("only a server-validated invited account claim can authorize email activation", async () => {
  for (const invited of [false, true]) {
    const { ctx, calls } = context({ invited });
    const response = await personnelAuth(
      request({
        action: "redeem",
        identifier: "person.one",
        code: "a".repeat(43),
        password: "Chosen-password-123",
        confirm_email: true,
      }),
      ctx,
      pepper,
    );
    check(response.status === 200, "setup failed");
    check(
      calls.find((c) => c.name === "password_update")?.args.email_confirm ===
        (invited ? true : undefined),
      "client controlled email activation",
    );
  }
});
Deno.test("Supervisor provisioning preserves optional email, randomizes initial password and reuses reconciled Auth user", async () => {
  for (const existing of [false, true]) {
    const { ctx, calls } = context({ existing, passwordConfirmed: true });
    const r = await manageIdentity(request({}), ctx, {
      id: actor,
      email: "manager@example.test",
    }, {
      action: "create_personnel",
      agency_id: "10000000-0000-0000-0000-000000000001",
      site_id: "30000000-0000-0000-0000-000000000001",
      request_id: worker,
      username: "person.one",
      full_name: "Person",
      password: "test-password",
    }, pepper);
    const body = await r.json();
    check(
      r.status === 200 && body.setup_code.length === 43,
      "code issuance failed",
    );
    check(
      calls.filter((c) => c.name === "create").length === (existing ? 0 : 1),
      "duplicate Auth account created",
    );
    check(
      !JSON.stringify(
        calls.filter((c) => c.name === "reserve" || c.name === "issue_grant"),
      ).includes(body.setup_code),
      "plaintext code persisted",
    );
    if (!existing) {
      check(
        calls.find((c) => c.name === "create")?.args.password !==
          body.setup_code,
        "handed out initial permanent password",
      );
    }
  }
});
Deno.test("Supervisor password and configured MFA protect username creation", async () => {
  for (
    const opts of [{ passwordConfirmed: false }, {
      passwordConfirmed: true,
      mfa: true,
    }]
  ) {
    const { ctx, calls } = context(opts);
    const r = await manageIdentity(request({}), ctx, {
      id: actor,
      email: "manager@example.test",
    }, {
      action: "create_personnel",
      site_id: "30000000-0000-0000-0000-000000000001",
      request_id: worker,
      username: "person.one",
      full_name: "Person",
      password: "test-password",
    }, pepper);
    check(r.status === 401 || r.status === 403, "reauthentication bypass");
    check(
      !calls.some((c) => c.name === "reserve"),
      "identity reserved without confirmation",
    );
  }
});
Deno.test("identity digests separate task-independent purposes", async () => {
  check(
    await identityDigest(pepper, "grant", "secret") !==
      await identityDigest(pepper, "rate-grant", "secret"),
    "purpose separation missing",
  );
});
Deno.test("definite password validation rejection permits a replacement, ambiguous failures remain sealed", async () => {
  for (const status of [422, 503]) {
    const { ctx, calls } = context({ passwordErrorStatus: status });
    const r = await personnelAuth(
      request({
        action: "redeem",
        identifier: "person.one",
        code: "a".repeat(43),
        password: "Chosen-password-123",
      }),
      ctx,
      pepper,
    );
    check(r.status === 401, "failed password change reported success");
    check(
      calls.some((c) => c.name === "reject_grant") === (status === 422),
      "uncertain password change was unlocked",
    );
    check(
      !calls.some((c) => c.name === "finish_grant"),
      "failed password change activated access",
    );
  }
});
