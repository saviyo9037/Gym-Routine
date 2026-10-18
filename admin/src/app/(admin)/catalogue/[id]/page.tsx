import { notFound } from "next/navigation";
import { pageGuard } from "@/lib/page-guard";
import { ErrorBox, PageHeader } from "@/components/ui";
import { ExerciseForm } from "@/components/exercise-form";
import { MediaUploadForm } from "@/components/media-upload-form";
import { MediaTable, type MediaRow } from "@/components/media-table";
import { ActionButton } from "@/components/action-button";
import { archiveExercise } from "@/lib/actions/catalogue";

export default async function EditExercise({ params }: { params: Promise<{ id: string }> }) {
  const { db } = await pageGuard(["owner", "content"]);
  const { id: raw } = await params;
  const id = Number(raw);
  if (!Number.isInteger(id) || id <= 0) notFound();
  const [ex, media] = await Promise.all([
    db.from("exercises_catalog").select("*").eq("id", id).maybeSingle(),
    db
      .from("exercise_media")
      .select("id, exercise_id, media_type, storage_path, size_bytes, license, attribution, license_verified, status")
      .eq("exercise_id", id)
      .order("created_at", { ascending: false }),
  ]);
  if (ex.error) return <ErrorBox message="Could not load exercise." />;
  if (!ex.data) notFound();
  return (
    <>
      <PageHeader title={ex.data.name} subtitle={`Exercise #${id} - ${ex.data.status}`}>
        {ex.data.status !== "archived" ? (
          <ActionButton
            action={archiveExercise.bind(null, id)}
            label="Archive"
            variant="danger"
            confirmText="Archive this exercise? It will be removed from the app on the next publish."
          />
        ) : null}
      </PageHeader>
      <ExerciseForm mode="update" defaults={ex.data} />
      <h2 className="mb-2 mt-8 text-lg font-medium">Media</h2>
      {media.error ? (
        <ErrorBox message="Could not load media." />
      ) : media.data?.length ? (
        <MediaTable rows={media.data as MediaRow[]} />
      ) : (
        <p className="mb-3 text-sm text-muted">No media for this exercise yet.</p>
      )}
      <h3 className="mb-2 mt-6 text-sm font-medium text-muted">Upload media</h3>
      <MediaUploadForm exerciseId={id} />
    </>
  );
}
