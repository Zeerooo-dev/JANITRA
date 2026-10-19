import type { SupabaseContext } from "@supabase/server";
import { confirmAccount } from "./confirm_account.ts";
import {
  identityDigest,
  setupCode,
  validUsername,
} from "./identity_security.ts";

export async function manageIdentity(
  request: Request,
  ctx: SupabaseContext,
  caller: { id: string; email: string },
  body: Record<string, unknown>,
  pepper = Deno.env.get("JANITRA_IDENTITY_PEPPER") ?? "",
): Promise<Response> {
  const fail = (message: string, status: number) =>
    Response.json({ message }, {
      status,
      headers: { "cache-control": "no-store" },
    });
  if (!/^[0-9a-f]{64}$/i.test(pepper)) {
    return fail("Account setup protection is not configured.", 503);
  }
  const username = String(body.username ?? "").trim().toLowerCase();
  const uuid =
    /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
  if (
    !(uuid.test(String(body.site_id)) ||
      (body.agency_id == null && body.site_id == null)) ||
    (body.action === "create_personnel" &&
      (!validUsername(username) || !uuid.test(String(body.request_id)) ||
        typeof body.full_name !== "string" ||
        body.full_name.trim().length < 1 || body.full_name.trim().length > 200))
  ) return fail("Check the username, name and workplace.", 400);
  const email = String(body.email ?? "").trim().toLowerCase();
  if (
    email && (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) || email.length > 320)
  ) return fail("Check the optional email address.", 400);
  const confirmation = await confirmAccount(
    request,
    ctx,
    caller,
    body.password,
  );
  if (confirmation) return confirmation;
  const admin = ctx.supabaseAdmin;
  const command = (action: string, data: Record<string, unknown>) =>
    admin.rpc("personnel_identity_command", {
      p_actor: caller.id,
      p_session: ctx.jwtClaims?.session_id,
      p_action: action,
      p_data: { agency_id: body.agency_id, site_id: body.site_id, ...data },
    });
  let target = String(body.user_id ?? "");
  if (body.action === "create_personnel") {
    const { data: reserved, error } = await command("reserve", {
      request_id: body.request_id,
      username,
      full_name: (body.full_name as string).trim(),
      email,
    });
    if (error || !reserved?.operation_id) {
      return fail(
        "Could not reserve this account. Check username and workplace access.",
        409,
      );
    }
    target = reserved.existing_user_id ?? "";
    if (!target) {
      const { data: created, error: createError } = await admin.auth.admin
        .createUser({
          email: reserved.login_email,
          password: setupCode(),
          email_confirm: true,
          app_metadata: { janitra_provisioning_id: reserved.operation_id },
          user_metadata: { username },
        });
      if (createError || !created.user?.id) {
        return fail(
          "Account creation is unfinished. Retry the same request; no workplace access was activated.",
          502,
        );
      }
      target = created.user.id;
    }
    const { error: finishError } = await command("finish_provision", {
      request_id: body.request_id,
      user_id: target,
    });
    if (finishError) {
      return fail(
        "Account creation is unfinished. Retry the same request.",
        503,
      );
    }
  } else if (
    !uuid.test(target) ||
    !["setup", "recovery"].includes(String(body.purpose)) ||
    (body.purpose === "recovery" &&
      (typeof body.reason !== "string" || body.reason.trim().length < 10))
  ) return fail("Choose Personnel and explain the recovery request.", 400);
  const code = setupCode();
  const purpose = body.action === "create_personnel"
    ? "setup"
    : String(body.purpose);
  const { data: grant, error: grantError } = await command("issue_grant", {
    user_id: target,
    purpose,
    reason: body.reason,
    digest: await identityDigest(pepper, "grant", code),
  });
  if (grantError || !grant?.expires_at) {
    return fail(
      "Could not issue a code. Check the person's status and your full account-management scope.",
      403,
    );
  }
  return Response.json({
    user_id: target,
    identifier: grant.identifier,
    setup_code: code,
    expires_at: grant.expires_at,
    purpose,
  }, { headers: { "cache-control": "no-store" } });
}
