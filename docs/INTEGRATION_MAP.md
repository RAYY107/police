# Evora_Police — Integration Map

> Development steps 1–3 of the master specification: analysis, API identification and integration map.

## 1. Analysis of the existing structure

The `police` repository was empty when development started (no commits, no server files,
no `vrp`, `groups.lua`, garage, radio or inventory resources to inspect). Evora_Police is a
**resale product for many different vRP servers**, not a script for one server. The
integration layer is therefore built against the **published vRP 0.5 APIs**, and every
server-specific system sits behind an isolated, swappable adapter.

What the resource inspects at runtime on the buyer's server:

| What | How | Why |
|---|---|---|
| vRP calling convention | reads `vrp/lib/Proxy.lua` (`proxy_rdata` / `(args,callback)` ⇒ legacy) | Selects table-args vs varargs calls automatically |
| `groups.lua` | `module("vrp", "cfg/groups")` (protected call) | Validates every group referenced in `config/government.lua`, reads group titles |
| OneSync | `onesync` / `onesync_enabled` convars | Enables server-side coordinates, entity checks, server teleports |
| Database driver | resource state of `oxmysql`, `mysql-async`, `ghmattimysql` (or `Config.Database.Custom`) | Picks the first running driver |
| Each integration resource | `GetResourceState(...)` | Logs `[Evora_Police] <X> integration unavailable.` instead of crashing |

## 2. vRP API identification

vRP 0.5 exists in two calling conventions that are not compatible with each other.
Evora_Police supports both through one bridge (`server/core/framework.lua`).

| Purpose | Legacy (dunko-style, table args) | Modern (varargs, async lib) |
|---|---|---|
| User id from source | `vRP.getUserId({src})` | `vRP.getUserId(src)` |
| Source from user id | `vRP.getUserSource({uid})` | `vRP.getUserSource(uid)` |
| Online users | `vRP.getUsers({})` | `vRP.getUsers()` |
| Groups | `getUserGroups`, `hasGroup`, `addUserGroup`, `removeUserGroup`, `getUserGroupByType` with `{...}` | same, varargs |
| Money | `tryPayment`, `tryFullPayment`, `giveMoney`, `getBankMoney`, `setBankMoney` | same |
| Inventory | `getUserDataTable`, `getInventoryItemAmount`, `tryGetInventoryItem`, `giveInventoryItem`, `getItemName` | same |
| Server data (vehicle chests) | `getSData({key, cb})`, `setSData({key, value})` | `getSData(key)`, `setSData(key, value)` |
| Menus (Builder Menu) | `registerMenuBuilder({"main", fn})`, `openMenu({src, menu})`, `closeMenu({src})` | same, varargs |
| Prompt | `prompt({src, title, default, cb})` | `prompt(src, title, default)` |
| Client tunnel | `vRPclient.fn(src, {args}, cb)` | `vRPclient.fn(src, ...)` / `vRPclient._fn(src, ...)` |
| Lifecycle events | `vRP:playerSpawn(uid, src, first)`, `vRP:playerLeave(uid, src)`, `vRP:playerJoinGroup/LeaveGroup(uid, group, gtype)` | same |

Rules the bridge enforces:

* Legacy callback functions (`prompt`, `getSData`, client tunnel with results) are wrapped in
  promises **with timeouts**, so a disconnected player can never hang a server thread.
* vRP callbacks that enter Evora_Police (menu builders, menu choices) never yield inside the
  callback; work is moved to a fresh thread first.
* Player **names are always `GetPlayerName(source)`** (FiveM name) and player **ids are always
  the vRP `user_id`**. Character identity (`vrp_user_identities.firstname/name`) is never read.

## 3. Integration map

Every adapter is configured in `Evora_Police/config/integrations.lua`. The `custom` type
of every adapter accepts plain Lua functions, so any server can be wired without editing
Evora_Police code.

