# AGENTS.md — guide for AI coding agents working on Fraktal

Fraktal is a **platform-neutral standard for PLC equipment software**: one recursive three-tier
module model, one data contract, one PLCopen command handshake, one diagnostic model, self-describing
over OPC UA so a generic HMI renders it with zero per-station code. This file is the working briefing
for any agent editing this repo. **Read the spec for anything normative** — every clause below names its
spec section so you can drill in. Spec lives in `Specification/`; the normative core is
`Fraktal_Core_Part_I.md` (Part I), with the TwinCAT binding in `Fraktal_TC3_Part_II.md` (Part II).

> Normative language in the spec: **shall/must** = requirement · **should** = recommendation · **may** = permitted.

---

## 1. Repository map

```
Specification/        The standard. Part I (Core, platform-neutral) + Part II (Fraktal/TC3 binding)
                      + annexes A–K (worked examples) + HMI_CONTRACT.md + split/audit notes.
FraktalCore/
├── PLC/              Fraktal/TC3 reference implementation (TwinCAT 3, IEC 61131-3).
│   ├── Fraktal_Core/            framework LIBRARY (contracts, base classes, PermIntlk, providers)
│   ├── Fraktal_Modules/         reusable module library + sim models and device presets
│   ├── Fraktal_Demo/            executable two-root application (MAIN + PlcTask; not a library)
│   ├── Fraktal_Press_Demo/      pneumatic-press virtual-commissioning application
│   ├── Fraktal_Tests/           aggregate TcUnit project (manifest + Core/Modules/Press test sources; excluded from runtime)
│   └── scaffold/FB_TemplateCM/  copy-template for a new CM type (not compiled; born RED)
└── HMI/               Generic operator HMI (Flutter). lib/{data,domain,state,ui}.
```

Two source-of-truth documents beyond the spec:
- `FraktalCore/PLC/IMPLEMENTATION_NOTES.md` — **every** place the implementation diverged from the
  draft spec, with the reason. Read this before changing PLC code; it records what was decided and why.
- `Specification/HMI_CONTRACT.md` — the exact symbol→widget bind table the HMI implements.
- `Specification/FIRST_PROJECT_AGENT_GUIDE.md` — mandatory phase/evidence workflow when guiding a
  first project, initial target deployment, TF6100 commissioning, or HMI connection troubleshoot.

---

## 2. The mental model (learn this first)

**Three function-block archetypes, recursively nested (§3.1, §3.3):**

| Tier | Type | Role | May contain |
|---|---|---|---|
| Top (recursive) | `FB_Unit` | **ModeHandler** — runs a continuous mode sequence Start→Stop; owns mode | Units, EMs, CMs |
| Middle | `FB_EquipmentModule` | **CommandHandler** — discrete, bounded commands | CMs, nested EMs — **never a Unit** |
| Leaf | `FB_ControlModule` | Hardware-bound device, one HAL channel | nothing (leaf) |

A program hosts **one or more root `FB_Unit`s** (a *forest*, §3.1a) — peers, each with its own
mode/cycle/model identity. There is no shared super-root.

**One contract everywhere (§3.12):** every module exposes `ParCfg` (config/recipe) · `ParCmd`
(command params) · `OutCmd` (command results) · `OutImm` (cyclic status). The PLCopen handshake
(§6.1) — `Execute`/`Busy`/`Done`/`Error`/`ErrorID`/`Abort`/`Aborted` — is the single command vocabulary;
`State` (`E_ExecState`: READY/BUSY/DONE/ERROR/ABORTED) is the derived summary.

**The lifecycle is written ONCE in `FB_ModuleBase` (§2.2).** A concrete module type
`EXTENDS FB_ControlModuleBase` (or the EM/Unit base) and overrides **only `_M_Dispatch`** (its
`CASE _step` device logic, calling `_M_Fault`/`_M_Complete`) plus, optionally, lifecycle hooks (§3.14).
Edge handling, state mapping, Execute-drop reset, `ErrorID`, abort routing, per-command timing, and the
HMI data mirror are all **inherited** — do not re-implement them.

