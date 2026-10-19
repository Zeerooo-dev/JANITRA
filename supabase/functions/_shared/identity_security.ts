export const validUsername = (value: unknown): value is string =>
  typeof value === "string" && /^[a-z0-9][a-z0-9._-]{2,31}$/.test(value);

export function setupCode(): string {
  return btoa(
    String.fromCharCode(...crypto.getRandomValues(new Uint8Array(32))),
  )
    .replaceAll("+", "-").replaceAll("/", "_").replaceAll("=", "");
}
export async function identityDigest(
  pepper: string,
  purpose: string,
  value: string,
): Promise<string> {
  if (!/^[0-9a-f]{64}$/i.test(pepper)) {
    throw new Error("Identity protection unavailable");
  }
  const key = await crypto.subtle.importKey(
    "raw",
    new Uint8Array(pepper.match(/../g)!.map((x) => parseInt(x, 16))),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const digest = await crypto.subtle.sign(
    "HMAC",
    key,
    new TextEncoder().encode(`${purpose}/${value}`),
  );
  return Array.from(
    new Uint8Array(digest),
    (x) => x.toString(16).padStart(2, "0"),
  ).join("");
}
