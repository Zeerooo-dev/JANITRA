import { workflow } from "./index.ts";
import { currentSession } from "../_shared/current_session.ts";
import type { SupabaseContext } from "@supabase/server";
const actor = "00000000-0000-0000-0000-000000000001",
  session = "00000000-0000-0000-0000-000000000002";
const task = "10000000-0000-0000-0000-000000000001",
  requestId = "20000000-0000-0000-0000-000000000001",
  secret = "12".repeat(32);
function check(value: unknown, message: string) {
  if (!value) throw new Error(message);
}
function request(body: object) {
  return new Request("http://localhost/workflow", {
    method: "POST",
    headers: { authorization: "Bearer test-session" },
    body: JSON.stringify(body),
  });
}
function mock(
  options: {
    session?: unknown;
    mfa?: boolean;
    password?: boolean;
    error?: { code: string; message: string };
    result?: unknown;
  } = {},
) {
  const calls: { name: string; args: Record<string, unknown> }[] = [];
  const ctx = {
    jwtClaims: { session_id: options.session ?? session },
    supabase: {
      auth: {
        getUser: async () => ({
          data: {
            user: {
              id: actor,
              email: "test@example.test",
              email_confirmed_at: "2026-10-12",
              factors: options.mfa ? [{ status: "verified" }] : [],
            },
          },
          error: null,
        }),
        mfa: {
          getAuthenticatorAssuranceLevel: async () => ({
            data: {
              currentLevel: "aal1",
              nextLevel: options.mfa ? "aal2" : "aal1",
            },
            error: null,
          }),
        },
        signInWithPassword: async () => ({
          data: { user: options.password === false ? null : { id: actor } },
          error: null,
        }),
      },
    },
    supabaseAdmin: {
      rpc: async (name: string, args: Record<string, unknown>) => {
        calls.push({ name, args });
        return {
          data: options.result ?? { ok: true },
          error: options.error ?? null,
        };
      },
    },
  } as unknown as SupabaseContext;
  return { ctx, calls };
}
Deno.test("workflow binds verified actor and session, strips spoofed identity and secrets", async () => {
  const { ctx, calls } = mock();
  const r = await workflow(
    request({
      action: "submit",
      request_id: requestId,
      task_id: task,
      version: 0,
      pin: "0042",
      password: "private password",
      actor: "forged",
      session: "forged",
      digest: "forged",
      _reauth: true,
    }),
    ctx,
    secret,
  );
  check(r.status === 200, "submit rejected");
  const args = calls[0].args, payload = args.p_data as Record<string, unknown>;
  check(
    args.p_actor === actor && args.p_session === session,
    "forged actor/session",
  );
  check(/^[a-f0-9]{64}$/.test(String(payload.digest)), "no HMAC");
  check(
    !JSON.stringify(args).includes("private password") &&
      !Object.hasOwn(payload, "pin") && !Object.hasOwn(payload, "_reauth") &&
      !Object.hasOwn(payload, "actor"),
    "secret or forged fields forwarded",
  );
});
Deno.test("workflow PIN confirmation purpose differs for submit and verify", async () => {
  const a = mock(), b = mock();
  for (const [m, action] of [[a, "submit"], [b, "verify"]] as const) {
    await workflow(
      request({ action, request_id: requestId, task_id: task, pin: "0042" }),
      m.ctx,
      secret,
    );
  }
  check(
    (a.calls[0].args.p_data as Record<string, unknown>).digest !==
      (b.calls[0].args.p_data as Record<string, unknown>).digest,
    "purpose not bound",
  );
});
Deno.test("schedule deletion binds actor/session, allows only the selected target and rejects malformed scope", async () => {
  for (const action of ["activity_delete", "shift_delete", "rule_delete"]) {
    const { ctx, calls } = mock();
    const response = await workflow(
      request({
        action,
        request_id: requestId,
        id: task,
        agency_id: task,
        site_id: task,
        actor: "forged",
        session: "forged",
        deleted_at: "forged",
        password: "secret",
      }),
      ctx,
      secret,
    );
    check(response.status === 200, "deletion action rejected");
    check(
      calls[0].args.p_actor === actor && calls[0].args.p_session === session,
      "forged authority forwarded",
    );
    const payload = calls[0].args.p_data as Record<string, unknown>;
    check(
      payload.id === task && !Object.hasOwn(payload, "deleted_at") &&
        !Object.hasOwn(payload, "password"),
      "untrusted deletion fields forwarded",
    );
    const invalid = mock();
    check(
      (await workflow(
        request({
          action,
          request_id: requestId,
          id: "bad",
          agency_id: task,
          site_id: task,
        }),
        invalid.ctx,
        secret,
      )).status === 400,
      "malformed target accepted",
    );
    check(invalid.calls.length === 0, "invalid delete reached database");
  }
});
Deno.test("workflow denies invalid session and unfinished MFA before database", async () => {
  for (const opts of [{ session: "bad" }, { mfa: true }]) {
    const m = mock(opts);
    const r = await workflow(
      request({ action: "approve", request_id: requestId, task_id: task }),
      m.ctx,
      secret,
    );
    check(r.status === 401 || r.status === 403, "allowed");
    check(m.calls.length === 0, "database touched");
  }
});
Deno.test("workflow override requires account password and ignores client reauth claim", async () => {
  const m = mock({ password: false });
  const r = await workflow(
    request({
      action: "override",
      request_id: requestId,
      task_id: task,
      password: "wrong",
      _reauth: true,
    }),
    m.ctx,
    secret,
  );
  check(r.status === 401 && m.calls.length === 0, "override allowed");
  const ok = mock();
  const accepted = await workflow(
    request({
      action: "override",
      request_id: requestId,
      task_id: task,
      password: "test-only",
    }),
    ok.ctx,
    secret,
  );
  check(
    accepted.status === 200 &&
      (ok.calls[0].args.p_data as Record<string, unknown>)._reauth === true,
    "no trusted confirmation",
  );
});
Deno.test("workflow wrong PIN is rejected without claiming success", async () => {
  const m = mock({
    result: { ok: false, code: "incorrect", message: "Incorrect PIN." },
  });
  const r = await workflow(
    request({
      action: "submit",
      request_id: requestId,
      task_id: task,
      pin: "0042",
    }),
    m.ctx,
    secret,
  );
  check(
    r.status === 409 && (await r.json()).ok === false,
    "failure acknowledged",
  );
});
Deno.test("workflow confirms session expiration with a client invalidation code", async () => {
  const m = mock({ error: { code: "42501", message: "Session expired" } });
  const r = await workflow(
    request({ action: "approve", request_id: requestId, task_id: task }),
    m.ctx,
    secret,
  );
  check(
    r.status === 403 && (await r.json()).code === "session_ended",
    "no invalidation",
  );
});
Deno.test("workflow validates four-digit PIN and maximum request size", async () => {
  for (const pin of ["42", "abcd", "12345"]) {
    const m = mock();
    check(
      (await workflow(
            request({
              action: "submit",
              request_id: requestId,
              task_id: task,
              pin,
            }),
            m.ctx,
            secret,
          )).status === 400 && m.calls.length === 0,
      "bad PIN allowed",
    );
  }
  const m = mock();
  check(
    (await workflow(
      request({
        action: "submit",
        request_id: requestId,
        remarks: "x".repeat(17000),
      }),
      m.ctx,
      secret,
    )).status === 413,
    "large body allowed",
  );
});
Deno.test("current session verifier distinguishes network failure from confirmed expiration", async () => {
  const fail = mock({ error: { code: "network", message: "unavailable" } });
  const r = await currentSession(fail.ctx, actor);
  check(
    r?.status === 503 && (await r.json()).code === "verification_unavailable",
    "network marked expired",
  );
  const expired = mock({ result: "expired" });
  check(
    (await currentSession(expired.ctx, actor))?.status === 401,
    "expired accepted",
  );
  const active = mock({ result: "active" });
  check(await currentSession(active.ctx, actor) === null, "active denied");
});