**Diagnosability by construction (§6.9, §8):** when a sequence stalls, the operator gets a precise
root cause produced automatically from the contract — never hand-coded per-step. A stall is a *pending*
diagnostic (Low), not a fault; the fault path is the awaited module's Error, adopted instantly via the
rollup (§8.2).

---

## 3. PLC editing guardrails (the shalls that bite)

**Lifecycle & hooks (§2.2, §3.14):**
- New module types **shall extend the base classes** — never re-implement the lifecycle.
- Every overridden hook **shall call `SUPER^.OnX(...)` first** and propagate its return — **except
  `OnModeExit`**, where calling the base *is* the cancel, so it is staged to the end of a graceful stop (§3.14.4).
- The base FB body only calls `Cyclic()`; concrete types **do not write a body** — per-scan work goes in
  `OnCyclic`, device logic in `_M_Dispatch` (IMPLEMENTATION_NOTES §5).
- **No `FB_Unit` inside an `FB_EquipmentModule`** (§3.3) — structurally enforced; a CI check walks the tree.

**Naming (§4.3–§4.6) — a lint gate checks this:**
- Prefixes: `F_` function · `FB_` function block · `M_`/`_M_` public/protected method · `ST_` struct ·
  `E_` enum · `I_` interface · `GVL_`/`PL_` GVL/param-list · `PRG_` program (except `MAIN`).
- **No Hungarian** on variables/instances (`Clamp1 : FB_ControlModule`, not `fbClamp1`). Retained
  access markers only: `p` pointer, `r` reference, `i` interface, leading `_` for `%I/%Q/%M`-mapped (HAL boundary).
- Enums carry `{attribute 'qualified_only'}` and are referenced `E_X.MEMBER`. Constants `UPPER_SNAKE_CASE`.
- TwinCAT keywords are case-insensitive and forbidden as identifiers (`Action`, `Log`, `Min`, `Max`, `R`,
  `S`, `DT`, `Time`, etc.). Use semantic alternatives (`Gate`, `AuditSlot`, `Minimum`, `Maximum`, `DeltaMs`).
- Status = *adj·noun·num·past-verb* (`ClampClosed`); Command = *verb·adj·noun·num* (`CloseClamp`) (§4.5).
- A module's local OPC UA browse segment **shall equal** its local PLC instance/schematic name.
  `Status.Name` is the qualified dotted Fraktal identity (`Root.Child`); its final segment shall equal
  that local browse name. `.` is reserved as the path separator and is forbidden inside a local name.
  Reference/owner aliases are not additional modules (§4.7, §4.8).
- In TwinCAT TF6100 **TMC-Filtered** mode, place `{attribute 'OPC.UA.DA' := '1'}` immediately before every deployed root Unit instance in `MAIN`/the forest-owning GVL. TwinCAT supports type-level inheritance too; the explicit instance marker makes the intended deployed forest auditable and inherits to that root's children (Part II §3.10).
- Exclude implementation-only pointer/interface/reference storage inherited into a published subtree with `{attribute 'OPC.UA.DA' := '0'}`. Never hide the published child-module instances. An application-owned `Unsupported datatype ... UXINT` path is an exclusion defect; Beckhoff's `TwinCAT_SystemInfoVarList._AppInfo.TComSrvPtr` is a skippable system leaf, not a Fraktal compile or discovery failure.

**Data & recipe (§3.8):**
- `SchemaVersion : UINT` **shall be the first member** of every `ParCfg`/record — a generic provider
  validates by comparing the stored first-UINT to the target's. Adding a member = a schema change.
- Recipe load is **migrate-or-fault** (`RECIPE_INVALID`), never partially applied. External payloads are
  validate-before-load (§5.6).

