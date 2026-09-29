# Evora_Police — Security, performance and UI review

> Development steps 9, 10 and 11 of the master specification.

## Step 9 — Security review

### Inbound surface

| Entry point | Who can call it | Guard |
|---|---|---|
| `evora_police:rpc` | any client | Registry of 47 actions. Every call resolves `source → user_id` on the server, then applies the token-bucket rate limit, the per-action cooldown, the feature flag, the military / permission / duty checks (fresh vRP groups) and the handler's own payload validation. |
| `evora_police:cres` | any client | Only resolves a pending server request of **the same** client. The value is validated by the code that asked. |
| Builder Menu actions | vRP menu / builtin menu | Server-side closures. Every flow re-reads the player's live groups when it runs and again after each wait (popup, confirmation). |
| `vRP:*`, `playerDropped` | server only | Local events (not network-safe), so clients cannot trigger them. |

Actions open to every player (`session:init`, `menu:*`, `dialog:*`, `confirm:answer`,
`spectate:stop`) only act on the caller's own session, popup, confirmation or spectate.

### Checks performed

* Every one of the 47 RPC handlers and every menu flow was read for: permission source (live
  vRP groups, never client data), scope (`Gov.canOnTarget` / `Gov.canOnRank`), re-validation
  after asynchronous waits, target validation (online, same `user_id`, server-side distance)
  and payload typing.
* Secrets: `config/server.lua` (webhooks, bot token, API keys) is a `server_script`; no code
  path sends `Config.Webhooks` or `Config.Secrets` to a client (verified with grep).
* NUI: every value is inserted as text. The only `innerHTML` sink receives static icon
  constants looked up by key.
* Client event handlers that act on network ids were audited, since those ids can come from a
  client report when OneSync is off.
* Every native name used by the client and server scripts was extracted with `luac -l` and
  checked, which rules out silent typos.

### Findings and fixes

| # | Finding | Impact | Fix | Covered by |
|---|---|---|---|---|
| 1 | Recruitment scope-checked only the ranks it replaced, so a sector commander could add a rank to an officer of another command or to a senior. | High | Recruitment is refused unless every current rank of the target is inside the recruiter's scope. | `affairs_spec` |
| 2 | Without OneSync, a barricade entry could carry a forged network id, and its removal would delete that entity on every client (e.g. another player's vehicle). | High | Clients only delete objects whose model is a configured barricade. | `client_smoke` |
| 3 | The impound deletion used a network id reported by the officer's client. | Medium | The client only deletes a vehicle that carries the impounded plate. | `client_smoke` |
| 4 | A spectate session outlived a revoked permission (demotion, released prisoner). | Medium | Sessions carry a guard, re-checked every 5 s. The session ends with `revoked` once the guard fails. | `affairs_spec` |
| 5 | Some permissions were not re-checked after a popup or confirmation wait: citizen, fine and jail inquiries, field confirmations, and the affairs vacation break. | Medium | Each flow re-validates the live profile (and the scope) after the wait. | `field_spec` |
| 6 | Vehicle-trunk seizure ignored per-action permission overrides. | Low | It now requires the `vehicleSearch` and `seizeContraband` action permissions. | — |
| 7 | With `giveToOfficer` enabled, seized weapons trusted the names and ammo the target's client reported. | Low (off by default) | Names must look like `WEAPON_*`, and ammo is capped by `maxAmmo`. | — |
| 8 | Discord mentions were neutralised only by rewriting the text. | Low | Webhook payloads also send `"allowed_mentions":{"parse":[]}`, written as literal JSON so no encoder can turn it into an object. | `affairs_spec` |
| 9 | Invalid UTF-8 in player text could make Discord reject a log. | Low | `Utils.validUtf8` runs inside `sanitize` / `safeName` (fuzz-tested). | — |
| 10 | Per-connection state (rate-limit buckets, menus, popups) stayed behind for players who never finished loading. | Low | The cleanup now runs on every drop. | — |
| 11 | A jail task waited forever if the NUI never answered a skill check. | Low | Unanswered skill checks fail after 10 s. | `client_smoke` |

### Accepted limitations (documented for server owners)

* **OneSync is strongly recommended.** Without it the server cannot see positions. Target lists
  then come from the officer's client, but every action re-measures the distance using both
  players' own reports, and the jail perimeter falls back to the prisoner's report. That report
  can only ever add time.
* **vRP 0.5 keeps weapons on the client.** Weapon searches and seizures reflect what the
  target's game reports.
* **Jail skill checks run on the client.** The server bounds their effect: the prisoner must be
  at the task when it starts and when it completes, the task has a minimum duration and a
  per-task cooldown, total reduction is capped at a percentage of the sentence, and a minimum
  remaining time always stays.

## Step 10 — Performance review

* **Server:** there is no per-frame work. Timers are listed in `ARCHITECTURE.md §8`. The jail
  timer now counts elapsed game time, so a server hitch no longer stretches sentences. Database
  writes are batched (duty heartbeat, jail persistence). Log inserts are asynchronous, and
  webhooks are queued with 429 back-off.
* **Queries:** every hot-path filter is indexed: officers (`sector`, `active`), fines
  (`target_id, status`), reports (`status`, `reporter_id`), wanted (`target_id, active`, plus
  the new `active` index used by the list and the overview count), impounds (`plate, status`,
  `owner_id, status`), vacations, logs and history tables. Every list has a `LIMIT`.
* **Client:** every loop is gated by state (a prompt is visible, the player is cuffed, jailed,
  in an alert zone, placing a barricade, or spectating). The only permanent loop, the
  interaction points, sleeps 750 ms when far away. Hints and NUI messages are de-duplicated, so
  nothing is sent every frame.
* **NUI:** vanilla JS with no framework. Timers belong to their layer and are cleared when it
  closes. The fonts are bundled (Tajawal, ~100 KB).

## Step 11 — UI/UX review

All 16 screens are rendered in headless Chromium at 1920×1080 by `tests/ui/preview.js`, with
no console errors. Fixes made during the review:

* Logos disappeared behind hidden layers because every copy shared one SVG gradient id; each
  logo now gets its own.
* Durations use locale formats (`51 س 30 د`), as do relative times.
* مكتبي gained a "نشاط الخدمة" card: reports handled, vehicles impounded, last clock-in and
  last clock-out.
* The recruitment button sits under the rank picker (sticky card) instead of below the fold.
* Number inputs no longer show browser spinners.
* Broadcasts no longer capture clicks meant for the panel beneath them.
* The spectate stop label reads "إيقاف المراقبة".
* The confirmation hint shows the configured key instead of a hard-coded F5.

## Re-running the checks

```bash
lua5.4 tests/run.lua                                   # 129 server specs (needs MariaDB)
lua5.4 tests/client_smoke.lua                          # 59 client checks
NODE_PATH=tests/ui/node_modules node tests/ui/preview.js   # NUI screenshots → tests/ui/shots/
```