| Integration | Config key | Default adapter | Other adapters | Runs on | Behaviour when missing |
|---|---|---|---|---|---|
| vRP core | `Config.Framework` | `vrp`, calling style `auto` | `legacy`, `modern` forced | server | Logs error; police features stay disabled |
| Database | `Config.Database` | `auto` | `oxmysql`, `mysql-async`, `ghmattimysql`, `custom` | server | Logs error; persistence disabled |
| Builder Menu | `Config.Integrations.BuilderMenu` | `vrp` (`registerMenuBuilder("main")`) | `builtin` (Evora NUI menu + command/key) | server | Falls back to `builtin` |
| Notify | `Config.Integrations.Notify` | `vrp` (`vRPclient.notify`) | `event`, `client_export`, `builtin`, `custom` | server / client | Falls back to Evora toast |
| Popup / input | `Config.Integrations.Popup` | `vrp` (`vRP.prompt`, sequential fields) | `builtin` (multi-field NUI dialog), `custom` | server | Falls back to `builtin` |
| Radio (military code) | `Config.Integrations.Radio` | `none` (stored + shown + state bag) | `statebag`, `event`, `client_export`, `custom` | server / client | Code still stored and displayed |
| Inventory | `Config.Integrations.Inventory` | `vrp` | `custom` | server | Search / contraband disabled with message |
| Weapons | `Config.Integrations.Weapons` | `vrp` (`getWeapons` / `giveWeapons`) | `builtin` (natives), `custom` | server / client | Seizure / equipment disabled |
| Vehicle inventory | `Config.Integrations.VehicleInventory` | `vrp_chest` (`chest:u{owner}veh_{model}`) | `custom` | server | Vehicle search disabled |
| Vehicle garage | `Config.Integrations.VehicleGarage` | `sql` (vRP registration plates) | `sql` presets, `export`, `custom` | server | Impound disabled |
| Vehicle impound | `Config.Integrations.VehicleImpound` | `evora` (exports for garages) + optional SQL hooks | `custom` | server | Evora records still authoritative |
| Clothing | `Config.Integrations.Clothing` | `vrp` (`get/setCustomization`) | `builtin` (natives), `custom` | server / client | Jail clothing / uniforms disabled |
| Handcuff | `Config.Integrations.Handcuff` | `vrp` (`isHandcuffed` / `setHandcuffed`) | `builtin`, `custom` | server / client | Falls back to `builtin` |
| Drag | `Config.Integrations.Drag` | `builtin` (attach) | `event` (e.g. `gggh`), `custom` | server / client | — |
| Vehicle seats | `Config.Integrations.Seats` | `vrp` (`putInNearestVehicleAsPassenger` / `ejectVehicle`) | `builtin`, `custom` | server / client | Falls back to `builtin` |
| Money | `Config.Integrations.Money` | `vrp` | `custom` | server | Payments disabled |
| Chat | `Config.Integrations.Chat` | `chat` (`chat:addMessage`) | `custom` | server | Announcements skipped |
| Job label | `Config.Integrations.Job` | `vrp` (group with `gtype = "job"`) | `custom` | server | Shows `—` |
| Profile image | `Config.Integrations.ProfileImage` | `none` (Evora avatar) | `url`, `discord`, `steam`, `custom` | server | Default avatar |
| Discord | `config/server.lua` (server only) | webhooks per category | — | server | Logs kept in database |

### Garage contract (impound)

Evora_Police never replaces a garage. It exposes server exports that the existing garage
calls before spawning a vehicle, plus optional SQL hooks for garages that keep their own
impound column:

```lua
exports["Evora_Police"]:IsVehicleImpounded(plate)           -- boolean
exports["Evora_Police"]:GetImpoundStatus(ownerUserId, plateOrModel) -- nil | { impounded = true, location = "...", fee = 5000, message = "..." }
```

### What a server owner verifies after installing

1. The groups referenced in `config/government.lua` exist in `vrp/cfg/groups.lua`
   (the console lists every missing group at start-up).
2. `Config.Vacation.InactiveGroup` exists in `groups.lua`.
3. The garage lookup in `config/integrations.lua` matches the garage table (plate column, owner column).
4. Webhook URLs are filled in `config/server.lua` (never sent to clients).
