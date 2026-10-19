import { type SupabaseContext, withSupabase } from "@supabase/server";
import { identityDigest, validUsername } from "../_shared/identity_security.ts";

const fail = (status = 401) =>
  Response.json({
    message: status === 429
      ? "Please wait before trying again."
      : "Could not sign in or complete account setup. Check your credentials or contact your Supervisor.",
  }, { status, headers: { "cache-control": "no-store" } });
export async function personnelAuth(
  request: Request,
  ctx: SupabaseContext,
  pepper = Deno.env.get("JANITRA_IDENTITY_PEPPER") ?? "",
): Promise<Response> {
  if (request.method !== "POST") return fail(405);
  if (!/^[0-9a-f]{64}$/i.test(pepper)) return fail(503);
  let body;
  try {
    const raw = await request.text();
    if (raw.length > 8192) return fail(413);
    body = JSON.parse(raw);
  } catch {
    return fail(400);
  }
  if (
    !body || !["login", "redeem"].includes(body.action) ||
    typeof body.identifier !== "string" || body.identifier.length > 320
  ) return fail(400);
  const identifier = body.identifier.trim().toLowerCase();
  const command = (action: string, data: Record<string, unknown>) =>
    ctx.supabaseAdmin.rpc("personnel_identity_command", {
      p_actor: null,
      p_session: null,
      p_action: action,
      p_data: data,
    });
  for (
    const [kind, value] of [["global", "all"], [
      body.action === "login" ? "identifier" : "grant",
      body.action === "login" ? identifier : String(body.code ?? ""),
    ]]
  ) {
    const { data, error } = await command("rate", {
      kind,
      digest: await identityDigest(pepper, `rate-${kind}`, value),
    });
    if (error) return fail(503);
    if (data?.allowed !== true) return fail(429);
  }
  if (body.action === "login") {
    if (typeof body.password !== "string" || body.password.length > 256) {
      return fail();
    }
    const { data: lookup, error: lookupError } = await command("login_lookup", {
      identifier,
    });
    if (lookupError) return fail(503);
    const found = validUsername(identifier) &&
      typeof lookup?.login_email === "string";
    const { data, error } = await ctx.supabase.auth.signInWithPassword({
      email: found
        ? lookup.login_email
        : "unregistered@personnel.janitra.invalid",
      password: body.password,
    });
    if (error || !found || !data.session || data.user?.id !== lookup.user_id) {
      return fail();
    }
    let sessionId;
    try {
      sessionId = JSON.parse(
        atob(
          data.session.access_token.split(".")[1].replaceAll("-", "+")
            .replaceAll("_", "/"),
        ),
      ).session_id;
    } catch {
      return fail();
    }
    const { data: state, error: stateError } = await ctx.supabaseAdmin.rpc(
      "actor_session_state",
      { p_actor: data.user.id, p_session: sessionId },
    );
    if (stateError || !["active", "unassigned"].includes(String(state))) {
      await ctx.supabase.auth.signOut().catch(() => {});
      return fail(stateError ? 503 : 401);
    }
    return Response.json({ session: data.session }, {
      headers: { "cache-control": "no-store" },
    });
  }
  if (
    typeof body.code !== "string" || !/^[a-zA-Z0-9_-]{43}$/.test(body.code) ||
    typeof body.password !== "string" || body.password.length < 12 ||
    body.password.length > 256
  ) return fail();
  const { data: claim, error: claimError } = await command("claim_grant", {
    identifier,
    digest: await identityDigest(pepper, "grant", body.code),
  });
  if (claimError || !claim?.claim_id || !claim?.user_id) return fail();
  const { error: passwordError } = await ctx.supabaseAdmin.auth.admin
    .updateUserById(claim.user_id, {
      password: body.password,
      ...(claim.confirm_email === true ? { email_confirm: true } : {}),
    });
  if (passwordError) {
    // A definite Auth validation rejection made no password change; ambiguous failures stay sealed.
    if (passwordError.status === 422) {
      await command("reject_grant", { claim_id: claim.claim_id });
    }
    return fail();
  }
  const { data: finished, error: finishError } = await command("finish_grant", {
    claim_id: claim.claim_id,
  });
  if (finishError || finished?.completed !== true) return fail();
  return Response.json({ completed: true }, {
    headers: { "cache-control": "no-store" },
  });
}
export default { fetch: withSupabase({ auth: "none" }, personnelAuth) };
