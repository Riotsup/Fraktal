# fraktal-hmi — Generic Operator HMI (Flutter, Material 3)

Implements `HMI_CONTRACT.md` / Core §3.13: the client is **generic** — it walks the
module forest and renders it; a station adds zero HMI code.

## Platforms
One codebase for **Windows, Linux, Android, Web**. Platform folders for
**windows** and **web** are generated; add the others as needed:
```
flutter create . --platforms=linux,android   # adds the remaining platform folders
flutter run -d windows|linux|<device>|chrome
```
The UI remains repository-driven and dependency-light. Flutter's SDK localization
delegates provide locale-aware widgets; `file_picker` supplies cross-platform CSV/PDF
open/save dialogs, `pdfrx` supplies the embedded cross-platform PDF viewer, and the
Flutter-published `cupertino_icons` asset completes its platform controls. Versions
are pinned in `pubspec.lock`. (`analysis_options.yaml` remains self-contained.)
Windows plugin builds require Windows Developer Mode because Flutter creates plugin
symlinks (`Settings > System > For developers`).

## Localization and module content

First run now precedes connection setup with language selection. The detected device
language is enabled by default; operators can switch among enabled languages. An ADMIN
can import/export a UTF-8 CSV for each language in two independent scopes: Fraktal
standard strings and project strings. Every UI `Text` path resolves through the runtime
catalog, while PLC-facing display fields are stable `std.*`/`project.*` keys.

Each module detail has a localizable Information section and optional PDFs. ENGINEER or
ADMIN can upload, ADMIN can delete, and ADMIN configures the minimum access level for
Information, Operations, Diagnostics, Configuration, Documentation, and History. The
shipped content store is local; production fleets should supply a shared `ContentStore`
adapter as specified in `Specification/LOCALIZATION_AND_MODULE_CONTENT.md`.

**Transport per platform:** the UI binds only `PlcRepository` (`lib/data/plc_repository.dart`).
- `SimRepository`: full live demo everywhere.
- Windows: native open62541 1.4.12 client through a small C ABI and a dedicated Dart worker isolate.
- Linux/Android: the same C ABI is source-compatible; runner packaging remains.
- **Web:** `WebGatewayOpcUaClient` implements the same snapshot/write session over the versioned Fraktal WebSocket gateway protocol.

See `Specification/OPCUA_TRANSPORT.md` for the ABI, snapshot schema, gateway
messages, security boundary, and acknowledged PLC mailbox.

## Connection startup

The operator shell is fail-closed behind `ConnectionBootstrap`:

- first use, corrupt settings, or settings that have never reached `LIVE` open step 1 of the connection wizard;
- after the endpoint is live, step 2 discovers root Units and requires the local HMI assignment;
- the assignment filters the module/fieldbus views and rejects writes outside its root paths;
- an authenticated ADMIN can edit the Unit assignment later; missing saved paths reopen step 2 fail-closed;
- a previously proven connection starts on a full-screen **Connecting to PLC** view;
- no module controls are built while the link is connecting, stale, or down;
- after 30 seconds without `LIVE`, **Edit connection settings** becomes available;
- losing a live link immediately returns to the blocking screen; writes are not queued;
- native settings are stored as JSON under the user configuration directory; Web uses browser local storage.

The built-in simulation is selectable in the wizard. On Windows use a complete
`opc.tcp://host:port` endpoint. Web builds require a deployed `ws://` or
`wss://` Fraktal gateway; the browser client is included, but the gateway is a
separate deployment service.

Connection startup logs each stage to the Flutter debug console with the
`[Fraktal/Connection]` prefix: settings load, endpoint and transport, TCP
preflight target/result, repository creation, subscription state, and link-state
transitions. A successful ping is not sufficient. Native OPC UA normally needs
the TwinCAT OPC UA Server (TF6100) listening at an `opc.tcp://host:port`
endpoint; ADS Router port 48898 is not an OPC UA endpoint. Startup advances
through TCP preflight, native repository creation or Web-gateway handshake,
Fraktal discovery, and live-state publication instead of waiting indefinitely.

## What's demonstrated (SimRepository)
- **Forest** (§3.1a): two roots (`StationA` running MODEL-A, `ConveyorB` running MODEL-B); scope selector = whole forest or one station.
- **Shrinkable tree** (left): expand/collapse per node, collapsible to an icon rail.
- **Event path highlighting** (§3.13): CylB error tints `StationA → ClampStation → CylB` red (source strongest); a conveyor warning tints its path amber; a robot message tints blue. Severity = subtree max (error > warning > info).
- **§8.3 lifecycle**: blocked banner (MANUAL_RESET), Operator reset (first click = condition gone → *awaiting reset*; second = closes into history **with duration**), history list gated by `ALARM_HISTORY`.
- **§7.7 access**: fully-open default; login (`op1/1111`, `tech1/4711`, `eng1/9999`, `admin1/2468`); controls grey below threshold; ADMIN can edit the local Unit assignment; theme changing is level-gated HMI config (`HmiConfig.themeMinLevel`, default open).

