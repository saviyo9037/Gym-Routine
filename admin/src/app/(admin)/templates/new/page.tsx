import { pageGuard } from "@/lib/page-guard";
import { PageHeader } from "@/components/ui";
import { TemplateForm } from "@/components/template-form";

export default async function NewTemplate() {
  await pageGuard(["owner", "content"]);
  return (
    <>
      <PageHeader title="New template" />
      <TemplateForm defaults={{}} />
    </>
  );
}
