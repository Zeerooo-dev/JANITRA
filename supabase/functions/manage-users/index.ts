import { type SupabaseContext, withSupabase } from "@supabase/server";
import { confirmAccount } from "../_shared/confirm_account.ts";
import { currentSession } from "../_shared/current_session.ts";
import { manageIdentity } from "../_shared/manage_identity.ts";

type RequestBody = {
  action?: unknown;
  agency_id?: unknown;
  site_id?: unknown;
  role?: unknown;
  email?: unknown;
  full_name?: unknown;
  password?: unknown;
  user_id?: unknown;
  is_active?: unknown;
  name?: unknown;
  destination_agency_id?: unknown;
  destination_site_id?: unknown;
  reason?: unknown;
  username?: unknown;
  request_id?: unknown;
  purpose?: unknown;
  confirmation?: unknown;
  site_ids?: unknown;
};

const redirectTo = "janitra://auth-callback/";
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const reply = (message: string, status: number, code?: string) =>
  Response.json({ message, ...(code ? { code } : {}) }, { status });

export async function manageUsers(
  request: Request,
  ctx: SupabaseContext,
): Promise<Response> {
  if (request.method !== "POST") return reply("Method not allowed.", 405);
  let body: RequestBody;
  try {
    body = await request.json();
  } catch {
    return reply("Invalid request.", 400);
  }
  if (
    !body || typeof body !== "object" || Array.isArray(body) ||
    (body.agency_id != null && !uuid.test(String(body.agency_id)))
  ) {
    return reply("Choose a valid manpower company.", 400);
  }
  const { data: identity, error: identityError } = await ctx.supabase.auth
    .getUser();
  const caller = identity.user;
  if (
    identityError || !caller || caller.is_anonymous || !caller.email ||
    !caller.email_confirmed_at
  ) {
    return reply("Sign in again to manage users.", 401);
  }
  const actor = caller.id;
  const ended = await currentSession(ctx, actor);
  if (ended) return ended;
  const agency = (body.agency_id ?? null) as string | null;
  const admin = ctx.supabaseAdmin;
  if (agency === null) {
    if (
      ![
        "list",
        "invite",
        "create_personnel",
        "issue_account_code",
        "edit_personnel",
        "delete_account",
        "create_agency",
      ].includes(String(body.action))
    ) {
      return reply("Choose a valid manpower company.", 400);
    }
    const { data: allowed, error } = await admin.rpc("owner_account_access", {
      p_actor: actor,
      p_session: ctx.jwtClaims?.session_id,
    });
    if (error || allowed !== true) {
      return reply("Only Admin can manage unassigned accounts.", 403);
    }
  }

  if (body.action === "assign_personnel") {
    if (!uuid.test(String(body.user_id)) || !uuid.test(String(body.site_id))) {
      return reply("Choose the Personnel account and workplace.", 400);
    }
    const confirmation = await confirmAccount(request, ctx, {
      id: actor,
      email: caller.email,
    }, body.password);
    if (confirmation) return confirmation;
    const { data, error } = await admin.rpc("assign_unassigned_personnel", {
      p_actor: actor,
      p_session: ctx.jwtClaims?.session_id,
      p_target: body.user_id,
      p_agency: agency,
      p_site: body.site_id,
    });
    return error || data !== true
      ? reply(
        "Only Admin can assign an unassigned Personnel account. Check the workplace and password setup status.",
        403,
      )
      : Response.json({ updated: true });
  }

  if (body.action === "delete_account") {
    if (!uuid.test(String(body.user_id)) || body.confirmation !== "DELETE") {
      return reply("Confirm the account and type DELETE.", 400);
    }
    const { data: allowed, error: permissionError } = await admin.rpc(
      "can_delete_account",
      {
        p_actor: actor,
        p_session: ctx.jwtClaims?.session_id,
        p_target: body.user_id,
      },
    );
    if (permissionError || allowed !== true) {
      return reply("You cannot permanently delete this account.", 403);
    }
    const confirmation = await confirmAccount(request, ctx, {
      id: actor,
      email: caller.email,
    }, body.password);
    if (confirmation) return confirmation;
    const { data: prepared, error: prepareError } = await admin.rpc(
      "owner_prepare_account_deletion",
      {
        p_actor: actor,
        p_session: ctx.jwtClaims?.session_id,
        p_target: body.user_id,
        p_confirmation: body.confirmation,
      },
    );
    if (prepareError || prepared !== true) {
      return reply(
        "This account cannot be deleted. Refresh the team and check your access.",
        403,
      );
    }
    const { error: deleteError } = await admin.auth.admin.deleteUser(
      body.user_id as string,
    );
    if (deleteError) {
      return reply(
        "Deletion could not be confirmed. Refresh the team and retry if the account remains.",
        409,
      );
    }
    return Response.json({ deleted: true });
  }

  if (body.action === "manage_supervisor") {
    if (
      !uuid.test(String(body.user_id)) || typeof body.is_active !== "boolean" ||
      typeof body.full_name !== "string" || !body.full_name.trim() ||
      body.full_name.trim().length > 200 ||
      (body.site_ids !== null &&
        (!Array.isArray(body.site_ids) || body.site_ids.length < 1 ||
          body.site_ids.length > 200 || body.site_ids.some((s) =>
            typeof s !== "string" || !uuid.test(s)
          )))
    ) {
      return reply("Check the Supervisor and selected workplaces.", 400);
    }
    const { data: allowed, error } = await admin.rpc("owner_account_access", {
      p_actor: actor,
      p_session: ctx.jwtClaims?.session_id,
    });
    if (error || allowed !== true) {
      return reply("Only Admins can manage Supervisors.", 403);
    }
    const confirmation = await confirmAccount(request, ctx, {
      id: actor,
      email: caller.email,
    }, body.password);
    if (confirmation) return confirmation;
    const { data, error: changeError } = await admin.rpc("manage_supervisor", {
      p_actor: actor,
      p_session: ctx.jwtClaims?.session_id,
      p_target: body.user_id,
      p_agency: agency,
      p_sites: body.site_ids,
      p_active: body.is_active,
      p_name: body.full_name.trim(),
    });
    return changeError || data !== true
      ? reply(
        "Supervisor access could not be changed. Refresh and check your authority.",
        403,
      )
      : Response.json({ updated: true });
  }

  if (body.action === "edit_personnel") {
    if (
      !uuid.test(String(body.user_id)) || typeof body.full_name !== "string" ||
      !body.full_name.trim() || body.full_name.trim().length > 200
    ) return reply("Check the Personnel name.", 400);
    const confirmation = await confirmAccount(request, ctx, {
      id: actor,
      email: caller.email,
    }, body.password);
    if (confirmation) return confirmation;
    const { data, error } = await admin.rpc("edit_personnel", {
      p_actor: actor,
      p_session: ctx.jwtClaims?.session_id,
      p_target: body.user_id,
      p_name: body.full_name.trim(),
    });
    return error || data !== true
      ? reply("You cannot edit this Personnel account.", 403)
      : Response.json({ updated: true });
  }

  if (
    ["create_personnel", "issue_account_code"].includes(String(body.action))
  ) {
    return manageIdentity(
      request,
      ctx,
      { id: actor, email: caller.email },
      body,
    );
  }

  if (body.action === "create_agency") {
    const name = typeof body.name === "string" ? body.name.trim() : "";
    if (name.length < 1 || name.length > 200) {
      return reply("Enter the manpower agency name.", 400);
    }
    const confirmation = await confirmAccount(request, ctx, {
      id: actor,
      email: caller.email,
    }, body.password);
    if (confirmation) return confirmation;
    const { data, error } = await admin.rpc("create_manpower_agency", {
      p_actor: actor,
      p_session: ctx.jwtClaims?.session_id,
      p_name: name,
    });
    return error
      ? reply(
        "Only an Admin or Company-Wide Supervisor with a current session can add a manpower agency.",
        403,
        error.code === "42501"
          ? (error.message === "Session expired"
            ? "session_ended"
            : "authorization_changed")
          : undefined,
      )
      : Response.json({ agency_id: data });
  }
  if (body.action === "transfer") {
    const reason = typeof body.reason === "string" ? body.reason.trim() : "";
    if (
      !uuid.test(String(body.user_id)) ||
      !uuid.test(String(body.destination_agency_id)) ||
      !uuid.test(String(body.destination_site_id)) || reason.length < 1 ||
      reason.length > 2000
    ) {
      return reply(
        "Choose the destination agency/workplace and provide a transfer reason.",
        400,
      );
    }
    const confirmation = await confirmAccount(request, ctx, {
      id: actor,
      email: caller.email,
    }, body.password);
    if (confirmation) return confirmation;
    const { data, error } = await admin.rpc("transfer_personnel_agency", {
      p_actor: actor,
      p_session: ctx.jwtClaims?.session_id,
      p_user: body.user_id,
      p_from: agency,
      p_to: body.destination_agency_id,
      p_site: body.destination_site_id,
      p_reason: reason,
    });
    return error
      ? reply(
        "Transfer requires Supervisor authority over both agencies and an active Personnel assignment.",
        403,
        error.code === "42501"
          ? (error.message === "Session expired"
            ? "session_ended"
            : "authorization_changed")
          : undefined,
      )
      : Response.json(data);
  }

  if (body.action === "list") {
    const { data, error } = await admin.rpc("owner_list_accounts", {
      p_actor: actor,
      p_session: ctx.jwtClaims?.session_id,
    });
    return error
      ? reply("Could not load accounts.", 403)
      : Response.json({ users: data ?? [], permissions_version: 2 });
  }

  if (body.action === "invite") {
    const role = body.role;
    const site = body.site_id === null ? null : body.site_id;
    const email = String(body.email ?? "").trim().toLowerCase();
    const name = String(body.full_name ?? "").trim();
    const sites = role === "supervisor" ? (body.site_ids ?? null) : null;
    if (
      !["supervisor", "personnel"].includes(String(role)) ||
      (site !== null && (typeof site !== "string" || !uuid.test(site))) ||
      !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) || email.length > 320 ||
      name.length < 1 || name.length > 200 ||
      (sites !== null &&
        (!Array.isArray(sites) || sites.length < 1 || sites.length > 200 ||
          sites.some((s) => typeof s !== "string" || !uuid.test(s))))
    ) return reply("Check the name, email, role and workplace.", 400);
    for (const scope of (sites as string[] | null) ?? [site]) {
      const { data: allowed, error: scopeError } = await admin.rpc(
        "can_invite_user",
        {
          p_actor: actor,
          p_agency: agency,
          p_site: scope,
          p_role: role,
        },
      );
      if (scopeError || allowed !== true) {
        return reply("You cannot invite users for this scope.", 403);
      }
    }
    const confirmation = await confirmAccount(request, ctx, {
      id: actor,
      email: caller.email,
    }, body.password);
    if (confirmation) return confirmation;
    const { data: existing, error: lookupError } = await admin.rpc(
      "find_invite_target",
      {
        p_actor: actor,
        p_agency: agency,
        p_site: site,
        p_role: role,
        p_email: email,
      },
    );
    if (lookupError) return reply("Could not check this account.", 403);
    let target: string | null = existing;
    let sent = false;
    if (!target) {
      const { data: invited, error: inviteError } = await admin.auth.admin
        .inviteUserByEmail(email, {
          redirectTo,
        });
      if (inviteError || !invited.user?.id) {
        if (inviteError?.code === "email_address_invalid") {
          return reply(
            "The email service rejected this address. Check the email address or ask the administrator to check email delivery settings.",
            422,
            "invitation_email_invalid",
          );
        }
        if (inviteError?.code === "email_address_not_authorized") {
          return reply(
            "Email invitations are restricted by the email service. The project administrator must configure custom SMTP before inviting this address.",
            422,
            "invitation_email_restricted",
          );
        }
        if (
          inviteError?.code === "over_email_send_rate_limit" ||
          inviteError?.code === "over_request_rate_limit" ||
          inviteError?.status === 429
        ) {
          return reply(
            "The email invitation limit has been reached. Wait before trying again.",
            429,
            "invitation_rate_limited",
          );
        }
        console.error("Invitation delivery failed", {
          code: inviteError?.code ?? "missing_invited_user",
          status: inviteError?.status,
        });
        return reply("Could not send the invitation. Try again.", 502);
      }
      target = invited.user.id;
      sent = true;
    }
    const { data: outcome, error: finishError } = await admin.rpc(
      role === "supervisor" ? "finish_supervisor_invite" : "finish_user_invite",
      role === "supervisor"
        ? {
          p_actor: actor,
          p_session: ctx.jwtClaims?.session_id,
          p_target: target,
          p_email: email,
          p_agency: agency,
          p_sites: sites,
          p_name: name,
        }
        : {
          p_actor: actor,
          p_target: target,
          p_email: email,
          p_agency: agency,
          p_site: site,
          p_role: role,
          p_name: name,
        },
    );
    if (finishError) {
      return reply(
        sent
          ? "Invitation sent, but access could not be assigned. Retry the same email."
          : "Could not assign access. Retry the same email.",
        500,
      );
    }
    return Response.json({ result: outcome, invitation_sent: sent });
  }

  if (body.action === "set_active") {
    if (
      !uuid.test(String(body.user_id)) || !uuid.test(String(body.site_id)) ||
      typeof body.is_active !== "boolean"
    ) return reply("Choose a valid personnel assignment.", 400);
    const confirmation = await confirmAccount(request, ctx, {
      id: actor,
      email: caller.email,
    }, body.password);
    if (confirmation) return confirmation;
    const { error } = await admin.rpc("set_personnel_access", {
      p_actor: actor,
      p_target: body.user_id,
      p_agency: agency,
      p_site: body.site_id,
      p_active: body.is_active,
    });
    if (error) return reply("Could not change this personnel assignment.", 403);
    return Response.json({ updated: true });
  }
  return reply("Unknown action.", 400);
}

export default { fetch: withSupabase({ auth: "user" }, manageUsers) };
