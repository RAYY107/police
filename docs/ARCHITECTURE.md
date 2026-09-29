# Evora_Police — Architecture & File Plan

> Development step 4 of the master specification.

## 1. Principles

1. **Server-authoritative.** The client renders UI and performs local effects only. Every
   decision (permission, scope, duty, target distance, confirmation ownership, timers,
   money, inventory) is taken on the server.
2. **One organisational model.** `رئاسة الوزراء → الوزارات → القطاعات → الرتب → الصلاحيات → الأفراد`.
   Groups come from the server's `groups.lua`; Evora only maps them.
3. **Adapters, not assumptions.** Every server system (menu, notify, popup, radio, inventory,
   garage, clothing, cuffs, drag, chat, database) is reached through an adapter.
4. **Identity rule.** Displayed name = FiveM name (`GetPlayerName`). Displayed id = vRP `user_id`.
5. **Persist everything that matters.** Attendance, vacations, reports, wanted, fines, jail,
   impound and statistics live in MySQL and survive resource and server restarts.

## 2. Layers

```
 NUI (web/)  ──fetch──▶  client Lua  ──evora_police:rpc──▶  RPC dispatcher (server/core/rpc.lua)
                                                              │  resolve source → vRP user_id
                                                              │  rate limit, feature flag, payload checks
                                                              ▼
                                                      Authority engine (server/government.lua)
                                                              │  grants, permissions, scope
                                                              ▼
                                                   Domain modules (fines, jail, affairs, ...)
                                                              │
                        ┌──────────────┬───────────────┬──────┴───────┬───────────────┐
                        ▼              ▼               ▼              ▼               ▼
                 Framework bridge   Adapters        Database       Logs/Webhooks   Client events
                 (vRP legacy/modern) (integrations)  (4 drivers)    (server only)   (UI, effects)
```

Clients never call domain code directly: there is exactly one inbound network event
(`evora_police:rpc`). Each handler is registered with its feature flag, required permission
and rate limit, so an unregistered or unauthorised call is rejected before domain code runs.

## 3. Authority model

At start-up `Config.Government` is compiled into a rank index:

```
rank = { group, label, level = "prime" | "ministry" | "sector", ministry, sector, order }
```

* `order` is the position of the rank inside its container (1 = most senior).
* Sector ids are namespaced (`Interior.PublicSecurity`) so two ministries may reuse a key.
* `Config.Roles` attaches permissions to ranks. A rank listed in several roles receives the union.

A player's **profile** is the list of ranks (grants) they currently hold, resolved from live vRP
groups for every sensitive request. A grant covers a target rank when:

| Grant level | Covers |
|---|---|
| Prime ministry | every ministry-level and sector-level rank; junior prime ranks |
| Ministry *M* | every sector-level rank in *M*'s sectors; junior ministry ranks of *M* |
| Sector *S* | junior ranks of sector *S* only |

"Junior" follows `Config.Hierarchy.SameContainer` (`"junior"` by default, `"all"` or `"none"`).
A check always pairs the **permission and the scope of the same grant**, so holding `recruit`
in one sector and a plain rank in another never leaks `recruit` into the second sector.

Scoped permissions: `recruit`, `dismiss`, `recall`, `monitor`, `vacationBalance`,
`officerInquiry`, `resetAttendance`, `resetFines`, `resetData`, `statistics`, `vacationBreak`.
Everything else (`fines`, `jail`, `wanted`, ...) is a plain capability.

## 4. Data model

| Table | Purpose |
|---|---|
| `evora_police_players` | FiveM name + avatar cache per vRP id (offline display) |
| `evora_police_officers` | rank snapshot, military code, attendance, counters, vacation balance, duty session |
| `evora_police_attendance` | one row per closed duty session |
| `evora_police_vacations` | vacation periods with the exact original groups |
| `evora_police_pending` | group changes queued for offline players (restore / dismissal) |
| `evora_police_reports` | citizen reports and their workflow status |
| `evora_police_wanted` | wanted persons |
| `evora_police_fines` | issued fines and payment status |
| `evora_police_jail` | active sentences (remaining time, saved clothing, cuff state) |
| `evora_police_jail_history` | finished sentences and releases with reasons |
| `evora_police_impounds` | impounded vehicles, fees, releases |
| `evora_police_logs` | every administrative / sensitive action |

