import { manageUsers } from "./index.ts";
import type { SupabaseContext } from "@supabase/server";

const actor = "00000000-0000-0000-0000-000000000001";
const agency = "10000000-0000-0000-0000-000000000001";
const site = "30000000-0000-0000-0000-000000000001";
const target = "00000000-0000-0000-0000-000000000002";
const body = {
  action: "invite",
  agency_id: agency,
  site_id: site,
  role: "personnel",
  email: "new@example.test",
  full_name: "New Person",
  password: "test-password",
};
function check(ok: unknown, why: string) {
  if (!ok) throw new Error(why);
}
function request(data: object) {
  return new Request("http://localhost/manage-users", {
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
    validPassword?: boolean;
    existing?: string | null;
    mfaRequired?: boolean;
    mutationError?: { code: string; message: string };
    owner?: boolean;
    canDelete?: boolean;
    prepared?: boolean;
    deletionError?: boolean;
    inviteError?: { code: string; status: number };
  } = {},
) {
  const calls: string[] = [];
  const argsList: Record<string, unknown>[] = [];
  const admin = {
    rpc: async (name: string, args: Record<string, unknown>) => {
      calls.push(name);
      argsList.push(args);
      if (name === "owner_account_access") {
        return { data: options.owner ?? false, error: null };
      }
      if (name === "can_delete_account") {
        return {
          data: options.canDelete ?? options.owner ?? false,
          error: null,
        };
      }
      if (name === "manage_supervisor" || name === "edit_personnel") {
        return { data: true, error: null };
      }
      if (name === "owner_prepare_account_deletion") {
        return { data: options.prepared ?? true, error: null };
      }
      if (name === "actor_session_state") {
        return { data: "active", error: null };
      }
      if (name === "can_invite_user") {
        return { data: options.allowed ?? true, error: null };
      }
      if (name === "find_invite_target") {
        return { data: options.existing ?? null, error: null };
      }
      if (name === "finish_user_invite") {
        return { data: "assigned", error: null };
      }
      if (name === "create_manpower_agency") {
        return { data: agency, error: options.mutationError ?? null };
      }
      if (name === "transfer_personnel_agency") {
        return { data: { transferred: true }, error: null };
      }
      return { data: null, error: null };
    },
    auth: {
      admin: {
        deleteUser: async (id: string) => {
          calls.push("deleteUser:" + id);
          return {
            error: options.deletionError ? new Error("Deletion failed") : null,
          };
        },
        inviteUserByEmail: async (
          _email: string,
          args: { redirectTo: string },
        ) => {
          calls.push("inviteUserByEmail:" + args.redirectTo);
          return {
            data: { user: { id: target } },
            error: options.inviteError ?? null,
          };
        },
      },
    },
  };
  const scoped = {
    auth: {
      getUser: async () => ({
        data: {
          user: {
            id: actor,
            email: "manager@example.test",
            is_anonymous: false,
            email_confirmed_at: "2026-10-12T00:00:00Z",
          },
        },
        error: null,
      }),
      signInWithPassword: async () => {
        calls.push("signInWithPassword");
        return options.validPassword === false
          ? { data: { user: null }, error: new Error("bad password") }
          : { data: { user: { id: actor } }, error: null };
      },
      mfa: {
        getAuthenticatorAssuranceLevel: async () => ({
          data: {
            currentLevel: "aal1",
            nextLevel: options.mfaRequired ? "aal2" : "aal1",
          },
          error: null,
        }),
      },
    },
  };
  return {
    calls,
    argsList,
    ctx: {
      jwtClaims: { session_id: actor },
      supabase: scoped,
      supabaseAdmin: admin,
    } as unknown as SupabaseContext,
  };
}

Deno.test("email restrictions and rate limits do not masquerade as authorization outages", async () => {
  for (
    const [code, status] of [
      ["email_address_invalid", 422],
      ["email_address_not_authorized", 422],
      ["over_email_send_rate_limit", 429],
      ["over_request_rate_limit", 429],
    ] as const
  ) {
    const { ctx, calls } = context({
      inviteError: {
        code,
        status: code === "email_address_invalid" ? 400 : status,
      },
    });
    const response = await manageUsers(request(body), ctx);
    check(response.status === status, "incorrect invitation failure status");
    check(
      (await response.json()).code.startsWith("invitation_"),
      "missing specific error",
    );
    check(
      !calls.includes("finish_user_invite"),
      "failed invitation assigned access",
    );
  }
});

Deno.test("account deletion requires scoped permission, password, MFA and SQL authorization", async () => {
  for (
    const cfg of [
      { owner: false },
      { owner: true, validPassword: false },
      { owner: true, mfaRequired: true },
      { owner: true, prepared: false },
    ]
  ) {
    const { ctx, calls } = context(cfg);
    const result = await manageUsers(
      request({
        ...body,
        action: "delete_account",
        user_id: target,
        confirmation: "DELETE",
      }),
      ctx,
    );
    check(
      result.status === 401 || result.status === 403,
      "unauthorized deletion accepted",
    );
    check(
      !calls.some((c) => c.startsWith("deleteUser:")),
      "Auth deletion bypassed a safety gate",
    );
  }
});

Deno.test("Supervisor deletion uses database target scope without requiring Admin", async () => {
  const { ctx, calls } = context({ owner: false, canDelete: true });
  const response = await manageUsers(
    request({
      ...body,
      action: "delete_account",
      user_id: target,
      confirmation: "DELETE",
    }),
    ctx,
  );
  check(
    response.status === 200 && calls.includes("deleteUser:" + target),
    "authorized Personnel deletion denied",
  );
});

Deno.test("ordinary Supervisors cannot edit Supervisor access", async () => {
  const { ctx, calls } = context({ owner: false });
  const response = await manageUsers(
    request({
      ...body,
      action: "manage_supervisor",
      user_id: target,
      site_ids: [site],
      is_active: true,
    }),
    ctx,
  );
  check(
    response.status === 403 && !calls.includes("manage_supervisor"),
    "Supervisor edited a Supervisor",
  );
});

Deno.test("Admin Supervisor editing binds identity, scope, name and session after confirmation", async () => {
  const { ctx, calls, argsList } = context({ owner: true });
  const response = await manageUsers(
    request({
      ...body,
      action: "manage_supervisor",
      user_id: target,
      site_ids: [site],
      is_active: false,
      p_actor: target,
    }),
    ctx,
  );
  check(
    response.status === 200 && calls.includes("signInWithPassword"),
    "confirmation missing",
  );
  const args = argsList.at(-1)!;
  check(
    args.p_actor === actor && args.p_session === actor &&
      args.p_target === target && args.p_active === false,
    "untrusted scope accepted",
  );
});
Deno.test("authorized deletion binds the target, verified owner and original session before Auth deletion", async () => {
  const { ctx, calls, argsList } = context({ owner: true });
  const result = await manageUsers(
    request({
      ...body,
      action: "delete_account",
      user_id: target,
      confirmation: "DELETE",
      p_actor: target,
      p_session: target,
    }),
    ctx,
  );
  check(
    result.status === 200 && (await result.json()).deleted === true,
    "deletion failed",
  );
  const args = argsList.at(-1)!;
  check(
    args.p_actor === actor && args.p_session === actor &&
      args.p_target === target,
    "caller controlled deletion authority",
  );
  check(
    calls.at(-1) === "deleteUser:" + target,
    "Auth delete did not run last",
  );
  check(
    !JSON.stringify(argsList).includes(body.password),
    "owner password reached SQL",
  );
});
Deno.test("deletion requires explicit typed confirmation and cannot report an Auth failure as success", async () => {
  for (const confirmed of [false, true]) {
    const { ctx, calls } = context({ owner: true, deletionError: true });
    const result = await manageUsers(
      request({
        ...body,
        action: "delete_account",
        user_id: target,
        confirmation: confirmed ? "DELETE" : "",
      }),
      ctx,
    );
    check(result.status === (confirmed ? 409 : 400), "wrong deletion failure");
    check(
      calls.includes("deleteUser:" + target) === confirmed,
      "confirmation bypassed",
    );
  }
});

Deno.test("session expiry confirmed during agency mutation invalidates client access", async () => {
  const { ctx } = context({
    mutationError: { code: "42501", message: "Session expired" },
  });
  const r = await manageUsers(
    request({ ...body, action: "create_agency", name: "Test agency" }),
    ctx,
  );
  check(
    r.status === 403 && (await r.json()).code === "session_ended",
    "confirmed expiry was hidden",
  );
});

Deno.test("agency creation and transfer bind verified actor/session and never send invitations", async () => {
  for (const action of ["create_agency", "transfer"]) {
    const { ctx, calls, argsList } = context();
    const response = await manageUsers(
      request({
        ...body,
        action,
        name: "Test agency",
        user_id: target,
        destination_agency_id: agency,
        destination_site_id: site,
        reason: "New employer",
        p_actor: target,
        p_session: target,
      }),
      ctx,
    );
    check(response.status === 200, "agency operation failed");
    const args = argsList.at(-1)!;
    check(
      args.p_actor === actor && args.p_session === actor,
      "client chose actor/session",
    );
    check(
      !calls.some((c) => c.startsWith("inviteUserByEmail")),
      "agency transfer sent invitation",
    );
    check(
      !JSON.stringify(args).includes("test-password"),
      "password reached SQL",
    );
  }
});
Deno.test("agency transfer requires fresh account confirmation", async () => {
  const { ctx, calls } = context({ validPassword: false });
  const response = await manageUsers(
    request({
      ...body,
      action: "transfer",
      user_id: target,
      destination_agency_id: agency,
      destination_site_id: site,
      reason: "New employer",
    }),
    ctx,
  );
  check(
    response.status === 401 && !calls.includes("transfer_personnel_agency"),
    "transfer bypassed password",
  );
});

Deno.test("agency creation rejects bad names and unconfirmed passwords without a write", async () => {
  for (const name of ["", " ", "a".repeat(201), "Valid company"]) {
    const { ctx, calls } = context({ validPassword: false });
    const response = await manageUsers(
      request({ ...body, action: "create_agency", name }),
      ctx,
    );
    check(
      response.status === (name === "Valid company" ? 401 : 400),
      "wrong creation validation response",
    );
    check(
      !calls.includes("create_manpower_agency"),
      "unconfirmed creation reached database",
    );
  }
});

Deno.test("agency creation reports current Company-Wide authority without leaking SQL details", async () => {
  const { ctx } = context({
    mutationError: { code: "42501", message: "Agency creation not authorized" },
  });
  const response = await manageUsers(
    request({ ...body, action: "create_agency", name: "New company" }),
    ctx,
  );
  const result = await response.json();
  check(
    response.status === 403 && result.code === "authorization_changed",
    "revocation must invalidate protected actions",
  );
  check(
    result.message.includes("Admin or Company-Wide Supervisor"),
    "creation authority is mislabeled",
  );
  check(!result.message.includes("SQL"), "database details leaked");
});

Deno.test("scope denial happens before reauthentication or invitation email", async () => {
  const { ctx, calls } = context({ allowed: false });
  const response = await manageUsers(request(body), ctx);
  check(response.status === 403, "wrong status");
  check(
    calls.join(",") === "actor_session_state,can_invite_user",
    "invitation or password attempted before scope check",
  );
});

Deno.test("configured MFA cannot be bypassed by password confirmation", async () => {
  const { ctx, calls } = context({ mfaRequired: true });
  const response = await manageUsers(request(body), ctx);
  check(response.status === 403, "MFA assurance not enforced");
  check(
    !calls.includes("signInWithPassword") &&
      !calls.includes("finish_user_invite"),
    "MFA bypass",
  );
});

Deno.test("wrong account password cannot invite anyone", async () => {
  const { ctx, calls } = context({ validPassword: false });
  const response = await manageUsers(request(body), ctx);
  check(response.status === 401, "wrong status");
  check(
    !calls.some((call) => call.startsWith("inviteUserByEmail")),
    "email sent",
  );
  check(!calls.includes("finish_user_invite"), "role assigned");
});

Deno.test("new invite sends callback and assigns its server role", async () => {
  const { ctx, calls } = context();
  const response = await manageUsers(request(body), ctx);
  check(response.status === 200, "wrong status");
  check(
    calls.includes("inviteUserByEmail:janitra://auth-callback/"),
    "wrong callback",
  );
  check(calls.includes("finish_user_invite"), "role not assigned");
  check(
    (await response.json()).invitation_sent === true,
    "result not marked sent",
  );
});

Deno.test("existing account is assigned without another invitation email", async () => {
  const { ctx, calls } = context({ existing: target });
  const response = await manageUsers(request(body), ctx);
  check(response.status === 200, "wrong status");
  check(
    !calls.some((call) => call.startsWith("inviteUserByEmail")),
    "duplicate email sent",
  );
  check(calls.includes("finish_user_invite"), "existing account not assigned");
});

Deno.test("suspension requires password confirmation", async () => {
  const { ctx, calls } = context({ validPassword: false });
  const response = await manageUsers(
    request({
      action: "set_active",
      agency_id: agency,
      site_id: site,
      user_id: target,
      is_active: false,
      password: "wrong",
    }),
    ctx,
  );
  check(response.status === 401, "wrong status");
  check(!calls.includes("set_personnel_access"), "suspension reached database");
});
