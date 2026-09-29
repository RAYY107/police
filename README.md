# Evora_Police — repository

A police and government operations platform for Universal vRP (FiveM). Made By LR.

| Path | What it is |
|---|---|
| [`Evora_Police/`](Evora_Police/) | The FiveM resource. Copy this folder to your server. Installation and configuration: [`Evora_Police/README.md`](Evora_Police/README.md). |
| [`docs/INTEGRATION_MAP.md`](docs/INTEGRATION_MAP.md) | Steps 1–3: analysis, vRP API identification, integration map |
| [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) | Step 4: architecture, data model, security and performance model |
| [`docs/REVIEW.md`](docs/REVIEW.md) | Steps 9–11: security, performance and UI review with findings and fixes |
| [`tests/`](tests/) | Development-only test suites (not needed on a server) |

## Tests

```bash
# Server: 129 specs against a real MariaDB
# (defaults: database evora_test, user evora / evora on localhost;
#  override with EVORA_DB, EVORA_DB_USER, EVORA_DB_PASS, EVORA_DB_HOST)
lua5.4 tests/run.lua

# Client: every client script against mocked natives (59 checks)
lua5.4 tests/client_smoke.lua

# NUI: renders every screen in headless Chromium → tests/ui/shots/
# (CHROMIUM=/path/to/chrome to use a specific browser)
(cd tests/ui && npm install)
NODE_PATH=tests/ui/node_modules node tests/ui/preview.js

# Regenerate the shipped SQL file / UI locale fixture after schema or locale changes
lua5.4 tests/tools/export_schema.lua
lua5.4 tests/tools/export_ui_locale.lua > tests/ui/init.json
```

The server suite needs `lua-sql-mysql` and a running MariaDB or MySQL server. It mocks FiveM
and both vRP calling conventions. Everything runs on virtual time, so tests covering
sentences, vacations and cooldowns take seconds.
