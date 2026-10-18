import { LoginForm } from "./login-form";

export default function LoginPage() {
  return (
    <main className="mx-auto flex min-h-screen max-w-sm flex-col justify-center px-4">
      <h1 className="mb-1 text-2xl font-semibold">
        RepTrack <span className="text-accent">Admin</span>
      </h1>
      <p className="mb-6 text-sm text-muted">Sign in with your admin account. Two-factor authentication is required.</p>
      <LoginForm />
    </main>
  );
}