**Traceability (§3.16):**
- Every `FB_Unit` publishes `Part : ST_PartContext`. Traceability is OFF until the composition root
  injects a carrier via `SetPartCarrier` (shipped default: `FB_LocalPartCarrier`, BY_POSITION serials;
  RFID/DataMatrix/host substitute behind `I_PartCarrier` — the recipe-provider pattern).
- A Unit's mode chain raises the four canonical events through the inherited helpers:
  `_M_PartReceived` (identity confirmed at entry) → `_M_PartStarted` → optional `_M_PartRecord`
  (measured values) → `_M_PartProcessed(Verdict, Reason)` — the carrier write precedes the event.
  ERROR entry auto-raises `EVENT_PART_PROCESSING_ABORTED`; also call `_M_PartAborted()` in `OnAbort`.
- Carrier failures are never silent: `CARRIER_READ_FAILED` / `CARRIER_WRITE_FAILED` faults (§8.8
  band 2020–2029; the four `EVENT_PART_*` codes live there too).

**I/O code placement (§10.2.1):**
- `GVL_<Project>IO` declares raw mapped symbols only; exactly one project Hardware Driver POU may access it.
- Project I/O catalogs own tag/address/description/module-role data only. They do not copy live values or
  reimplement bounds, duplicate, health, or diagnostic-join algorithms.
- `FB_IoTopologyPublisher` owns those reusable algorithms; CMs consume HAL semantics and injected identity.
- `MAIN` is a composition root: setup, real/simulation selection, and scan ordering—not channel assignments.
- An electrical tag/address has one project source of truth; do not repeat the literal in `MAIN`, a CM, and
  a fieldbus publisher.
- Changeover uses fallible `PrepareRecipe(Model)` → recursive readiness → infallible bounded
  `CommitRecipe()`; prepare rejection calls `AbortRecipe()`. Commit performs no validation or I/O.
  Providers address records by `(ModelCode, RecipeKey)`, never one ambiguous string.

**Reason codes (§8.8) — one number space, the registry is the collision authority:**
- Framework band `2001–2008` (TIMEOUT/PERMISSIVE_NOT_MET/INTERLOCK_DROPPED/RECIPE_INVALID/STEP_STALLED/
  RETRY_EXHAUSTED/CYCLE_TIME_DEGRADED/UNSUPPORTED_COMMAND); self-test `2900–2909`. Type bands are `DINT` constants ≥10000 in
  the type's own `PL_<Type>Reasons`. **Reserve a band before writing a type**; record it; the audit scans
  for duplicates and band squats. `E_Reason` is deliberately non-strict so bands compose across libraries.

**Defensive coding (§5.6):** validate commands against the supported set (reject out-of-range with a
reason, never a silent default); bounds-check indices; validate motion targets against limits; **every
`CASE`/`IF` shall have a defined `ELSE`** that drives a safe reaction — never a silent no-op that stalls a chain.

**Safety and control power (§9.8, `SAFETY_AND_CONTROL_POWER_PROFILE.md`):** the standard PLC may
send untrusted enable/stop/unlock requests, but TwinSAFE/certified safety alone grants safe enable,
unlock, reset, muting, bridging, and safe valve/drive outputs. `ControlOn` is control-domain orchestration;
`PowerOn` targets one named group. Neither may self-resume after safety or communication recovery.
Key bridging and muting are read-only, conspicuous HMI status—never `PermIntlk` bypasses or forces.
Safety/control-power ownership is an optional **control domain** orthogonal to the Unit forest: a Unit
references zero or one domain, and one domain may serve several peer root Units. Never invent a
super-root Unit or duplicate the coordinator per Unit; `Present=FALSE` means no profile Start gate.