All times are stored as UNIX seconds.

## 5. Reusable services

| Service | File | Used by |
|---|---|---|
| Confirmation (F5 / F6) | `server/confirm.lua` + `client/confirm.lua` | fines, jail, jail edits, recall, impound, release, dismissal, resets, ID card, field actions |
| Spectate | `server/spectate.lua` + `client/spectate.lua` | officer monitoring, prisoner monitoring |
| Menu | `server/core/menu.lua` | Builder Menu (vRP) or Evora NUI menu |
| Popup | `server/core/integrations.lua` | every text / number input |
| Target picker | `server/field.lua` | fines, jail, field actions |

Confirmation requests carry a random id, the expected responder and an expiry. The server
accepts an answer only from that responder, only once, only before expiry, and domain flows
re-validate distance / permission after the answer arrives.

## 6. File plan

```
Evora_Police/
├── fxmanifest.lua
├── README.md
├── sql/evora_police.sql              schema (also auto-created on start)
├── config/                           shared config (client + server)
│   ├── config.lua                    general, features, duty, vacation, broadcast, recall, reset, stats, UI
│   ├── government.lua                hierarchy
│   ├── permissions.lua               roles → permissions
│   ├── fines.lua  jail.lua  impound.lua  field.lua
│   ├── equipment.lua  uniforms.lua  security.lua
│   ├── integrations.lua              adapters
│   ├── locale.lua                    every text
│   └── server.lua                    SERVER ONLY: webhooks, tokens
├── shared/utils.lua
├── server/
│   ├── core/  bootstrap, framework, database, players, rpc, logs, integrations, menu
│   ├── government.lua  confirm.lua  spectate.lua
│   ├── officers.lua  vacation.lua  affairs.lua  statistics.lua  ipad.lua
│   ├── reports.lua  wanted.lua  citizens.lua  fines.lua  jail.lua
│   ├── field.lua  equipment.lua  security.lua  barricades.lua  impound.lua
│   ├── policemenu.lua                Builder Menu tree
│   └── main.lua                      start-up, lifecycle, exports
├── client/
│   ├── main.lua                      RPC client, NUI bridge, focus stack, state
│   ├── integrations.lua              client-side adapters (builtin cuff/drag/seats/clothing)
│   ├── ui.lua  confirm.lua  ipad.lua  spectate.lua  jail.lua
│   ├── field.lua  security.lua  barricades.lua  points.lua
└── web/  index.html  css/app.css  js/icons.js  js/app.js  js/ipad.js  assets/
```

Development-only folders at the repository root: `docs/` and `tests/` (Lua test harness that
mocks FiveM + vRP and runs the server modules against a real MariaDB).

## 7. Security model

* One inbound net event, dispatched through a registry (feature flag, permission, duty,
  rate limit, payload validation).
* `local src = source` is captured before any yield in every handler.
* Targets are validated server-side: online, correct `user_id`, distance from server-side
  ped coordinates (OneSync), within the administrator's scope.
* State after an asynchronous wait (confirmation, popup) is re-validated before acting.
* Webhook URLs, bot tokens and database access exist only in server scripts.
* All strings shown in NUI are rendered with `textContent`; Discord output is escaped.
* No client event can change jail time, money, groups, inventory or statistics.

## 8. Performance model

| Loop | Interval | Work |
|---|---|---|
| Jail timer (server) | 1 s | decrement online prisoners in memory |
| Jail escape check (server, OneSync) | 2 s | distance for online prisoners only |
| Jail persistence | 30 s | batched updates |
| Duty heartbeat | 60 s | one batched `UPDATE ... WHERE user_id IN (...)` |
| Vacation expiry | 60 s | in-memory list of active vacations |
| Client interaction points | 750 ms far / per frame within 15 m | markers, hints |
| Security alert (client) | 400 ms | only while an alert exists; per-frame effects only while affected |
| Confirmation keys (client) | per frame | only while a prompt is visible |

NUI timers run only while their layer is visible.

## 9. Restart safety

On start the resource re-attaches every online player: rebuilds the online map, resolves
profiles, resumes duty sessions from `duty_started_at`, re-applies active jail sentences
(without overwriting the saved original clothing), restores due vacations and applies queued
group changes. Duty sessions of players who left while the server was down are closed using
the last heartbeat, so downtime is never counted as attendance.
