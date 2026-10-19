import { type SupabaseContext, withSupabase } from "@supabase/server";
import { confirmAccount } from "../_shared/confirm_account.ts";
import { currentSession } from "../_shared/current_session.ts";

const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const reply = (message: string, status: number) =>
  Response.json({ message }, { status });

export async function pinDigest(
  secret: string,
  purpose: "employee" | "supervisor",
  userId: string,
  pin: string,
): Promise<string> {
  if (!/^[0-9a-f]{64}$/i.test(secret)) {
    throw new Error("PIN protection is not configured");
  }
  const bytes = Uint8Array.from(
    secret.match(/../g)!,
    (byte) => parseInt(byte, 16),
  );
  const key = await crypto.subtle.importKey(
    "raw",
    bytes,
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const digest = await crypto.subtle.sign(
    "HMAC",
    key,
    new TextEncoder().encode(`${purpose}:${userId.toLowerCase()}:${pin}`),
  );
  return Array.from(
    new Uint8Array(digest),
    (byte) => byte.toString(16).padStart(2, "0"),
  ).join("");
}

export async function managePins(
  request: Request,
  ctx: SupabaseContext,
  secret = Deno.env.get("JANITRA_PIN_PEPPER") ?? "",
): Promise<Response> {
  if (request.method !== "POST") return reply("Method not allowed.", 405);
  if (Number(request.headers.get("content-length")) > 4096) {
    return reply("Request too large.", 413);
  }
  let body;
  try {
    const text = await request.text();
    if (text.length > 4096) return reply("Request too large.", 413);
    body = JSON.parse(text);
  } catch {
    return reply("Invalid request.", 400);
  }
  if (
    !body || typeof body !== "object" ||
    !["status", "set"].includes(body.action) ||
    !["employee", "supervisor"].includes(body.kind) ||
    !uuid.test(String(body.agency_id)) ||
    !uuid.test(String(body.user_id)) ||
    (body.site_id !== null && !uuid.test(String(body.site_id)))
  ) {
    return reply("Choose a valid PIN account and workplace.", 400);
  }
  const { data: identity, error } = await ctx.supabase.auth.getUser();
  const caller = identity.user;
  if (
    error || !caller || caller.is_anonymous || !caller.email ||
    !caller.email_confirmed_at
  ) {
    return reply("Sign in to a verified account to manage PINs.", 401);
  }
  const ended = await currentSession(ctx, caller.id);
  if (ended) return ended;
  const args = {
    p_actor: caller.id,
    p_target: (body.user_id as string).toLowerCase(),
    p_kind: body.kind as "employee" | "supervisor",
    p_agency: body.agency_id,
    p_site: body.site_id,
  };
  if (body.action === "status") {
    const { data, error } = await ctx.supabaseAdmin.rpc("pin_status", args);
    return error
      ? reply("You cannot view this PIN account.", 403)
      : Response.json(data);
  }
  if (typeof body.pin !== "string" || !/^[0-9]{4}$/.test(body.pin)) {
    return reply("Enter exactly four digits for the new PIN.", 400);
  }
  const { data: allowed, error: scopeError } = await ctx.supabaseAdmin.rpc(
    "can_manage_pin",
    args,
  );
  if (scopeError || allowed !== true) {
    return reply(
      "You cannot reset this account's PIN within your workplace scope.",
      403,
    );
  }
  if (!/^[0-9a-f]{64}$/i.test(secret)) {
    return reply(
      "PIN protection is not configured. Contact your supervisor.",
      503,
    );
  }
  const confirmation = await confirmAccount(request, ctx, {
    id: caller.id,
    email: caller.email,
  }, body.password);
  if (confirmation) return confirmation;
  const digest = await pinDigest(secret, args.p_kind, args.p_target, body.pin);
  const { data, error: writeError } = await ctx.supabaseAdmin.rpc(
    "set_pin_credential",
    { ...args, p_digest: digest },
  );
  return writeError
    ? reply("Could not set the PIN. Refresh access and try again.", 403)
    : Response.json(data);
}

export default { fetch: withSupabase({ auth: "user" }, managePins) };