**Language policy (§5.5, §6.2, §6.8):** framework/base types are **ST only**. A multi-step Unit/EM
sequence is a separate POU that **extends `FB_SequenceBase`**; the shipped reference form is the Core
§6.8 **ST `CASE _step OF` skeleton** (native graphical SFC is a permitted §6.8 alternative but only if
authored in the XAE SFC editor — a hand-emitted chart XML fails with an `SFCStepType` cascade; never
commit one). Each `_step` branch contains that step's `M_Step`/condition record, child command or wait,
decision/timer/result logic, and sets the shared `_retVal`, ending with `M_Advance(OnAdvance := <next>)`.
The owner adapter may only reset/run the sequence or bridge protected framework services. A token-only
body plus `CASE ActiveStep OF` application logic in the Unit is forbidden. The project-owned
`FB_PressDemoHome`, `FB_PressDemoChangeover`, `FB_PressDemoAuto`, and shared `FB_PressDemoLoadPosition`
are the reference; their `FB_PressDemoUnit._M_Sequence*` methods are lifecycle-only adapters.

**Release ownership and act-or-explain (§7.2.1, §7.6, §7.8):**
- Define a condition at the lowest module with enough semantic context. Reusable release logic consumes
  HAL/child/domain contracts, never project raw-I/O GVLs or unrelated application globals. Parents append
  child records; they do not copy the Boolean under a new description.
- `CommonManRelease`/`AllOk` are convenience summaries, never the only diagnostic source. Preserve every
  condition record and qualified owning `SourcePath` so common + active-mode/function-specific failures
  remain individually visible and same-text child conditions are distinguishable.
- A Unit's `Start()` **consumes the BOOL returned by `ReleaseReportStart(Report := HmiResponse.Report)`**
  after the audited access check. Never code
  a second execution predicate beside the report. Compose one common Start set plus optional active-mode
  entry/frontier records; later part/operator/downstream waits stay in the §6.5 pending step record.
- Manual release is common Unit manual conditions AND only the selected target+direction's specific
  conditions. Safety/muting/bridging may be explained read-only but never granted or bypassed here.
- Cross-module, mode-entry, and application-policy conditions **shall be visibly project-owned** under the
  affected Unit branch (normally `Release`/`Permissives`), not hidden in a reusable library. Expose named
  condition state and feed the one authoritative Unit release report. Device-intrinsic conditions stay in
  the reusable CM/EM that has the semantic context to own them.

**Code grouping & sequence distribution (§4.2, §6.7):**
- Application project folders follow the **instance tree**, not artifact types: `00_System` (MAIN,
  raw I/O GVLs, safety aliases, hardware driver, domain coordinator, sim plant) then one
  `0N_<UnitName>` folder per root Unit holding that Unit's application engineering data
  grouped into owner-local roles (`Sequences/Mode|Sub`, `Release`, `Recipes`, and `Io`).
  Never create application-wide POU/DUT/sequence buckets. `Fraktal_Press_Demo` is the model.
- Reusable libraries are type—not instance—collections: keep the type/owner relationship obvious, but do
  not copy a reusable implementation into each application branch. TwinCAT methods stay under their owner
  FB; do not add forwarding POUs merely to manufacture a folder.
- A deployed Unit's concrete mode chains and cross-module release policy belong to its application branch.
  A library may offer an abstract helper, reusable sub-sequence, or opt-in generic default, but it shall be
  explicitly selected and extendable/replaceable; a library shall not silently make AUTO/HOME/CHANGEOVER
  final for the project. In the press reference, `FB_PressDemoUnit`, `Sequences/`, and `Release/` all live
  under `Fraktal_Press_Demo/01_PneumaticPress` while `Fraktal_Modules` supplies the reusable device modules.
- Every chain has one owner and one step-state writer: an ST chain with application logic inside its
  `CASE _step OF` step branches plus a lifecycle-only `_M_Sequence<Mode>` adapter = continuous Unit mode
  (default form on `FB_SequenceBase`);
  EM/CM command dispatch = finite public command through §6.1; `_M_Seq<Name>` = owner-private finite
  sub-sequence with no module/OPC UA identity. The call graph is acyclic and two chains never command the
  same child in one scan. Promote a sub-sequence to an EM when it needs independent commandability,
  concurrency, recipe/lifecycle/diagnostic identity, or reuse by unrelated owners.
