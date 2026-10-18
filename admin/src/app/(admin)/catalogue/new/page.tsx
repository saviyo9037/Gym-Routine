import { pageGuard } from "@/lib/page-guard";
import { PageHeader } from "@/components/ui";
import { ExerciseForm } from "@/components/exercise-form";

export default async function NewExercise() {
  const { db } = await pageGuard(["owner", "content"]);
  const { data } = await db.from("exercises_catalog").select("id").order("id", { ascending: false }).limit(1).maybeSingle();
  return (
    <>
      <PageHeader title="New exercise" subtitle="The integer id is permanent and must match the app's exercise id." />
      <ExerciseForm mode="create" defaults={{ id: (data?.id ?? 0) + 1 }} />
    </>
  );
}
