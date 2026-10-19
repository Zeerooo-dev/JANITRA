import { type SupabaseContext, withSupabase } from "@supabase/server";
import { confirmAccount } from "../_shared/confirm_account.ts";
import { pinDigest } from "../manage-pins/index.ts";

const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const actions = [
  "activity_save",
  "shift_save",
  "rule_save",
  "activity_delete",
  "shift_delete",
  "rule_delete",
  "exception_save",
  "policy_save",
  "submit",
  "verify",
  "approve",
  "reject",
  "override",
  "report",
  "read_notifications",
];
const reply = (message: string, status: number) =>
  Response.json({ message }, { status });

export async function workflow(
  request: Request,
  ctx: SupabaseContext,
  pepper = Deno.env.get("JANITRA_PIN_PEPPER") ?? "",
): Promise<Response> {
  if (request.method !== "POST") return reply("Method not allowed.", 405);
  let body;
  try {
    const text = await request.text();
    if (text.length > 16384) return reply("Request too large.", 413);
    body = JSON.parse(text);
  } catch {
    return reply("Invalid request.", 400);
  }
  if (
    !body || typeof body !== "object" || !actions.includes(body.action) ||
    !uuid.test(String(body.request_id))
  ) return reply("Invalid work action.", 400);
  if (
    ["activity_delete", "shift_delete", "rule_delete"].includes(body.action) &&
    (!uuid.test(String(body.id)) || !uuid.test(String(body.agency_id)) ||
      !uuid.test(String(body.site_id)))
  ) {
    return reply("Choose a valid activity, shift or cleaning schedule.", 400);
  }
  const { data, error } = await ctx.supabase.auth.getUser();
  const user = data.user;
  const session = ctx.jwtClaims?.session_id;
  if (
    error || !user?.id || !user.email || !user.email_confirmed_at ||
    user.is_anonymous || !uuid.test(String(session))
  ) return reply("Sign in to a verified account again.", 401);
  const jwt = request.headers.get("authorization")?.match(/^Bearer (.+)$/i)
    ?.[1];
  const { data: assurance, error: aalError } = await ctx.supabase.auth.mfa
    .getAuthenticatorAssuranceLevel(jwt);
  if (aalError || !assurance?.currentLevel) {
    return reply("Could not confirm account security.", 401);
  }
  if (
    user.factors?.some((f) => f.status === "verified") &&
    assurance.currentLevel !== "aal2"
  ) {
    return reply(
      "Complete two-step verification by refreshing workplace access.",
      403,
    );
  }
  const allowedFields = [
    "checklist_items",
    "checklist_results",
    "checklist_version",
    "request_id",
    "agency_id",
    "site_id",
    "task_id",
    "version",
    "remarks",
    "claimed_at",
    "reason",
    "deadline",
    "id",
    "user_id",
    "name",
    "location",
    "instructions",
    "is_active",
    "weekdays",
    "starts_on",
    "ends_on",
    "segments",
    "activity_id",
    "shift_id",
    "at_minute",
    "until_minute",
    "interval_minutes",
    "rule_id",
    "work_date",
    "cancelled",
    "substitute_id",
    "weekday",
    "hours",
    "from_date",
    "to_date",
    "format",
    "supervisor_id",
    "status",
  ];
  const payload: Record<string, unknown> = Object.fromEntries(
    allowedFields.filter((k) => Object.hasOwn(body, k)).map(
      (k) => [k, body[k]],
    ),
  );
  if (["submit", "verify"].includes(body.action)) {
    if (
      !uuid.test(String(body.task_id)) || typeof body.pin !== "string" ||
      !/^[0-9]{4}$/.test(body.pin)
    ) return reply("Enter exactly four PIN digits for this task.", 400);
    if (!/^[0-9a-f]{64}$/i.test(pepper)) {
      return reply("PIN protection is unavailable.", 503);
    }
    payload.digest = await pinDigest(
      pepper,
      body.action === "submit" ? "employee" : "supervisor",
      user.id,
      body.pin,
    );
  }
  if (body.action === "override") {
    const confirmation = await confirmAccount(request, ctx, {
      id: user.id,
      email: user.email,
    }, body.password);
    if (confirmation) return confirmation;
    payload._reauth = true;
  }
  const result = await ctx.supabaseAdmin.rpc("workflow_command", {
    p_actor: user.id,
    p_session: session,
    p_action: body.action,
    p_data: payload,
  });
  if (result.error?.code === "42501") {
    return Response.json({
      message: "Your work access or session changed. Refresh workplace access.",
      code: result.error.message === "Session expired"
        ? "session_ended"
        : "authorization_changed",
    }, { status: 403 });
  }
  if (result.error) {
    return reply(
      result.error.code === "42501"
        ? "Your work access or session changed. Refresh workplace access."
        : result.error.code === "23505"
        ? "This request conflicts with an existing operation. Refresh the task."
        : result.error.code?.startsWith("22") ||
            result.error.code === "23514" || result.error.code === "23503" ||
            result.error.code === "23502"
        ? "Check the selected people, workplace, dates and times."
        : result.error.code === "P0001"
        ? result.error.message
        : "Could not save work. Please retry.",
      result.error.code === "42501"
        ? 403
        : result.error.code === "23505"
        ? 409
        : 400,
    );
  }
  if (!result.data || typeof result.data !== "object") {
    return reply("No server confirmation received.", 502);
  }
  return result.data.ok === false
    ? Response.json(result.data, { status: 409 })
    : Response.json(result.data);
}
export default { fetch: withSupabase({ auth: "user" }, workflow) };