- A sequence POU **extends `FB_SequenceBase`** (§6.8(a)): it supplies the `_step` token,
  `M_Step`/`M_Await`/`M_Gate`/`M_MayIssue`/`M_Delay`, the part/decision/completion forwards, the shared
  `_retVal : E_StepResult`, and `M_Advance`. Each `_step` branch is `_retVal`'s only writer and ends with
  `M_Advance(OnAdvance := <next>)` (optional `OnJump<n>` for §6.10 branches), which advances and clears
  the step-scoped latches. The owning Unit already implements `I_SequenceHost` (base) — pass `THIS^` at
  the sequence's `Setup`; do not create per-project host interfaces or per-step transition Booleans.
- Extract a coherent chain when reused, branch/cleanup-heavy, or materially clearer—not every step. The
  caller supplies a `BaseStepNo` window and publishes the private progress through the normal step record.
  In the press, AUTO/HOME/CHANGEOVER embed the shared `FB_PressDemoLoadPosition`; never copy that motion chain.
- Cross-standard orientation (Bosch **Nexeed** reference, `NexeedReferenceOnly/`; decisions documented in
  `Specification/NEXEED_REFERENCE_INSIGHTS.md`): `SqM` ≈ mode sequence, `SqC` ≈ module command, `SqS` ≈
  private sub-sequence, location folders ≈ §4.2 ownership. Do **not** import Unit+Extension duplication,
  per-step wrappers, opaque summed releases, PLC-authored HMI visibility, direct raw-global coupling, or
  ordinary-PLC safety bridging. Fraktal base classes, hooks, condition records, and safety boundary own those.

**Testing (§5.7):** every reusable module **type** ships a TcUnit suite run against the sim HAL in CI.
Rows **T1** (handshake + Execute-drop reset) and **T4** (abort, no self-resume) are proven **once** in
`FB_Base_Tests` for every inheriting type — **do not re-test them per type**. A type earns T2 (first-out
reason + SourcePath), T3 (interlock withholds output), T5 (recipe migrate-or-fault). T10 proves once that
the Unit base consumes its release report; any Unit adding mode-entry conditions exercises one of them.
`Fraktal_Tests` runs only on an isolated test runtime/ADS port with Autostart Boot Project disabled;
never deploy it as the machine boot application. On TC3, fill large bounded records such as
`ST_ReleaseReport` through caller-owned `VAR_IN_OUT` storage—nested by-value returns can overflow the
bounded task stack.
SIM-only force hooks compile out of release builds.

---

## 4. HMI editing guardrails

**The HMI is generic and data-driven (§3.10(a′), §3.13, `HMI_CONTRACT.md`):**
- It binds **published data, never properties/methods** (those are invisible to OPC UA). A node is a module
  iff it has a `Status : ST_ModuleStatus` member. Adding a module type adds HMI automatically — **do not
  write per-station/per-type screens.**
- The UI binds only `PlcRepository` (`lib/data/plc_repository.dart`). `SimRepository` is the shipped live
  demo; OPC UA (FFI) and a WebSocket/REST gateway (for Web) are swap-in adapters behind the same interface.
- **Enum ordinals in `lib/domain/types.dart` are the PLC contract** — they must match the Core DUTs
  (`E_Mode`, `E_ExecState`, `E_NodeState`, `E_ChannelDir`, `E_ChannelKind`, `E_GatedAction`, …). Verify
  them first when changing either side.
- Dependencies are deliberately narrow: Flutter SDK localization, `file_picker`,
  `pdfrx`, `cupertino_icons`, and the Dart-team `ffi` package for the normative
  native OPC UA adapter. Native code must remain behind conditional imports;
  Web uses the versioned gateway protocol. Do not add further packages without
  a spec-backed need and a cross-platform review.
