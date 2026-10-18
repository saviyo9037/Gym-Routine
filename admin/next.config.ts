import type { NextConfig } from "next";

const isDev = process.env.NODE_ENV === "development";

/** Supabase origin (HTTPS + realtime WSS) allowed for API calls, images and media. */
function supabaseSources(): { http: string; ws: string } {
  try {
    const u = new URL(process.env.NEXT_PUBLIC_SUPABASE_URL ?? "");
    return { http: u.origin, ws: `wss://${u.host}` };
  } catch {
    return { http: "", ws: "" };
  }
}

/**
 * Content-Security-Policy. Next.js injects small inline bootstrap scripts, so
 * script-src needs 'unsafe-inline' unless a per-request nonce is used (a
 * possible future hardening). The app renders no user HTML (no
 * dangerouslySetInnerHTML; a test enforces that); everything else is locked down.
 */
export function contentSecurityPolicy(): string {
  const { http, ws } = supabaseSources();
  const directives = [
    "default-src 'self'",
    `script-src 'self' 'unsafe-inline'${isDev ? " 'unsafe-eval'" : ""}`,
    "style-src 'self' 'unsafe-inline'",
    `img-src 'self' data: blob: ${http}`.trim(),
    `media-src 'self' blob: ${http}`.trim(),
    `connect-src 'self' ${http} ${isDev ? "ws://localhost:*" : ws}`.replace(/\s+/g, " ").trim(),
    "font-src 'self' data:",
    "object-src 'none'",
    "base-uri 'self'",
    "form-action 'self'",
    "frame-ancestors 'none'",
  ];
  return directives.join("; ");
}

const config: NextConfig = {
  poweredByHeader: false,
  experimental: {
    // Media uploads go through a server action; keep in sync with MAX_VIDEO_BYTES.
    serverActions: { bodySizeLimit: "55mb" },
  },
  async headers() {
    return [
      {
        source: "/:path*",
        headers: [
          { key: "X-Frame-Options", value: "DENY" },
          { key: "X-Content-Type-Options", value: "nosniff" },
          { key: "Referrer-Policy", value: "same-origin" },
          { key: "Content-Security-Policy", value: contentSecurityPolicy() },
          { key: "Strict-Transport-Security", value: "max-age=63072000; includeSubDomains" },
          { key: "Permissions-Policy", value: "camera=(), microphone=(), geolocation=(), payment=()" },
          { key: "Cross-Origin-Opener-Policy", value: "same-origin" },
        ],
      },
    ];
  },
};
export default config;
