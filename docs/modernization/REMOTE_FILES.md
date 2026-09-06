# Remote files and NAS support

Status: proposed technical plan

## Goal

A user should be able to choose a music location that their desktop file
browser can access and use it as a gmusicbrowser library source without first
creating a manual system mount. This includes NAS and server locations reached
through SMB, SFTP, FTP/FTPS, AFP where still available, WebDAV, and other
enumerable schemes supplied by the installed desktop storage backend.

"Support" means more than accepting a URI. For a declared library-source
capability it includes:

- Selecting or entering the location.
- Reusing access already established by the desktop file browser or portal.
- Recursively indexing supported audio files.
- Reading metadata and artwork.
- Playing, seeking, queueing, and reporting errors.
- Preserving the indexed library while offline.
- Reconnecting and reconciling changes safely.
- Editing tags and moving/renaming files only when the backend can do so safely.

## Current limitations

The present code treats a song as a POSIX `path` plus `file` and derives a
`file://` URI from them. Important operations use Perl filesystem primitives:

- Scanning relies on `opendir`, `readdir`, `-f`, and `-d` in
  `gmusicbrowser.pl` and `gmusicbrowser_list.pm`.
- Song existence and missing-file logic use `-e` in
  `gmusicbrowser_songs.pm`.
- File choosers frequently remove `file://` and reject every other scheme.
- Tag readers and writers receive local filenames.
- Artwork discovery scans local parent directories.
- Rename, copy, export, and external-command paths assume local files.
- The GStreamer backend accepts a URI but normally receives a local filename
  from the song model.

Adding protocol-specific scanners around these assumptions would multiply
special cases and still fail on desktop-provided locations. The storage model
must become URI-native first.

## Product behaviour

### Adding a source

The main action is **Add Music Source…**. It opens the native/portal folder
chooser, allowing the current desktop to show its local disks, connected
servers, and network locations. The application also accepts:

- A folder dragged from a file browser.
- A URI pasted into an advanced location field.
- A URI or accessible directory received on the command line.

Gmusicbrowser does not initiate network authentication. If the selected
location is not currently accessible, it reports that state and asks the user
to connect or authorize it in the desktop file browser, then retry. A native
file chooser or portal may show desktop-owned access UI as part of selecting a
location, but no password or key passes through gmusicbrowser.

### Source status

Every source has a visible state:

- Online
- Scanning
- Offline
- Access required
- Permission denied
- Read-only
- Partially scanned
- Error, with a retry action and useful details

Songs from an offline source remain searchable, sortable, and usable in saved
lists. Playing them offers retry and a **Reconnect in File Browser** action
instead of reporting that the library entry has vanished or opening an
application-owned login prompt.

The application loads cached library data first and checks source availability
asynchronously. An unavailable source produces one quiet, source-level status
and does not display repeated dialogs for its songs. Queue entries remain in
place; a failed playback attempt may be retried or skipped, but never removes
the song from the queue or library.

### Availability state machine

Availability and catalog presence are separate state machines. A source may
move through `unknown`, `checking`, `online`, `scanning`, `offline`,
`access-required`, or `error` without changing any song record. A song may be
present, unverified, or missing while its record and all user metadata remain
intact. Only a successful, source-identity-verified scan can commit a new
presence generation.

The normal startup path is therefore:

1. Load the complete cached library and user state.
2. Show remote songs immediately, with their last known availability.
3. Check each source without blocking local-library use.
4. Scan only sources proven accessible and matching their registered identity.
5. Gently mark unavailable sources offline or access-required and retain their
   last complete generation unchanged.

### Source preferences

Per-source options include:

- Display name.
- Scan automatically, manually, or on a schedule.
- Follow symbolic links where meaningful.
- Include/exclude patterns.
- Read-only policy even when writes are technically available.
- Artwork and optional audio-cache policy.
- Bandwidth/concurrency limit.
- Open/reconnect through the desktop and rescan actions.
- Remove source from library, with an explicit confirmation separate from
  merely disconnecting it.

## Terminology and data model

### Resource

A resource is an immutable application reference to a file-like object. Its
authoritative identity is a canonical URI plus source context. It may currently
have a native local path, a seekable stream, a staged local copy, or none of
those while offline.

### Source

A source is a user-approved library root.

Suggested source record:

| Field | Purpose |
|---|---|
| `source_id` | Stable application UUID, independent of mount path |
| `root_uri` | Canonical root without embedded credentials |
| `display_name` | User-facing name, independent of URI escaping |
| `provider` | Local, GIO, portal document, or future adapter |
| `capabilities` | Enumerate/read/seek/monitor/write/move/replace/delete flags |
| `availability` | Online/offline/access-required/error state |
| `read_only_policy` | User policy layered over backend capability |
| `scan_policy` | Manual/startup/scheduled/monitor-assisted |
| `cache_policy` | Metadata/artwork/audio limits and pinning policy |
| `last_complete_scan` | Time and generation of last successful traversal |
| `last_error` | Structured error category and redacted diagnostic |

### Song location

Suggested song-location fields:

| Field | Purpose |
|---|---|
| `source_id` | Owning source |
| `relative_uri` | Canonical location below the root |
| `resource_id` | Backend file ID when stable and available |
| `display_name` | Human-readable basename |
| `size` | Last observed byte size |
| `modified` | Last observed modification time |
| `etag` | Version token used for change/conflict checks |
| `content_type` | Last observed media/content type |
| `availability` | Available/offline/missing/permission/error |
| `cache_key` | Optional local staging/cache reference |

The public `uri` field becomes authoritative. Existing `path`, `file`, and
`fullfilename` fields remain computed compatibility values for native local
resources during migration. A remote resource must never be forced into a fake
POSIX path.

### Identity rules

- Normalize URI scheme and escaping through `GFile`, not hand-written regular
  expressions.
- Reject credential-bearing URIs as canonical source identities and strip
  sensitive user information before persistence or logging.
- Keep display names separate from serialized URIs.
- Use source ID plus relative URI as the portable fallback identity.
- Record a backend file ID when available to recognize renames, but never
  require it because remote backends may not provide stable IDs.
- Treat case sensitivity and Unicode normalization as source capabilities; do
  not assume local Unix semantics for SMB or AFP.

## Storage service

The core uses a storage interface instead of Perl path operators.

Required asynchronous operations:

- Create/normalize a resource from a path, command-line argument, or URI.
- Query attributes and capabilities.
- Enumerate children in bounded batches.
- Open a read or read/write stream.
- Request a seekable local staging lease.
- Monitor a resource where supported.
- Recheck a location after the desktop establishes or restores access.
- Copy, move, replace, delete, and create directories where supported.
- Compare identity, parentage, and relative location.
- Produce a redacted display URI and structured errors.

Synchronous calls are permitted for already-cached application data and small
local operations outside the UI event path. Network I/O must never block the
GTK main thread.

### Providers

#### Local/GIO provider

Use `GFile` for local paths as well as URIs. This gives local and remote
resources one API and allows GIO/GVfs to provide installed schemes. `GFile`
supports async enumeration, attributes, streams, monitors, mounting, copying,
moving, and replacing without requiring a POSIX path.

Reference: <https://docs.gtk.org/gio/iface.File.html>

#### Desktop portal provider

Use the FileChooser portal for user-approved roots, especially in Flatpak. The
portal returns application-accessible `file://` document paths and can preserve
access across sessions. Treat those paths as granted native resources and
retain the document identity needed by the selected packaging model.

Use the FileTransfer portal format for sandbox-aware drag-and-drop when the
toolkit exposes it.

References:

- <https://flatpak.github.io/xdg-desktop-portal/docs/doc-org.freedesktop.portal.FileChooser.html>
- <https://flatpak.github.io/xdg-desktop-portal/docs/doc-org.freedesktop.portal.FileTransfer.html>

#### KDE interoperability

Dolphin and other KDE applications use KIO, while GTK uses GIO. KDE can expose
KIO resources to non-KIO applications through KIOFuse, and the KDE portal can
return an application-accessible path. These projected paths are the preferred
zero-special-case integration on Plasma.

If Dolphin supplies a standard URI such as `smb://` or `sftp://`, the GIO
provider may also handle it when the corresponding GVfs backend is installed
and already connected. Capability detection decides this at runtime; sharing a
URI spelling does not imply that KIO and GIO share an access session.

Reference: <https://invent.kde.org/system/kio-fuse>

#### Future providers

The interface permits a future dedicated provider, but the initial release
does not embed SMB, SSH, FTP, or AFP client libraries. Protocol implementation,
connection setup, and credential policy remain with GIO/GVfs, the portal, or
the desktop file browser.

## Protocol and capability policy

Support is capability-based rather than a hard-coded scheme whitelist.