- Connection ownership precedes the operator shell: `ConnectionBootstrap` opens the wizard until an endpoint has reached `LIVE`, removes the interactive HMI immediately on `STALE`/`DOWN`, and exposes connection editing only after 30 s without `LIVE`. Never bypass this gate or queue writes across reconnect.
- Wizard step 2 assigns one or more discovered root Unit paths to this HMI. `ScopedPlcRepository` enforces that scope for reads and writes; only an authenticated ADMIN may edit it later.
- The write surface is deliberately narrow: `Command`+`Execute`/`Abort`, `DecisionAnswer`, Unit
  mode/start/stop, manual commands, channel force — all release-gated (§7.6/§7.7) and re-checked by the PLC.
  **Hold-to-run over HMI is non-safety** (no dead-man).
- I/O identity is structured data: `ST_IoChannel.Name` and `ST_Diagnostic.IoTag` **shall equal the
  approved electrical/I/O-list tag verbatim**. Localize only `DescriptionKey`/`Diagnostic`; preserve
  `Address`, unique `Path`, and owning `ModulePath` so alarms cross-link to fieldbus channels.

---

## 5. Build, run, test

For a first project or first deployment, read and follow
`Specification/FIRST_PROJECT_AGENT_GUIDE.md` completely. Keep compile, target,
runtime, OPC UA channel/session, namespace authorization, Fraktal discovery,
mailbox acknowledgement, and PLC acceptance as separate checkpoints. Once the
module tree is live, diagnose failed controls from the `HmiRequest` write/commit
and `HmiResponse` acknowledgement/diagnostic path—do not restart from ping.

**PLC (TwinCAT 3, 4024+):** a `.plcproj` is added *into* a TwinCAT XAE solution, not opened directly:
create a TwinCAT XAE Project in TcXaeShell/VS, right-click **PLC → Add Existing Item…** → the `.plcproj`.
The aggregate test manifest is `FraktalCore/PLC/Fraktal_Tests/Fraktal_Tests.plcproj`. It links the
deployed press sources with `<Compile Include="..\Fraktal_Press_Demo\...">` + a `<Link>` display path, so
the gate tests the same Unit/sequences that ship.
Build order: `Fraktal_Core` first (save/install as library), then `Fraktal_Modules` (save/install as
library), then the `Fraktal_Demo`, `Fraktal_Press_Demo`, and `Fraktal_Tests` applications
(`Fraktal_Tests` needs TcUnit).
Do not leave the Core/Modules source-library projects loaded beside applications that consume their
installed libraries: XAE sees the same source object GUIDs twice and rewrites them in the solution.
Use separate library/application solutions, or unload/remove the library-source projects after install
and before adding the applications. The press sequences are plain ST on `FB_SequenceBase` and need no SFC
library reference. (If you ever add a genuine graphical SFC drawn in the XAE editor, it also needs no
`IecSfc` `.plcproj` reference — the compiler provides `SFCStepType`; an `SFCStepType` cascade means a
machine-generated/malformed chart XML, which is prohibited — author charts in the editor only.) Close
and reopen XAE after changing a `.plcproj` library reference so the in-memory project reloads it.
The current Core is `0.1.0.2` and Modules is `0.1.0.2`; downstream placeholders are pinned accordingly.
If every Modules-owned type is reported
unknown in an application, stop: this is an unresolved/stale `Fraktal_Modules` reference, not a
reason to edit each affected POU. Install Core `0.1.0.2`, resolve/build/install Modules `0.1.0.2`,
then reload the application placeholders and rebuild.
Build warning-clean (§2). The source is a **draft not
yet compiled against a pinned TwinCAT** — see "watch items" below.

**HMI (Flutter):** from `FraktalCore/HMI/` (windows/web platform folders are committed; SDK on this
machine: `D:\FlutterSDK\flutter`):
```
flutter pub get
flutter analyze                 # clean as of 2026-07-12 (Flutter 3.44.5)
flutter test                    # SimRepository boot smoke test
flutter run -d windows|chrome
```
`analysis_options.yaml` is self-contained (no flutter_lints include) per the zero-package policy.

---

## 6. Known deferred / watch items — do NOT "fix" blindly

