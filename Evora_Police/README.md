# Evora_Police

**Evora** police and government operations platform for **Universal vRP** servers.
Arabic RTL interface, server-authoritative and fully configurable.
Made By **LR**.

```
رئاسة الوزراء  →  الوزارات  →  القطاعات  →  الرتب  →  الصلاحيات  →  الأفراد
```

---

## Contents

1. [Features](#features)
2. [Requirements](#requirements)
3. [Installation](#installation)
4. [Configuration files](#configuration-files)
5. [Hierarchy and permissions](#hierarchy-and-permissions)
6. [Integrations](#integrations)
7. [Garage integration (impound)](#garage-integration-impound)
8. [Exports](#exports)
9. [Keys and commands](#keys-and-commands)
10. [Logs and Discord webhooks](#logs-and-discord-webhooks)
11. [Security model](#security-model)
12. [Troubleshooting](#troubleshooting)
13. [Testing (developers)](#testing-developers)
14. [Credits](#credits)

---

## Features

**Builder Menu (vRP main menu)**
* **الشرطة**: shown only to configured police and government ranks, and to officers on
  vacation. It has 11 entries, each with its own `enabled` switch and permission:
  * القائمة العسكرية
  * تسجيل الدخول / الخروج
  * استعلام عن مواطن
  * تعميم بلاغ
  * المخالفات
  * السجن
  * خيارات الميدان
  * الأدوات الأمنية
  * استعلامات
  * حجز المركبات
  * الحواجز
* **إبلاغ عن مجرم**: available to every player.

**القائمة العسكرية (police iPad)**
* **مكتبي**: duty clock, session and total attendance, fines and jail counters, service
  activity, military / radio code, vacations with balance.
* **المتصلين**: clocked-in officers with rank, sector, code and session time.
* **البلاغات**: citizen reports with status workflow (جديد → مستلم → قيد المعالجة → مغلق)
  and waypoint.
* **مطلوبين الدولة**: wanted list with live alerts and a quick-open key.
* **الشؤون**: the administrator's control centre, always limited to their own scope:
  * recruitment and dismissal (online or offline, queued until the player joins)
  * broadcasts to officers or citizens
  * officer recall with F5/F6
  * live monitoring (spectate)
  * vacation balance
  * officer inquiry
  * attendance, fines and data resets
  * a combined Top 10 that can be sent to Discord

**Field and justice**
* **Fines**: categories, target acceptance with F5/F6, payment points, chat announcements.
* **Jail**: centre, perimeter and escape handling, prison clothing saved and restored,
  handcuffs, work tasks with skill checks and reduction caps. Sentences survive restarts and
  disconnects.
* **Field options**: cuff, seize weapons, drag, search, vehicle-trunk search and contraband
  seizure, put in / pull out of a vehicle, identity card.
* **Security tools**: equipment kits, uniforms, security alert. Players already inside the zone
  when an alert starts are not affected; players who enter afterwards are.
* **Vehicle impound**: fees and centres. Works with your existing garage and never replaces it.
* **Barricades**: preview placement, per-officer and global limits, lifetime.

**Platform**
* Every name shown is the **FiveM name**. Every id shown is the **vRP `user_id`**.
  Character names and FiveM sources are never displayed.
* Everything that matters is stored in MySQL and survives restarts: attendance, vacations,
  reports, wanted notices, fines, jail, impounds, statistics and logs.
* Every text lives in `config/locale.lua`.

---

## Requirements

| | |
|---|---|
| FiveM server | recent artifact, `lua54` |
| vRP | Universal vRP / vRP 0.5 family. Both calling conventions are detected automatically (`vRP.fn({args})` and `vRP.fn(args...)`). |
| Database | one of: **oxmysql**, **mysql-async**, **ghmattimysql**, or your own functions (`Config.Database.Driver = "custom"`) |
| OneSync | **Strongly recommended.** It gives server-side distances, vehicle validation and escape detection. Without it Evora still works, using client reports that the server re-checks. |

---

## Installation

1. Copy the `Evora_Police` folder into your `resources` directory. Keep the folder name.
2. In `server.cfg`, start it **after** vRP and your database resource:
   ```cfg
   ensure oxmysql      # or mysql-async / ghmattimysql
   ensure vrp
   ensure Evora_Police
   ```
3. **Database.** The `evora_police_*` tables are created automatically on start
   (`Config.Database.AutoCreateTables = true`). To create them yourself, import
   `sql/evora_police.sql`.
4. **Groups.** Evora_Police never creates groups. Every rank you map in
   `config/government.lua` must already exist in `vrp/cfg/groups.lua`, and so must the
   vacation group. Example:
   ```lua
   ["ps_commander"]    = { _config = { gtype = "job" }, "police.ps_commander" },
   ["ps_officer"]      = { _config = { gtype = "job" }, "police.ps_officer" },
   ["police_vacation"] = { },  -- Config.Vacation.InactiveGroup (no gtype)
   ```
   The console lists every mapped group that is missing from `groups.lua` at start-up.
5. **Hierarchy.** Map your ministries, sectors and ranks in `config/government.lua`, then
   give roles to ranks in `config/permissions.lua`. See
   [Hierarchy and permissions](#hierarchy-and-permissions).
6. **Webhooks.** Fill `config/server.lua`. This file is server-only and never reaches clients.
7. **Integrations.** Check `config/integrations.lua`: notifications, popup, inventory, garage
   lookup, money, clothing, handcuffs and so on. The defaults use vRP. See
   [Integrations](#integrations).
8. **Places.** Set coordinates for the jail (`config/jail.lua`), fine payment points
   (`config/fines.lua`), impound centres (`config/impound.lua`) and alert zones
   (`config/security.lua`).
9. Start the server and read the console. Evora prints one line per missing integration or
   group and a summary:
   `ready — N ministries, N sectors, N ranks`.

---

## Configuration files

| File | Loaded on | Contents |
|---|---|---|
| `config/config.lua` | client + server | framework, OneSync, database, feature switches, duty, military code, vacations, targeting, F5/F6 confirmation, broadcasts, recall, resets, statistics weights, reports, wanted, spectate, iPad, ID card, chat templates, UI |
| `config/government.lua` | client + server | رئاسة الوزراء → الوزارات → القطاعات → الرتب, same-level management rule |
| `config/permissions.lua` | client + server | roles, inheritance, rank → role mapping |
| `config/fines.lua` | client + server | categories, fines, payment points, auto-charge |
| `config/jail.lua` | client + server | centre, radius, entry/exit, reasons, clothing, handcuffs, escape rules, tasks |
| `config/impound.lua` | client + server | reasons, fees, centres |
| `config/field.lua` | client + server | per action: enabled, permission, confirmation, requires-cuffed; contraband list |
| `config/equipment.lua` | client + server | kits, restrictions by sector or rank, return mode |
| `config/uniforms.lua` | client + server | uniform presets |
| `config/security.lua` | client + server | security alert zones and effects, barricade props and limits |
| `config/integrations.lua` | client + server | every adapter (see below) |
| `config/locale.lua` | client + server | every text (server, menus and NUI) |
| `config/server.lua` | **server only** | Discord webhooks, log options, secrets (bot token, Steam key) |

`Config.Debug = true` prints permission, group, integration, database, jail, impound and
spectate diagnostics. Keep it `false` in production.

---

## Hierarchy and permissions

* **Scope** comes from the level of the rank:

  | Rank level | Manages |
  |---|---|
  | Sector rank | its own sector only |
  | Ministry rank | every sector of its ministry |
  | Prime ministry | every configured ministry and sector |

* **Same-level management** is set by `Config.Hierarchy.SameContainer`:
  * `"junior"` (default): ranks listed below it
  * `"all"`: every rank of the same container
  * `"none"`: lower levels only

  The order of `ranks` inside a sector is its seniority, most senior first. A deputy
  therefore cannot dismiss the commander.
* **Permissions** come from roles in `Config.Roles`. A rank listed in several roles gets all
  of them. `inherits` copies another role, `false` removes an inherited permission, and the
  shorthands `all`, `broadcast` and `reset` are available.
* **Management permissions** only apply to officers inside the administrator's scope:
  `recruit`, `dismiss`, `recall`, `monitor`, `vacationBalance`, `vacationBreak`,
  `officerInquiry`, `resetAttendance`, `resetFines`, `resetData` and `statistics`.
  Officers outside the scope are never listed in the UI, and the server refuses them anyway.

---

## Integrations

Every server system is reached through an adapter in `config/integrations.lua`. Each one can
be switched to `"custom"` with your own functions. A missing resource is reported once in the
console and the feature degrades gracefully.

| Adapter | Types | Used for |
|---|---|---|
| `BuilderMenu` | `vrp`, `builtin` (NUI menu, command `evora` / F7) | الشرطة, إبلاغ عن مجرم |
| `Notify` | `vrp`, `event`, `client_export`, `builtin`, `custom` | every notification |
| `Popup` | `vrp` (`vRP.prompt`), `builtin` (NUI dialog), `custom` | ids, reasons, amounts |
| `Radio` | `none`, `statebag`, `event`, `client_export`, `custom` | military code → radio / callsign |
| `Inventory` | `vrp`, `custom` | search, contraband, kits |
| `Weapons` | `vrp`, `builtin`, `custom` | seize, kits, equipment return |
| `VehicleInventory` | `vrp_chest`, `custom` | trunk search and seizure |
| `VehicleGarage` | `sql`, `export`, `custom` | plate → owner and model |
| `VehicleImpound` | `evora` (garage calls Evora exports), `sql` hooks, `custom` | impound status in your garage |
| `Clothing` | `vrp`, `builtin`, `custom` | jail clothing, uniforms |
| `Handcuff` / `Drag` / `Seats` | `vrp` / `builtin` / `event` / `custom` | field options |
| `Money` | `vrp`, `custom` | fines, impound fees |
| `Chat` | `chat` (`chat:addMessage`), `custom` | fine and jail announcements |
| `Job` | `vrp` (group gtype `Config.Framework.JobGroupType`), `custom` | citizen job |
| `ProfileImage` | `none`, `url`, `discord`, `steam`, `custom` | avatars in the iPad and ID card |

---

## Garage integration (impound)

Evora_Police never replaces your garage. The owner of a plate is found with
`VehicleGarage` (by default through SQL on the vRP 0.5 tables, with `platePrefix = "P "`).
Your garage then asks Evora before spawning a vehicle:

```lua
-- server side of your garage, before spawning `vehicleName` for `user_id`
local status = exports["Evora_Police"]:GetImpoundStatus(user_id, vehicleName) -- or the plate
if status then
    -- status = { impounded = true, plate, location, fee, reason, message }
    vRPclient.notify(source, { status.message })
    return
end
```

Other exports: `IsVehicleImpounded(plate)` and `GetImpoundedVehicles(ownerId)`.

A garage that keeps its own impound column can use `VehicleImpound.type = "sql"`. It fills
the `onImpound` / `onRelease` queries with the `@owner @model @plate @id` placeholders.

Owners pay the fee at an impound centre (marker + **E**). Officers with `impoundRelease` can
release a vehicle from the menu.

---

## Exports

All exports are server-side. `user_id` is always the vRP user id.

| Export | Returns |
|---|---|
| `IsOnDuty(user_id)` | boolean |
| `IsJailed(user_id)` | boolean |
| `IsOnVacation(user_id)` | boolean |
| `GetOfficerProfile(user_id)` | `{ military, rank, group, level, sector, sectorLabel, ministryLabel, permissions, onDuty }` |
| `HasPermission(user_id, perm)` | boolean |
| `IsVehicleImpounded(plate)` | boolean |
| `GetImpoundStatus(ownerId, plateOrModel)` | `nil` or a status table |
| `GetImpoundedVehicles(ownerId)` | list |

---

## Keys and commands

| Key / command | Action |
|---|---|
| **F5** / **F6** | accept / reject a confirmation (`Config.Confirm`) |
| **E** | interact: payment point, impound centre, jail task, place a barricade |
| **G** | open the wanted page from a wanted alert (`Config.Wanted.QuickOpen`) |
| **BACKSPACE** | stop monitoring (spectate) |
| `evora` / **F7** | builtin menu, only when `BuilderMenu.type = "builtin"` |
| `Config.Ipad.Command` | optional command (and key) to open the iPad |
| `evora_stopspectate` | emergency stop for monitoring |

---

## Logs and Discord webhooks

* Every sensitive action is stored in the `evora_police_logs` table (`Config.Logs.Database`).
* Each category can have its own webhook, falling back to `general`:
  * `recruitment`
  * `affairs`
  * `attendance`
  * `reports`
  * `wanted`
  * `fines`
  * `jail`
  * `impound`
  * `field`
  * `security`
  * `statistics`
* Webhooks are sent server-side through a rate-limited queue, and they never ping anyone.
* Webhook URLs and tokens live only in `config/server.lua`, which clients never download.

---

## Security model

* **The server decides everything.** The client renders the UI and plays local effects.
  Permissions, scope, duty, targets, distances, confirmations, timers, money, inventory,
  groups and statistics are all decided server-side from live vRP data. Hiding a button is
  never the protection.
* **Two inbound network events.**
  * `evora_police:rpc` goes through a registry that applies the rate limit, cooldown, feature
    switch, permission, duty and payload checks.
  * `evora_police:cres` only answers a question the server asked that same client.
* **Confirmations are bound to their responder.** Only the expected player can answer, only
  once, and only before expiry. Every flow re-checks the officer and the target after any wait.
* The full review is in `docs/REVIEW.md` (repository), including what OneSync changes.

---

## Troubleshooting

| Console message | Meaning |
|---|---|
| `vRP unavailable (...)` | `Config.Framework.Resource` does not match your vRP folder, or vRP is not started before Evora. |
| `Database unavailable (driver '...')` | No supported driver is started. Set `Config.Database.Driver` or start oxmysql, mysql-async or ghmattimysql first. |
| `Groups missing from vrp/cfg/groups.lua: ...` | A group mapped in `config/government.lua` does not exist in `vrp/cfg/groups.lua`. |
| `Vacation group '...' is missing from vrp/cfg/groups.lua.` | Add `Config.Vacation.InactiveGroup` to `groups.lua`. |
| `Unknown permission '...' in role '...'` | Typo in `config/permissions.lua`. |
| `<Name> integration unavailable.` | The adapter's resource is missing. Switch the adapter type or install the resource. |

When a menu entry is missing for a player, set `Config.Debug = true`. The console then
prints each player's resolved ranks and every refused permission.

---

## Testing (developers)

The repository contains a test suite. It is not needed on a live server.

```bash
lua5.4 tests/run.lua                                        # server specs against MariaDB
lua5.4 tests/client_smoke.lua                               # client scripts with mocked natives
NODE_PATH=tests/ui/node_modules node tests/ui/preview.js    # screenshots of every NUI screen
```

---

## Credits

* Evora_Police — **Made By LR**.
* Font: [Tajawal](https://fonts.google.com/specimen/Tajawal), SIL Open Font License
  (`web/assets/fonts/OFL.txt`), bundled so the UI works offline.
