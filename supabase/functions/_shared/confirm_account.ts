import type { SupabaseContext } from "@supabase/server";

export async function confirmAccount(
  request: Request,
  ctx: SupabaseContext,
  caller: { id: string; email: string },
  password: unknown,
): Promise<Response | null> {
  const fail = (message: string, status: number) =>
    Response.json({ message }, { status });
  if (typeof password !== "string" || password.length === 0) {
    return fail("Enter your account password to continue.", 400);
  }
  const jwt = request.headers.get("authorization")?.match(/^Bearer (.+)$/i)
    ?.[1];
  if (!jwt) return fail("Sign in again to continue.", 401);
  // Read assurance for the original request, before password login creates an AAL1 session.
  const { data: assurance, error: assuranceError } = await ctx.supabase.auth.mfa
    .getAuthenticatorAssuranceLevel(jwt);
  if (assuranceError || !assurance?.currentLevel) {
    return fail("Could not confirm your account security. Sign in again.", 401);
  }
  if (assurance.nextLevel === "aal2" && assurance.currentLevel !== "aal2") {
    return fail(
      "Complete your account's two-step verification before continuing.",
      403,
    );
  }
  const { data, error } = await ctx.supabase.auth.signInWithPassword({
    email: caller.email,
    password,
  });
  return error || data.user?.id !== caller.id
    ? fail("Password confirmation failed.", 401)
    : null;
}