These are recorded honestly in `IMPLEMENTATION_NOTES.md` and the spec. They are **first-compile watch
items or deliberate deferrals**, not bugs to silently change without a compiler or a spec reason:
- Compile-plausibility caveats pending a pinned TwinCAT: `SEL` on STRING, `DINT_TO_TIME`/`TIME_TO_DINT`,
  `TIME_TO_UDINT`, interface `= 0` comparisons, `MID()` arg
  order, `'$R'` terminator escape, `FIND/DELETE` string semantics, `TIME * INT` backoff doubling,
  `AssertEquals_REAL` delta signature in TcUnit.
- The pinned 4024 compiler requires every method input at every call. Optional method inputs are a
  4026+ feature; do not use default-valued method `VAR_INPUT` in this binding.
- A child FB published as a parent's `VAR_OUTPUT` is readable to external ST, but its inputs cannot be
  assigned through that parent output. Route such writes through an explicit method on the child or
  owner; keep direct request-symbol writes for OPC UA clients at the published module node.
- `FB_TemplateCM` (`scaffold/`) is a **copy-template, not compiled** — it is intentionally absent from
  every `.plcproj`. Its tests are born RED on purpose (§5.7).
- `I_EventSink` historian adapters and the OPC UA / gateway HMI transports are **deployment-deferred by design**. Runtime localization catalogs and local PDF content are shipped; a shared production document store remains a deployment adapter.
- Annexes B/D/G/I predate the base classes and show the *expanded* lifecycle form for pedagogy; a
  conforming type keeps only their `CASE` bodies (§2.2).

When you change code, prefer **anchored edits with a post-assertion** over "if X not in file" idempotency
guards — the latter silently no-op when an old artifact already carries the name (this caused real
compile-blocking regressions; see IMPLEMENTATION_NOTES §24).

---

## 7. Where things live (quick lookup)

| You need… | Look at… |
|---|---|
| The common lifecycle | `PLC/Fraktal_Core/BaseClasses/FB_ModuleBase.TcPOU`; tier wrappers are `FB_ControlModuleBase`, `FB_EquipmentModuleBase`, and `FB_UnitBase`; spec §2.2, §6.1 |
| The public module interface | `PLC/Fraktal_Core/Interfaces/I_Module.TcIO` (+ `I_Unit`/`I_EquipmentModule`/`I_ControlModule`); spec §3.2 |
| Framework reason codes / constants | `PLC/Fraktal_Core/Params/PL_Fraktal.TcGVL`; spec §8.8 |
| A reusable CM/EM implementation | `PLC/Fraktal_Modules/` (cylinder CM, clamp EM); Annexes A/B/C |
| Press project Unit, mode chains, and releases | `PLC/Fraktal_Press_Demo/01_PneumaticPress/{FB_PressDemoUnit,Sequences,Release}` |
| CX2030 press I/O and commissioning gaps | `Specification/CX2030_PRESS_IO_MAPPING.md`; physical XTI and linked symbols in `PLC/Fraktal_Press_Demo/00_System/{Hardware,GVL_PressIO.TcGVL}` |
| First project / deployment / OPC UA commissioning | `Specification/FIRST_PROJECT_AGENT_GUIDE.md` |
| Part traceability (§3.16) | `PLC/Fraktal_Core/Connectivity/FB_LocalPartCarrier.TcPOU`, `Interfaces/I_PartCarrier.TcIO`, UnitBase `_M_Part*` helpers; Annex E |
| Start a new module type | Copy `PLC/scaffold/FB_TemplateCM/`, read its `SKELETON.md` |
| HMI↔PLC bind table | `Specification/HMI_CONTRACT.md` |
| HMI domain model (the contract types) | `HMI/lib/domain/types.dart` |
| HMI transport seam | `HMI/lib/data/plc_repository.dart` (+ `sim_repository.dart`) |
| Nexeed comparison decisions (grouping/sequences/releases) | `Specification/NEXEED_REFERENCE_INSIGHTS.md` |
| Why the code differs from the draft spec | `PLC/IMPLEMENTATION_NOTES.md` |
