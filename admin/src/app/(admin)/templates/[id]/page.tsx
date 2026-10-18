import { notFound } from "next/navigation";
import { pageGuard } from "@/lib/page-guard";
import { ErrorBox, PageHeader } from "@/components/ui";
import { TemplateForm } from "@/components/template-form";
import { ActionButton } from "@/components/action-button";
import { deleteTemplate } from "@/lib/actions/templates";
import { uuidSchema } from "@/lib/validation";

export default async function EditTemplate({ params }: { params: Promise<{ id: string }> }) {
  const { db } = await pageGuard(["owner", "content"]);
  const { id } = await params;
  if (!uuidSchema.safeParse(id).success) notFound();
  const { data, error } = await db.from("template_plans").select("*").eq("id", id).maybeSingle();
  if (error) return <ErrorBox message="Could not load template." />;
  if (!data) notFound();
  return (
    <>
      <PageHeader title={data.title}>
        <ActionButton action={deleteTemplate.bind(null, id)} label="Delete" variant="danger" confirmText="Delete this template?" redirectTo="/templates" />
      </PageHeader>
      <TemplateForm defaults={data} />
    </>
  );
}
