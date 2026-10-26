# Eluno protocol 1

All JSON APIs are same-origin. `POST /api/devices` registers `{name}` and returns `{id, token}`. Subsequent requests send `Authorization: Bearer <token>`. Media ticket URLs are the only content endpoints that authenticate through an opaque query ticket instead. Do not log these URLs or tokens. Error responses use `{error: string}` and an appropriate HTTP status.

| Method and path | Request / response | Permission |
| --- | --- | --- |
| GET `/api/health` | product, version, protocol, LAN support, chunk size, capability modules | Public; no secrets |
| POST `/api/rooms` | Creates a session; returns snapshot | Registered, currently unpaired |
| POST `/api/join` | `{code}` → pending snapshot | Registered; rate-limited |
| POST `/api/approve` | `{deviceId, allow}` | Creator; pending request required |
| POST `/api/renew-code` | New five-minute invitation code | Creator |
| GET `/api/pairing` | PNG QR, native `eluno://pair?data=<base64url JSON>` in LAN mode | Creator |
| GET `/api/addresses` | Private HTTPS origins, pin, LAN flag | Approved member |
| GET `/api/events?since=N` | Snapshot, waits up to 10 seconds if version unchanged | Registered |
| POST `/api/files` | `{files:[{name,type,size,allowDownload?}]}` → IDs | Approved member |
| PATCH `/api/files/:id` | `{allowDownload:boolean}` | File owner |
| DELETE `/api/files/:id` | Stops sharing and invalidates grants | File owner |
| POST `/api/files/:id/open` | Optional `{purpose:'view'|'download'}` → relative URL and type | Approved; download requires owner permission |
| GET/HEAD `/media/:id?ticket=…` | Original bytes, optional single Range; 206/Content-Range | Valid scoped ticket |
| POST `/api/chunks/:id` | Requested raw byte buffer, exact size, max 256 KiB | Requested source only |
| DELETE `/api/members/:id` | Removes a peer, its files and access | Creator; cannot remove self |
| POST `/api/leave` | Ends participation; creator ends entire room | Registered |
| GET `/api/diagnostics` | Version/protocol plus numeric counts | Approved; no filenames/tokens/addresses |

Snapshots include `version`, `self`, `pending`, `room` or null, and `reads`. Each read identifies `id`, `fileId`, inclusive `start` and `end`. A room contains creator ID, expiration, approved members, files, and creator-only pending request names/code. See `packages/protocol/index.d.ts` for fields. Source implementations must stop reading when participation ends and must never interpret file IDs as filesystem paths.

Native invitation JSON: `{v:1,endpoints:[privateHttpsOrigin,...],fingerprint:64HexCharacters,code:sixDigits,expiresAt:unixMilliseconds}`. Validate every endpoint and pin before connecting. Discovery carries no credentials and cannot replace this verification. Unknown protocol versions must be rejected.

A `download` grant is independent of a `view` grant; disabling downloads invalidates only download grants. Content-Disposition is set for downloads. Received bytes cannot be recalled. Names are display metadata and are escaped by clients, with a separate safe download filename formatter. Media metadata validation does not establish codec support.

New modules must explicitly declare capability/version, authorization and revocation rules, bounded resource use, visible consent, backward compatibility and a tested failure path. The initial `search` module uses client-local metadata, and `save-copy` extends the owner permission model. No cloud persistence or account dependency is implied by adding a module.
