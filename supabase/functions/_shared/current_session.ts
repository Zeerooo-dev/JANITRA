import type { SupabaseContext } from "@supabase/server";
export async function currentSession(
  ctx: SupabaseContext,
  actor: string,
): Promise<Response | null> {
  const session = ctx.jwtClaims?.session_id;
  if (typeof session !== "string") {
    return Response.json({
      message: "Sign in again to continue.",
      code: "session_ended",
    }, { status: 401 });
  }
  const { data, error } = await ctx.supabaseAdmin.rpc("actor_session_state", {
    p_actor: actor,
    p_session: session,
  });
  if (error) {
    return Response.json({
      message: "Could not verify access. Please retry when connected.",
      code: "verification_unavailable",
    }, { status: 503 });
  }
  return data !== "active"
    ? Response.json({
      message: "Your session or account access has ended. Sign in again.",
      code: data === "suspended" || data === "revoked"
        ? "authorization_changed"
        : "session_ended",
    }, { status: 401 })
    : null;
}
