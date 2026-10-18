import { pageGuard } from "@/lib/page-guard";
import { ErrorBox, PageHeader, fmtDate } from "@/components/ui";
import { PaywallCopyForm } from "@/components/config-forms";
import { loadAppConfig } from "@/lib/queries/app-config";
import { createStoreInfoProvider } from "@/lib/revenuecat";

export default async function PaywallPage() {
  // Pricing copy is owner-only.
  const { db } = await pageGuard(["owner"]);
  const [{ config, error }, store] = await Promise.all([loadAppConfig(db), createStoreInfoProvider().overview()]);

  return (
    <>
      <PageHeader title="Plans & Paywall" subtitle="What the in-app paywall says. Prices and trial length live in Google Play Console." />
      {error ? <ErrorBox message="Could not load the app config." /> : null}

      <div className="card mb-4 text-sm">
        <p className="mb-2 font-medium">Store plans (read-only)</p>
        {!store.configured ? (
          <p className="text-muted">
            Not configured. Add the two server-side RevenueCat variables from <code>.env.example</code> to show the monthly/yearly offers here. Prices and the free trial are changed in <strong>Google Play Console</strong> (subscriptions,
            base plans, offers), never in this panel.
          </p>
        ) : store.error ? (
          <ErrorBox message={`${store.error}. Prices and trials are managed in Google Play Console.`} />
        ) : store.plans.length === 0 ? (
          <p className="text-muted">RevenueCat returned no packages. Check the current offering in RevenueCat.</p>
        ) : (
          <table className="w-full">
            <thead>
              <tr>
                <th className="th">Package</th>
                <th className="th">Product</th>
                <th className="th">Period</th>
                <th className="th">Price</th>
                <th className="th">Trial</th>
              </tr>
            </thead>
            <tbody>
              {store.plans.map((p) => (
                <tr key={p.packageId}>
                  <td className="td">{p.title ?? p.packageId}</td>
                  <td className="td">{p.productId ?? "-"}</td>
                  <td className="td">{p.period ?? "not provided by the API"}</td>
                  <td className="td">{p.price ?? "not provided by the API"}</td>
                  <td className="td">{p.trial ?? "not provided by the API"}</td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
        <p className="mt-3 text-xs text-muted">
          The app always shows the price and trial text that Google Play returns for the signed-in user. This table is for reference only.
        </p>
      </div>

      <PaywallCopyForm
        initial={{
          title: config.paywall_title ?? "",
          subtitle: config.paywall_subtitle ?? "",
          benefits: config.paywall_benefits.join("\n"),
          badgeMonthly: config.plan_badges.monthly ?? "",
          badgeYearly: config.plan_badges.yearly ?? "",
          promo: config.promo_text ?? "",
        }}
      />
      <p className="mt-3 text-xs text-muted">Last changed: {fmtDate(config.updated_at)}</p>
    </>
  );
}
