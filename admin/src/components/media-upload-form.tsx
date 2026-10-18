"use client";

import { useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { uploadMedia } from "@/lib/actions/media";

const MAX_VIDEO = 50 * 1024 * 1024;
const MAX_IMAGE = 5 * 1024 * 1024;

export function MediaUploadForm({ exerciseId }: { exerciseId: number }) {
  const router = useRouter();
  const [pending, start] = useTransition();
  const [error, setError] = useState<string | null>(null);
  const [done, setDone] = useState(false);

  function submit(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault();
    const fd = new FormData(e.currentTarget);
    const file = fd.get("file");
    setError(null);
    setDone(false);
    // Early feedback only; the server re-validates type, size and file signature.
    if (file instanceof File) {
      const isVideo = file.type === "video/mp4";
      if (file.size > (isVideo ? MAX_VIDEO : MAX_IMAGE)) {
        setError(`File too large (max ${isVideo ? "50" : "5"} MB)`);
        return;
      }
    }
    start(async () => {
      const r = await uploadMedia(fd);
      if (r.ok) {
        setDone(true);
        (e.target as HTMLFormElement).reset?.();
        router.refresh();
      } else {
        const fe = r.fieldErrors ? Object.values(r.fieldErrors).flat().join(", ") : "";
        setError(r.error === "validation" ? fe || "Invalid input" : r.error);
      }
    });
  }

  return (
    <form onSubmit={submit} className="card grid gap-3 md:grid-cols-2">
      <input type="hidden" name="exercise_id" value={exerciseId} />
      <div className="md:col-span-2">
        <label className="label" htmlFor="file">
          File (mp4 up to 50 MB; jpg/png/webp up to 5 MB)
        </label>
        <input id="file" name="file" type="file" accept="video/mp4,image/jpeg,image/png,image/webp" required className="input" />
      </div>
      <div>
        <label className="label" htmlFor="license">
          Licence (required)
        </label>
        <input id="license" name="license" required className="input" placeholder="State the actual licence/permission" />
      </div>
      <div>
        <label className="label" htmlFor="attribution">
          Attribution / source credit (required)
        </label>
        <input id="attribution" name="attribution" required className="input" />
      </div>
      <div className="md:col-span-2">
        <label className="label" htmlFor="source_url">
          Source URL (optional)
        </label>
        <input id="source_url" name="source_url" type="url" className="input" />
      </div>
      <p className="text-xs text-muted md:col-span-2">
        Uploads are saved as drafts with the licence marked UNVERIFIED. A person must verify the licence before the media can be published.
      </p>
      <div className="md:col-span-2">
        {error ? (
          <p role="alert" className="mb-2 text-sm text-danger">
            {error}
          </p>
        ) : null}
        {done ? <p className="mb-2 text-sm text-ok">Uploaded as draft.</p> : null}
        <button className="btn" disabled={pending}>
          {pending ? "Uploading..." : "Upload"}
        </button>
      </div>
    </form>
  );
}