## Honest status
Verified against Flutter 3.44.5 (2026-07-12): `flutter analyze` clean, the
SimRepository boot smoke test passes (`flutter test`), and `flutter build web`
succeeds. Enum **ordinals in `lib/domain/types.dart` are the PLC contract**
(must match the Core DUTs) and are the first thing to verify against a real server.

## Widget set & annex coverage

The HMI is generic: it renders whatever a module publishes. The annexes are PLC
worked examples, not screens — but several publish typed data the detail view
surfaces automatically (a facet card appears only when its data is present):

| Annex | Publishes | HMI widget |
|-------|-----------|------------|
| A Separator CM · B Clamp EM | Status/state/first-out | tree tile + Status strip (all modules) |
| C Station Unit | mode, model, counters, stall | Unit controls + cycle profile |
| D External device link | `Linked`/`LastSeen`/`LinkReason` | `LinkCard` |
| E Traceability/MES | `ST_PartContext`/`Verdict`/`ST_MeasRecord` | `PartCard` (verdict + measured records vs limits) |
| F PackML profile | `E_PackMLState` | `PackMLCard` |
| G Motion · I Robot | actual/target position, velocity, homed | `MotionCard` |
| H TcUnit | (test-only — no runtime HMI) | — |

Standalone views from the standard's HMI clauses:
- **Cycle profile** (§8.11.4): `cycle_profile_view.dart` — waterfall coloured by
  time class, header split Total / **Work (real cycle time)** / Wait.
- **Config editor** (§3.8a): `config_and_history.dart` — ParCfg vs StationCfg
  grouped; edit gated by `DATA_WRITE`, re-checked in PLC.
- **History browser** (§8.3): filterable by kind, durations, reset class.
- **Decision prompt** (§6.11): typed request, answer written back.

All facet/view data is defined in `lib/domain/types.dart` as optional classes;
the sim populates representative values so every widget is exercisable now.

## HMI-completeness pass (audit-driven)

A coverage audit against the contract and common HMI patterns added:
- **Plant overview** (`overview_and_indicators.dart`) — dashboard-first landing: one card per root (state, model, mode, counters, worst severity). Tap to drill in; the app-bar dashboard icon / title returns here.
- **Current-step card** (§6.5/§6.9) — live StepNo/name, awaiting-label, failing named conditions, STARVED/BLOCKED chips, expected time. Answers "what is it doing right now".
- **Step Pareto** (§8.11.4 `StepStats`) — per-step Avg bars (worst-first) with a Max marker, complementing the waterfall.
- **Global alarm banner** — the single worst active event across the whole forest, visible from every screen; tap selects the source (standard safety pattern).
- **Connection chip** — transport liveness (Live/Connecting/Stale/Offline); an HMI must never present data of unknown freshness.
- **Responsive layout** — persistent left tree ≥900px; below that it becomes a Drawer (phone/Android portrait). Same code, all four platforms.

### Deliberately out of scope here (deployment/next)
The Web gateway service, certificate provisioning UI, Linux/Android runner
packaging, and long-horizon historian storage remain deployment work. OEE
recent-history visualization and alarm shelving are implemented against
the bounded PLC mirrors; external retention still belongs to the historian.

## Fieldbus topology view (Core §10.5.1 / TC3 §10.6)

A **second tree** beside the module tree (app-bar Modules/Fieldbus toggle): the
physical bus — master → couplers → terminals/drives — auto-detected from the
fieldbus master's diagnostics on a real transport (EtherCAT/ADS, TC3 §10.6).
- **Node status colouring**: OP = neutral, SAFEOP/PREOP/link-warn = amber,
  FAULT/OFFLINE = red; worst-in-subtree tints ancestors (same rule as the module tree).
- **I/O panel per node**: every digital channel as ON/OFF, every analog as
  value + unit, with direction, quality, and forced flags. Each channel carries
  the browse path back to the owning module (§4.8), so a bus fault and a module
  first-out are two lenses on one event.
- **Sim** reflects the same fault as the module tree: when CylB errors, its EL1008
  DI terminal goes FAULT and its coupler drops to SAFEOP — demonstrating the
  cross-view diagnosis. **Channel forcing (implemented):** the first real manual-function write. A pin
button on each channel (visible only at MANUAL level, §7.7) opens a confirm dialog
(digital ON/OFF or analog value); the force is applied through `forceChannel`,
re-checked in the repository, reflected as a FORCED flag on the channel, and
logged as a §8.3 event. Below MANUAL the button is a lock icon. This is the
write-surface pattern for every future manual function.

Enum ordinals (`NodeState`, `ChannelDir`, `ChannelKind`) mirror the PLC DUTs
`E_NodeState`/`E_ChannelDir`/`E_ChannelKind` — verified against them.
