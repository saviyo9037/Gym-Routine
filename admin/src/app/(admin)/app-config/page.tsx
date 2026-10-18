import { pageGuard } from "@/lib/page-guard";
import { ErrorBox, PageHeader, fmtDate } from "@/components/ui";
import { AccessModelForm, OperationalConfigForm } from "@/components/config-forms";
import { loadAppConfig } from "@/lib/queries/app-config";

export default async function AppConfigPage() {
  const { role, db } = await pageGuard(["owner", "support"]);
  const { config, error } = await loadAppConfig(db);
  return (
    <>
      <PageHeader title="App config" subtitle="Remote switches the app reads. The app keeps working with built-in defaults if this is unreachable." />
      {error ? <ErrorBox message="Could not load the app config." /> : null}
      <div className="space-y-4">
        <OperationalConfigForm
          initial={{
            maintenance: config.maintenance_mode,
            message: config.maintenance_message ?? "",
            minVersion: config.min_app_version ?? "",
          }}
        />
        {role === "owner" ? (
          <AccessModelForm current={config.access_model_override} />
        ) : (
          <div className="card text-sm">
            <p className="font-medium">Access model override</p>
            <p className="mt-1 text-muted">Current: {config.access_model_override ?? "no override"}. Only owners can change it.</p>
          </div>
        )}
      </div>
      <p className="mt-3 text-xs text-muted">Last changed: {fmtDate(config.updated_at)}</p>
    </>
  );
}
