import { ActionButton } from "@/components/action-button";
import { deleteMedia, setMediaStatus, verifyMediaLicense } from "@/lib/actions/media";

export interface MediaRow {
  id: string;
  exercise_id: number;
  media_type: string;
  storage_path: string;
  size_bytes: number;
  license: string;
  attribution: string;
  license_verified: boolean;
  status: string;
}

export function MediaTable({ rows, showExercise }: { rows: MediaRow[]; showExercise?: boolean }) {
  return (
    <div className="card overflow-x-auto p-0">
      <table className="w-full">
        <thead>
          <tr>
            {showExercise ? <th className="th">Exercise</th> : null}
            <th className="th">Type</th>
            <th className="th">Licence</th>
            <th className="th">Verified</th>
            <th className="th">Status</th>
            <th className="th">Size</th>
            <th className="th">Actions</th>
          </tr>
        </thead>
        <tbody>
          {rows.map((m) => (
            <tr key={m.id}>
              {showExercise ? <td className="td">#{m.exercise_id}</td> : null}
              <td className="td">{m.media_type}</td>
              <td className="td">
                {m.license}
                <span className="block text-xs text-muted">{m.attribution}</span>
              </td>
              <td className="td">{m.license_verified ? <span className="text-ok">Yes</span> : <span className="text-danger">UNVERIFIED</span>}</td>
              <td className="td">{m.status}</td>
              <td className="td">{(m.size_bytes / 1024 / 1024).toFixed(2)} MB</td>
              <td className="td">
                <div className="flex flex-wrap gap-2">
                  {!m.license_verified ? (
                    <ActionButton action={verifyMediaLicense.bind(null, m.id)} label="Mark licence verified" confirmText="Confirm you have checked that the licence/permission is genuine." />
                  ) : null}
                  {m.status !== "published" ? (
                    <ActionButton action={setMediaStatus.bind(null, m.id, "published")} label="Publish" />
                  ) : (
                    <ActionButton action={setMediaStatus.bind(null, m.id, "archived")} label="Unpublish" />
                  )}
                  <ActionButton action={deleteMedia.bind(null, m.id)} label="Delete" variant="danger" confirmText="Delete this media file?" />
                </div>
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
