import { createServerClient } from "@supabase/ssr";
import { NextResponse, type NextRequest } from "next/server";
import { envProblems } from "@/lib/env-check";

/**
 * Refreshes the Supabase session cookie and bounces unauthenticated visitors to /login.
 * This is only a convenience: authorisation (admin role + aal2) is enforced by
 * requireAdmin() in every page and server action, not here.
 */
export async function proxy(request: NextRequest) {
  let response = NextResponse.next({ request });
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const anon = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
  const problems = envProblems(url, anon);
  if (problems.length > 0) {
    // Misconfiguration must produce a readable message, never a stack trace.
    const body =
      "Admin panel is not configured:\n- " +
      problems.join("\n- ") +
      "\n\nEdit admin/.env.local (see .env.example) and restart the dev server.";
    return new NextResponse(body, {
      status: 500,
      headers: { "content-type": "text/plain; charset=utf-8" },
    });
  }

  const supabase = createServerClient(url as string, anon as string, {
    cookies: {
      getAll: () => request.cookies.getAll(),
      setAll: (list) => {
        for (const { name, value } of list) request.cookies.set(name, value);
        response = NextResponse.next({ request });
        for (const { name, value, options } of list) response.cookies.set(name, value, options);
      },
    },
  });
  const { data } = await supabase.auth.getUser();
  const path = request.nextUrl.pathname;
  if (!data.user && path !== "/login") {
    return NextResponse.redirect(new URL("/login", request.url));
  }
  return response;
}

export const config = {
  matcher: ["/((?!_next/static|_next/image|favicon.ico).*)"],
};
