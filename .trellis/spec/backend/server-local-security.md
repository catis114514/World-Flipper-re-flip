# Local Server Security Contract

## 1. Scope / Trigger

Applies while the legacy Fastify server remains available as a reference/compatibility runtime during Godot migration.

## 2. Signatures

```text
POST /api/index.php/tool/signup -> random numeric viewer_id
POST /api/index.php/load         -> requires a valid viewer session
GET  /mail                       -> static template; query messages render only via textContent
CN_LISTEN_HOST                   -> defaults to 127.0.0.1
```

## 3. Contracts

- `viewer_id` is a cryptographically random session token and is not the account primary key.
- `/load` never falls back to account 1 and resolves account ownership only through `getSession()`.
- Invalid JSON produces HTTP 400 through the Fastify parser.
- User-controlled query strings are never interpolated into server-rendered HTML.
- A missing player sends an explicit response; async handlers never return bare `undefined`.

## 4. Validation & Error Matrix

| Condition | Result |
|---|---|
| Missing/unknown viewer token | 400, no profile data |
| Invalid JSON | 400, route handler not entered |
| Missing player row | explicit 500 response |
| No listen-host configuration | bind loopback only |

## 5. Good / Base / Bad Cases

- Good: signup returns random token; load validates it and returns that same token in headers.
- Base: LAN operation explicitly sets `CN_LISTEN_HOST` and accepts the remaining compatibility-server risk.
- Bad: `token=String(accountId)`, `viewer_id || 1`, raw `${query}` HTML, or default `0.0.0.0` binding.

## 6. Tests Required

- Static security regression script checks all forbidden patterns.
- TypeScript syntax parsing for every changed route/server file.
- Existing gacha movie selection regression remains green.

## 7. Wrong vs Correct

```ts
// Wrong
const accountId = body.viewer_id || 1;

// Correct
const session = await getSession(String(body.viewer_id));
if (!session) return reply.status(400).send(...);
const accountId = session.accountId;
```