| Location type | Expected initial mode | Notes |
|---|---|---|
| Native `file://` | Full | Existing paths migrate here |
| CIFS/NFS system mount | Full | Appears as native file storage |
| Portal document path | Full within granted permissions | Persistence depends on portal grant |
| KIOFuse path | Full within projection capabilities | Preferred KDE bridge for KIO resources |
| `smb://` | Library source when GVfs SMB exists | Primary NAS acceptance protocol |
| `sftp://` | Library source when an already-connected GVfs SFTP resource exists | Primary secured remote acceptance protocol |
| `ftp://`, `ftps://` | Usually read-oriented library source | Writes enabled only after capability and safety checks |
| `afp://` | Optional library source when a maintained backend exists | AFP is the Apple Filing Protocol; modern Apple NAS often also offers SMB |
| `dav://`, `davs://` | Library source when enumerable | Test seek and safe replacement separately |
| `http://`, `https://` | Playback item/stream by default | Ordinary HTTP is not an enumerable directory tree |

The UI reports missing backend support and recommends connecting through the
desktop rather than silently treating the URI as an empty folder.

## Scanning and reconciliation

Remote scanning must be incremental, cancellable, and conservative.

1. Verify that the already desktop-accessible source is reachable and matches
   its registered source or mount identity; otherwise stop without catalog
   mutation.
2. Establish a candidate scan generation without replacing the last complete
   generation.
3. Enumerate directories asynchronously in bounded batches.
4. Query name, type, size, modification time, etag/file ID, and content type in
   the directory request where possible.
5. Compare those cheap attributes with the local index.
6. Queue metadata reads only for new or changed candidates.
7. Stage discovered changes in database batches and update the UI through
   state events.
8. Commit the candidate generation only after the entire traversal and source
   health checks complete successfully.
9. Songs unseen in that verified generation may be marked missing, but their
   records, ratings, labels, play history, artwork associations, queue entries,
   and saved-list membership are retained.
10. On disconnect, access denial, cancellation, source-identity mismatch, or
   partial traversal,
   retain the previous source generation and report a partial scan.
11. Quarantine an empty result or unexpectedly large disappearance for a later
   confirmation scan or explicit user review instead of committing it.
12. Permanently purging missing records is a separate, explicit action that
   previews the affected source and song count.

The mass-loss guard must use more than a brittle fixed percentage. It considers
source identity, root attributes, enumeration errors, prior generations, and
the scale and shape of the change. In particular, a now-unmounted NAS that
leaves an empty local directory at the old mount path is an offline or
source-mismatch event, not an empty music library.

Directory monitors are an optimization, not the correctness mechanism. Remote
backends may lack monitors or lose events while disconnected, so a full
reconciliation remains available.

Concurrency defaults must be conservative. More parallel metadata reads can
make a high-latency server faster, but can overload a small NAS or saturate Wi-Fi.

## Metadata and artwork

Metadata parsers should consume an application source abstraction with:

- Read operations.
- Seek/tell where available.
- Known size and version information.
- Cancellation and structured I/O errors.
- A method to request a local staging lease.

Migration can proceed in stages:

1. Stage remote files locally for existing filename-only parsers.
2. Adapt parsers that naturally support seekable streams.
3. Optimize header/range reads for large remote files where measurements show
   that full staging is too expensive.

Metadata and artwork results are stored locally so browsing remains useful
offline. Folder artwork uses sibling resources, not string concatenation of
local paths. Embedded art follows the media resource's cache/version rules.

## Playback and buffering

Preferred flow:

1. Give the canonical URI to GStreamer when its source stack can read and seek
   the scheme.
2. Allow GStreamer's URI source/buffering elements to handle normal network
   buffering.
3. If direct playback cannot provide the required access, acquire a local
   staging lease and play its `file://` URI.
4. Keep the lease through playback and gapless handoff; release it when no
   consumer remains.

The UI distinguishes connecting, buffering, offline, access-required, and codec
errors. It must not collapse every remote failure into "file missing" or ask
for server credentials itself.

Reference:
<https://gstreamer.freedesktop.org/documentation/playback/playbin.html>

## Cache and staging

Separate caches by purpose:

- Metadata staging: short-lived files needed to inspect tags.
- Artwork: reusable thumbnails/originals keyed by resource version.
- Playback staging: active or recently used complete media objects.
- User-pinned audio: optional future offline-use feature, not enabled by
  default.

Requirements:

- Configurable size limit and cache location.
- LRU eviction with active leases protected.
- Keys derived from redacted resource identity plus version/etag.
- Atomic completion marker so partial downloads are never treated as valid.
- Cancellation, retry, free-space checks, and cleanup after crashes.
- No automatic full-library mirroring.
- Cache removal never removes the library entry or remote original.

## Remote writes and tag safety

Remote mutation is opt-in per source until proven safe.

For a tag edit:

