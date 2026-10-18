import "server-only";
import { headers } from "next/headers";

export interface RequestOriginInfo {
  origin?: string | null;
  host?: string | null;
  forwardedHost?: string | null;
  fetchSite?: string | null;
}

/**
 * Defence in depth on top of Next's own server-action origin check and the
 * SameSite=Lax session cookies. A state-changing request is refused when the
 * browser says it came from another site:
 *  - `Sec-Fetch-Site: cross-site` (or same-site from a sibling subdomain), or
 *  - an `Origin` header (including the literal "null") whose host is not ours.
 * Requests without Origin/Sec-Fetch-Site (non-browser clients) carry no
 * ambient cookies, so they are not a CSRF vector and are allowed here; the
 * guard (session + MFA + role) still applies.
 */
export function isSameOrigin(info: RequestOriginInfo): boolean {
  const site = info.fetchSite?.toLowerCase();
  if (site === "cross-site" || site === "same-site") return false;
  const origin = info.origin;
  if (origin == null || origin === "") return true;
  let originHost: string;
  try {
    originHost = new URL(origin).host.toLowerCase();
  } catch {
    return false; // "null" or garbage
  }
  const allowed = [info.forwardedHost, info.host]
    .filter((h): h is string => !!h)
    .map((h) => h.split(",")[0]!.trim().toLowerCase());
  return allowed.includes(originHost);
}

/** Reads the current request's headers and applies [isSameOrigin]. */
export async function requestIsSameOrigin(): Promise<boolean> {
  const h = await headers();
  return isSameOrigin({
    origin: h.get("origin"),
    host: h.get("host"),
    forwardedHost: h.get("x-forwarded-host"),
    fetchSite: h.get("sec-fetch-site"),
  });
}