1. Capture original URI, size, modification time, and etag/version.
2. Download or lease a complete local working copy.
3. Run the existing tag writer against a new temporary local file.
4. Re-read and validate the result.
5. Recheck the remote original for conflicting changes.
6. Upload to a temporary sibling resource.
7. Atomically replace/rename when the provider supports it.
8. Refresh attributes and library metadata.
9. If any precondition or atomic step is unsupported, keep the remote original
   unchanged and report that safe writing is unavailable.

Never overwrite the remote original progressively across an unreliable
connection. Delete and rename actions use the same capability and conflict
model. Cross-source moves are copy, verify, then delete, and require a separate
confirmation when atomicity is impossible.

## Access and privacy boundary

- Do not create a login dialog, password field, key selector, credential store,
  or protocol-specific connection wizard.
- Do not call a mount operation that delegates credential questions back into
  gmusicbrowser UI. Consume resources that are already accessible through the
  desktop session.
- Let the native file chooser/portal and file browser own connection and access
  prompts. Gmusicbrowser sees only the resulting accessible URI/path or an
  access failure.
- On `not mounted`, `permission denied`, or equivalent errors, mark the source
  **Access required** and offer **Reconnect in File Browser** plus **Retry**.
- Reject passwords, private keys, and credential-bearing URIs from saved source
  identity.
- Redact usernames, hosts where configured, query tokens, and sensitive paths
  from normal logs and crash reports.
- Never place credentials in GStreamer command lines or exported playlists.
- Distinguish access-required, denied, host-key/certificate failure reported by
  the desktop, not-found, timeout, and offline errors without attempting to fix
  authentication internally.
- Respect sandbox permissions and do not bypass the portal with broad host
  filesystem access.

## External commands and exports

Existing commands may expand `$files` to local filenames. For remote songs each
command declares one of:

- Accepts URIs: pass redacted canonical URIs.
- Requires local files: acquire staging leases before launch.
- Mutates files: disabled until a safe import-back transaction is designed.

Playlist exports should prefer canonical URIs when the format permits them.
Portable exports may offer path rewriting relative to a selected source, but
must never include credentials.

## Testing

### Contract tests

Every provider runs the same tests for each capability it advertises:

- URI normalization and redaction.
- Attribute query and batched enumeration.
- Read, seek, cancellation, and local staging.
- Monitor events or declared monitor absence.
- Accessible/inaccessible state and recovery after the desktop reconnects.
- Copy/move/replace/delete semantics.
- Version conflict and partial-transfer cleanup.

### Integration matrix

Automated test services should cover at least:

- Samba/SMB with guest, preconnected authenticated, read-only, and writable
  shares. The harness, not gmusicbrowser, establishes the authenticated mount.
- OpenSSH SFTP preconnected by the test desktop using ephemeral credentials.
- FTP and FTPS, primarily for read/error behaviour.
- WebDAV when included in the support matrix.
- A high-latency/fault proxy for timeout, truncation, disconnect, and retry.
- AFP in an optional/manual job where a maintained server/backend is available.
- KDE portal/KIOFuse and GTK/GVfs desktop sessions in scheduled testing.
- Flatpak document access and sandbox-aware drag-and-drop.

Scenarios include desktop reconnect during playback, NAS loss during a scan,
revoked desktop access, rename during metadata staging, concurrent remote tag
modification, cache exhaustion, application restart with partial files, and
local-library use while every remote source is offline.

Data-loss regression scenarios are release blockers. They include a NAS absent
before launch, disconnect during enumeration, an unmounted path exposing an
empty local directory, a successful-looking empty listing, permission loss, a
different share appearing at the former path, and a legitimate individual file
deletion. Every scenario must preserve the total catalog record and all user
metadata; the last scenario may only soft-mark the file missing until the user
explicitly purges it.

### Performance budgets

Measure and set budgets for:

- Time to show the cached library while offline.
- First directory results and complete traversal at representative latency.
- Requests and bytes transferred during unchanged rescans.
- Metadata throughput with bounded concurrency.
- Time to start playback uncached and cached.
- Cache growth and eviction.
- UI frame/command latency during scanning and buffering.

## Delivery slices

Remote support can ship incrementally behind an experimental setting:

1. URI/source model with unchanged local-file behaviour.
2. Desktop-projected remote paths and read-only GIO enumeration.
3. SMB and SFTP scan/play/reconnect acceptance.
4. Artwork and metadata optimization plus bounded playback staging.
5. Safe writes for one capable backend.
6. Wider protocol matrix and stable-source UI.

The feature leaves experimental status only after temporary source loss cannot
cause library deletion and access-boundary/cache audits pass.
