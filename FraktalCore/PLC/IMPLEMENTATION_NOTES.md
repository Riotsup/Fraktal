# Fraktal Core — Implementation Notes (Milestone 1, 2026-07-02)

*Scope: `Fraktal_Core` library + aggregate `Fraktal_Tests` gate + scaffold, implementing Core §2.2 (base classes), §3.2 (interfaces), §3.8/§3.15/§3.16 (provider/connector/carrier contracts), §6.1 (lifecycle), §6.5/§6.9(b)/§6.11 (step/condition/decision records), §7.2 (`FB_PermIntlk`), §8.2 (rollup), §8.8 (`E_Reason`). Source drafts: `Fraktal_Core_BaseClasses.md`, `Fraktal_QuickStart_and_Suite.md`. Status: source-complete, **not yet compiled against a pinned TwinCAT** (Core §2 / TC3 §2.1) — see "Bring-up" in README.*

## 1. Draft pseudocode fixed in the implementation

| Draft construct | Problem | Implemented as |
|---|---|---|
| `_exec IN (E_ExecState.DONE, …)` | no set-membership operator in IEC ST | explicit `OR` chain in the Execute-drop reset |
| `SysTime()` | not a TwinCAT function | `F_Now()` — [TC3] wrapper over `Tc2_Utilities.F_GetSystemTime()` (UTC, 1601-epoch FILETIME → DT); one clock feeds all timestamps (Core §2.7) |
| `CONCAT3/4/5` (Annex C drafts) | Tc2_Standard `CONCAT` is 2-arg | not needed in M1; the M2 stall walk will chain 2-arg `CONCAT` (noted for the Unit base) |
| `_M_OnAbort` (base-classes draft) | §3.14 names the hook `OnAbort` | hook named `OnAbort`/`OnCyclic` per the §3.14 catalogue, with the call-`SUPER^`-first contract in the method headers |
| bare `FOR i := 1 TO _nChild` rollup | no null/bounds guards (Core §5.6) | `_M_Register` bounds-checked; rollup/tick guard `<> 0` with `AND_THEN` (Core §5.3 short-circuit rule) |

## 2. Contract reconciliations against Core §3.2 — **folded back into Core on 2026-07-02**

These compile-driven deviations are now normative: Core §3.2 (interface surfaces + rationale), §2.2 (hooks = the §3.14 family; bases implement `I_Module`), §5.7 (inherited rows proven once), and §8.8 (band-extensibility rule) were amended accordingly, each clause stating the §1.1 objective it serves. The list below is the original record:

- **`I_Module` has no `ErrorID` property.** Every module already exposes `ErrorID` as a PLCopen `VAR_OUTPUT` (§6.1); an identically-named interface property on the same FB does not compile. Callers use `GetFaultSummary().ReasonCode` (richer anyway). `FaultActive`/`State` remain.
- **`GetFaultSummary` returns `ST_Diagnostic`,** not the §3.2 text's `ST_FaultSummary` — the §8.8 record is the one every other clause (rollup §8.2, stall walk §6.9, PermIntlk §7.2) uses; a second summary type would duplicate it.
- **Recipe changeover is transactional.** `I_Module` exposes `PrepareRecipe(Model)`/`CommitRecipe()`/`AbortRecipe()`; types stage validated `ParCfg`, and composites recurse before the Unit publishes its new `Model`.
- **Generic command ids are `DINT`.** Per-type command enums cannot appear in a common interface. Both command-bearing tiers use `ExecuteCommand(Command : DINT)` and `AbortCommand()`; the typed PLCopen `Command`/`Execute` surface remains primary.
- **`FB_ModuleBase` implements `I_Module`; tier wrappers implement their tier interfaces.** `FB_CompositeModuleBase` owns child registration, recipe recursion, and rollup without implying that a Unit is an Equipment Module.
- **Published status is `ST_ModuleStatus`.** The abandoned tier-specific `ST_CmStatus` duplicate was removed.

## 3. `E_Reason` extensibility

IEC enums cannot be extended across libraries, but Core §8.8's model is "one number space, per-type bands." Implementation: `E_Reason` declares the **framework bands only** and deliberately omits `{attribute 'strict'}`, so a module type declares its band codes (10000+) as `DINT` constants in its own library and assigns them into `ST_Diagnostic.ReasonCode` / `_M_Fault` directly. The §8.8 registry remains the single collision authority; the generated catalog (§8.8) is built from the union of the framework enum and the registered type bands.

## 4. Numbers newly pinned (Core §8.8 registry updated accordingly)

`TIMEOUT`=2001 · `PERMISSIVE_NOT_MET`=2002 · `INTERLOCK_DROPPED`=2003 · `RECIPE_INVALID`=2004 · `STEP_STALLED`=2005 (already pinned) · `RETRY_EXHAUSTED`=2006 (was named but unnumbered) · new sub-range **2900–2909 framework self-test** with `TEST_FAULT`=2901 (used only by the base suite; never raised in production). These match the values Annex A already declared (2001–2004), so docs, annexes, and code now agree.

## 5. Design decisions

- **Body = `Cyclic()`.** Each base FB's body only calls its `Cyclic()` method, so `inst()` and `inst.Cyclic()` (the `I_Module` path a parent uses) are identical. Concrete types **do not write a body**; per-scan work goes in an `OnCyclic` override (base first, per §3.14.2), device logic in `_M_Dispatch`.
- **`_M_Complete` / `_M_Fault` / `_M_FaultDiag` / `_M_ClearDiag` / `_M_SetName`** are the whole protected toolkit a type needs; `_M_Fault` stamps `SourcePath`/`Since` (`F_Now`), `_M_FaultDiag` adopts a diagnostic *verbatim* (rollup/connector, §8.2 — the child's `SourcePath` survives).
- **`FB_PermIntlk`** implements the full §7.2 canonical surface; `Since` is stamped only when the first-out *changes*; `SourcePath` is left for the owner to set when copying `Diagnostic` up (per the §7.2 usage contract). Bypass honors §7.3 (only `Bypassable`, always flagged via `AnyBypassed`).
- **The EM base extends the CM base** (per the draft): it *adds* `_M_Register`/`_M_TickChildren`/`_M_RollupFault` and overrides `ModuleType`.
- **Test coverage:** `FB_Base_Tests` proves **T1, T2, T4** once for every inheriting type, plus the **rollup (T6 at base level)** via `FB_ProbeEM` — asserting the child's `SourcePath` (`Test.EM.ChildB`) survives adoption verbatim. `FB_PermIntlk_Tests` proves first-out ordering (a later FALSE never masks an earlier one) and the bypass rules. Concrete types remain responsible for T2/T3/T5 with *their* reasons (scaffold) and tier rows per §5.7.
- **Scaffold is born RED** (Quick-start §2): `FB_TemplateCM_Tests` ships with failing T2/T3/T5 placeholders (`16#FFFF_FFFF` expected values, `AssertTrue(FALSE)`) so the §5.7 checklist drives development; T1/T4 are inherited and not repeated.
- **`OPC.UA.DA` pragmas [TC3]** sit on the base classes per TC3 §3.10 so every derived type inherits the contract exposure. The reference applications additionally mark every root Unit **instance** in `MAIN`; TF6100 supports both definition-level (all instances) and instance-level (one instance plus children) inheritance, and the explicit root marker makes the deployed forest auditable.

## 6. Known M1 limits → Milestone plan

- **M2 — `FB_UnitBase`:** mode model (§3.4, `_M_Supports`, graceful cascade §3.7 via `__QUERYINTERFACE` [TC3]), the step-chain base with `_M_SetStep`/`_M_Await` condition records, the §6.9(c) stall walk (2-arg `CONCAT` chains), `OnInit`/`OnModeChanged`/`OnModeExit` hooks, decision queue (§6.11).
- **M3 — providers & connectors:** `FB_LocalRecipeProvider` with SchemaVersion migrate-or-fault (§3.8), an `FB_DeviceConnectorBase` (heartbeat, `LinkTimeout`, HOLD/ABORT/MODE_STOP reaction, bounded backoff, no self-resume — §3.15).
- **M4 — first shipping type:** `FB_CylinderCM` + `FB_ClampEM` from Annexes A/B against a sim plant model (`FB_CylinderSim`, §5.7 should-clause), turning the Annex H suite into real CI.
- The **`SimForceInterlock` SIM-only hook** (§5.7) is deferred to M4 with the first HAL-bound type; the scaffold marks where it belongs.

## 7. Timing capture & time classification (Core §8.11.4) — M1.x, 2026-07-02

Implements the cycle-time-profile amendment, including clause (f) time classification. Design points:
- **Two clocks, deliberately (§8.11.4(e) / TC3 §8.11):** durations from the monotonic ms clock (`TIME()` differenced as `DWORD`, wrap-safe across the ~49-day rollover); wall-clock `Started`/stamps from `F_Now()` so profiles align across stations (§2.7). Never mix the two.
- **`F_TimingUpdate` is a pure function** (running mean `avg += (x−avg)/n`) so the aggregate math is unit-tested with exact values (100/200/300 → avg 200 in `FB_Timing_Tests`).
- **Base-class capture is transition-driven:** the row closes on `BUSY → DONE/ERROR/ABORTED` via `_prevExec`, so faulted/aborted commands are measured too. A type contributes only `_M_TagCommand(TO_DINT(Command), '<label>')` — one idempotent line, in the scaffold; untagged types still get `LastCmdTime` and an id-0 row.
- **Classification is opt-in per wait step (§8.11.4(f)):** `StepChanged(…, Class := E_TimeClass.WAIT_UPSTREAM)` — default `WORK`, so non-wait steps cost nothing. The profiler accumulates `ByClass[TO_INT(class)]` and publishes `WorkTime` (**the real cycle time**) and `WaitTime` at `CycleComplete`; the suite asserts `Total = WorkTime + WaitTime` and that classes survive into both the waterfall and the per-step aggregates. `WAIT_UPSTREAM`/`WAIT_DOWNSTREAM` are the per-step attribution of §8.11.3 Starved/Blocked; M2's chain base may auto-attribute them from the Unit's Starved/Blocked conditions (explicit class wins).
- **Find-or-allocate rows, fixed arrays:** `Count = 0` marks a free slot; overflow sets `Truncated`/`StatsTruncated` rather than growing — capture never allocates at runtime.
- **`FB_CycleProfiler` is event-driven** (`StepChanged`/`CycleComplete`, no cyclic body): a refreshed same-step call is a no-op (but may re-declare the class), the first step opens the cycle (§8.11.1 start marker), `ResetStats` exists but the *caller* must log the reset (§8.11.2).
- **M2 wiring:** the Unit/step-chain base will call `StepChanged` inside `_M_SetStep` (forwarding the step record's class) and `CycleComplete` at `N999` — step timing and classification become zero-effort by construction; until then a Unit adds the two calls once (Annex C §C.6 note).
- **HMI:** `Timing`, `Current`, `LastCycle`, `StepStats` are fixed framework DUTs under the base-class pragmas — the §3.13 waterfall (coloured by class, Total/Work/waits header) and Pareto bind to them with no per-type wiring.

## 8. M2–M4: the lifecycle family completed (2026-07-02)

**M2 — `FB_UnitBase`** (now extends `FB_CompositeModuleBase`, implements `I_Unit`): modes reject unsupported requests gracefully; Start/Stop reuse the §6.1 lifecycle; step records power pending diagnostics, rollup, Starved/Blocked, and profiling. A non-graceful mode change performs an **immediate non-safety software abort**; `OnModeExit` stages graceful stopping. The one-slot decision and cycle profiler remain inherited services.

**M3 — `FB_DeviceConnectorBase`** (§3.15): abstract transport quartet `_M_Open/_M_Close/_M_HbStart/_M_HbPoll : E_HbResult`; heartbeat, `LinkTimeout` loss confirm, `DEVICE_PROTOCOL_ERROR` vs `LINK_TIMEOUT` first-outs, bounded exponential backoff (DINT-ms doubling capped at `BackoffMax`), session drop on loss, **no self-resume** (the fronting CM owns `Reaction`). Row **T7 proven once** (§5.7 amendment). **`FB_LocalRecipeProvider`** (§3.8): generic validation via the new **SchemaVersion-first-member rule** (spec amendment) — stored first-`UINT` vs target's initialized first-`UINT`; unknown id, size mismatch, or schema mismatch → `Load = FALSE`, caller faults `RECIPE_INVALID`; `MEMCPY` only after full validation (never partial).

**M4 — `Fraktal_Modules`** (separate reusable-module library, own §8.8 band constants `PL_ModuleReasons`): `FB_CylinderCM` provides interlock-first device logic and direction-specific diagnostics; `FB_ClampEM` provides parallel fork/join, partner abort, settle/confirm, and transactional recipe recursion; `FB_CylinderSim` is the §5.7 plant model.

**Suites** (all in one open-ended gate, §6.8/H.6): `FB_Unit_Tests` (stall text asserted verbatim: `'Step 100 StepA stalled'`; Starved from wait class; stop-after-cycle; 2-step profile published; E-stop-by-default mode change), `FB_Connector_Tests` (T7: healthy beat links; protocol FAIL and silent LINK_TIMEOUT paths, `SourcePath` asserted), `FB_CylinderCM_Tests` (T2/T3/T5 with the type's own reasons + functional completion against the sim; deterministic timing via `T#0S` timeouts), `FB_ClampEM_Tests` (H.5 rollup: `ClampStation.CylB` verbatim). T1/T4 are not repeated per type (§5.7).

**Compile-plausibility caveats to watch at first build:** `SEL` on `STRING` operands in `FB_CylinderCM` (replace with IF if the pinned compiler objects), `DINT_TO_TIME`/`TIME_TO_DINT` availability, and interface `= 0` comparisons.

## 9. Pre-HMI gap closure (M5, 2026-07-02)

The pre-HMI review found that the HMI-facing surface was accidentally accessor-shaped: `Name`/`State`/`FaultActive` were properties and the diagnostic only reachable via `GetFaultSummary()` — **none of which appear in the OPC UA namespace** (TF6100 publishes symbols, not accessors). That also made the base non-conformant with §6.9(a)'s "publish the diagnostic each scan". Closed by: **`ST_ModuleStatus` data mirror** refreshed every scan in `FB_ControlModuleBase` (name set in `_M_SetName`; on Units the live `Pending` stall surfaces on the mirror whenever no fault is active); **§6.9(a) ring buffer** (`History`, fixed size, newest at `HistoryHead`, pushed on the ERROR rising edge); **§8.11 counters** (`GoodCount`/`NokCount` + public `CountGood`/`CountNok`). Spec: new **§3.10(a′)** ("the HMI contract is data, not accessors") and a **§3.13 discovery-and-binding bullet** (module marker = the `Status` member; narrow write surface). `HMI_CONTRACT.md` is the bind table the HMI phase builds against. Deliberately deferred to the HMI phase, recorded there: §7.6 manual-function release gating (item #1, blocks any HMI write of `Command`/`Execute`), §8.3 alarm ack workflow, §8.8 text catalog. Proven in `FB_Hmi_Tests` (mirror fields, pending-on-mirror, counters).

## 10. Pre-HMI regression fix (2026-07-04)

Audit before starting the HMI found one **compile-blocking regression**: the `Model : ST_ModelId` member declaration in `FB_UnitBase` had been dropped during a later edit to that FB's `VAR` block (which added the HMI data-mirror members `Status`/`History`/`GoodCount`/`NokCount`). The `SetModel` method (`Model := Id`) and `ModelCode` property (`Model.ModelCode`) both reference it, so the type would not have compiled. **Restored** the declaration between `StallTime` and `GoodCount`. Verified: `Model`, `Status`, `History`, `HistoryHead`, `GoodCount`, `NokCount`, `Pending`, `Profiler`, `CurrentStep` all resolve in `FB_UnitBase` through the inheritance chain; all 80 files pass XML/lint/VAR-balance/project-list gates.

Also confirmed sound (not regressions): the HMI-prep additions from the prior session — `ST_ModuleStatus` data mirror refreshed each scan by `FB_ControlModuleBase` (+ `Pending` overlay in `FB_UnitBase`), the §6.9(a) `History` ring via `_M_PushHistory`, `CountGood`/`CountNok`, `HMI_CONTRACT.md`, and `FB_Hmi_Tests` — are internally consistent, wired into the runner, and present in the project compile lists. There is correctly **no `FB_Hmi` POU**: per §3.10(a′) the HMI binds published *data*, not a PLC-side HMI object.

## 11. Alarm & event history — §8.3 implemented (2026-07-04)

Spec: §8.3 rewritten from a two-line promise into the full contract — (a) `ST_AlarmEvent` record with `Duration` (monotonic come→gone per the two-clock rule) and synchronized `ComeAt/GoneAt/ResetAt`; (b) `E_ResetClass`: **AUTO_RESET** closes when the condition re-establishes, **MANUAL_RESET** stays blocking (`WAIT_RESET`) until a deliberate, release-gated operator reset — never self-closing (§9.3 principle), and the Unit **refuses `Start`** while any such event is open; (c) automatic capture: `FB_UnitBase` raises an ERROR/MANUAL_RESET event from the rolled-up first-out on ERROR entry and marks it gone on exit — the event IS the diagnostic plus lifecycle, nothing double-authored (O1/O3); (d) per-Unit `Active[]` + closed `Ring[]` browsable over OPC UA; **`I_EventSink`** invoked at come and close so a DB/historian adapter subscribes later without touching the log — interface normative now, adapters deferred by design (exactly the user's "we don't have to code this now"); (e) ISA-18.2 state mapping, reset doubles as acknowledge.

Code: `E_Severity`/`E_ResetClass`/`E_AlarmState`/`ST_AlarmEvent`, `I_EventSink`, `FB_AlarmLog` (Raise/RaiseDiag/Gone/OperatorReset/SetSink, fixed arrays, `Blocking`), UnitBase wiring (`AlarmLog`, `_faultEvt`, Start gate, public `OperatorReset`). Severity is the sole presentation/priority axis. Suite `FB_AlarmLog_Tests`: AUTO closes with Duration into the ring; MANUAL survives condition-gone and unblocks only on OperatorReset; Unit refuses Start while blocking.

**Honest gap:** the third test asserts Start-blocking by raising through the log directly; the *automatic* ERROR-entry capture path in `OnCyclic` is wired but not yet asserted by a test (FB_ProbeUnit has no easy fault injection). Add a `SimFaultStep` input to the probe and assert `AlarmLog.NActive = 1` after a forced fault — small item for the next pass or first compile session.

## 12. User access levels — §7.7 implemented (2026-07-04)

New Core §7.7: access level as the **who** dimension of release, ANDed with §7.2–§7.6's machine dimensions. Ordinal `E_AccessLevel` (NONE<OPERATOR<TECHNICIAN<ENGINEER<ADMIN); nine `E_GatedAction`s covering exactly the user's list (data read/write, manual — with per-function override via §7.6 —, changeover, mode change, start/stop, alarm history, alarm reset, policy edit). **Per-station policy** = persistent station config (§3.8a); **shipped default fully open** (every threshold NONE ⇒ no login needed — the deliberate-decision principle: locking down is a commissioning choice per §14 checklist, never silent). `I_AccessProvider` + `FB_LocalAccessProvider` default (persistent user/PIN table) mirror the provider pattern; `FB_AccessManager` per root: data-driven login per §3.10(a′) (methods are invisible to OPC UA), secret cleared after every attempt, idle auto-logout, audit via §8.3 MESSAGE events. Gated in `FB_UnitBase`: `SetMode`/`SetModel`/`Start`/`Stop`/`OperatorReset`. Cascade safety: thresholds enforce at the root the HMI addresses; framework-internal calls are trusted (documented in §7.7(c)) — with fully-open child defaults the cascade is unaffected in every configuration. Suite `FB_Access_Tests`: open-by-default; threshold denial audited; wrong-PIN rejected; login grants; secret cleared; logout re-denies. Deferred to their owning phases: `DATA_WRITE` enforcement in the generic editor and per-function `MANUAL` in the §7.6 implementation (both spec'd now). Security caveat, stated honestly: the local PIN travels the OPC UA write path — pair with server-side encryption/auth (§7.7(d), TC3 §11.1) for anything beyond shop-floor-trust deployments.

## 13. Configurable cylinder Control Module — FB_ConfigurableCylinderCM (2026-07-04)

A production-grade reusable cylinder CM alongside the Annex-A/B teaching `FB_CylinderCM`. Answers the brief (2 optional home/work sensors, 5 s default max move time) and adds what a real cylinder CM needs, each justified by an objective:
- **Optional AND redundant sensors (0..N per position).** `Cfg.HomeSensorCount`/`WorkSensorCount` (0 = sensorless/time-based; N up to `PL_Fraktal.MAX_POS_SENSORS`, default 2, raise for 2oo3). HAL carries sensor **arrays** `HomeFb[]`/`WorkFb[]`. **Arrival = ALL wired sensors TRUE** (`_M_PosArrived`, AND-combine — the safest rule for safety cylinders). One type serves sensorless, single-sensor, and duplex/redundant actuators (O4/O1).
- **Your timing.** `MoveTimeout := T#5S` default; `SettleTime` debounce so a chattering reed switch can't false-complete; `TravelTime` for the sensorless path (must be `< MoveTimeout`, checked).
- **Plausibility & integrity faults** (own §8.8 band 10200s): `CYL_WORK/HOME_NOT_REACHED` (timeout), `CYL_DISCREPANCY` (redundant sensors for one position disagree longer than `DiscrepancyTime` — dual-channel monitoring, like a safety-gate discrepancy timer; checked continuously in OnCyclic), `CYL_BOTH_SENSORS` (home+work both confirmed — implausible), `CYL_SENSOR_LOST` (reserved), `CYL_CFG_INVALID` (count out of range or bad travel/timeout — bad config faults, never runs wrong; O3/O7).
- **Single- or double-acting** (`SingleActing`: spring return drives home with no solenoid), **fail-safe abort** (`DeenergizeOnAbort` default, or drive to `SafePosOnAbort`) per §3.14.2, **startup position resolve** (`Position`/`AtPos` from whatever sensors exist, §3.12).
- Inherits the whole lifecycle: edge/handshake, ErrorID, per-command timing (§8.11.4 `TO_HOME`/`TO_WORK` tags), abort routing. `FB_ConfigurableCylinderSim` (per-sensor stuck-mask to inject faults) + `FB_ConfigurableCylinderCM_Tests` (duplex AND-arrival, discrepancy, sensorless, and timeout cases). SIM force hook for interlock (§5.7).

## 14. Fieldbus ADS adapter — contract sketch (2026-07-04)

Deliverable so an integrator can wire real EtherCAT data. Not runnable against a master here — a *seam + guide*, honest about what needs InfoSys verification.
- **PLC seam:** `I_FieldbusScanner` (Scan / RefreshValues / ForceChannel) + `FB_EcFieldbusScanner` skeleton naming the real `Tc2_EtherCAT` building blocks (`FB_EcGetSlaveCount`/`GetAllSlaveStates`/`GetSlaveIdentity`, `FB_CoeSdoReadEx`) with TODO bodies and a working AL-state→`E_NodeState` map (`_M_MapState`, low-nibble 0x01/0x02/0x04/0x08 + 0x10 error bit). Flat node table (`MAX_BUS_NODES`).
- **HMI seam (historical):** this pass originally added an `EtherCatGatewayRepository` stub; §41 supersedes it with the native OPC UA repository and versioned Web gateway client.
- **Doc:** `fraktal-tc3/FIELDBUS_ADS_ADAPTER.md` — two deployment paths (A: PLC-published `ST_BusNode` over OPC UA, works on all 4 platforms incl. Web; B: direct client, no Web without a gateway), the channel-value design (read the process image via HAL references, not raw addresses — keeps the channel↔module link exact), the honestly-flagged force path (write mapped output vs true ADS force), and an acceptance checklist. TC3 §10.6 points to it.
- **Objectives:** O4/O8 (any bus fills the same table; neutral node state), O1 (fieldbus knowledge in one place, Path A), O3 (topology + alarms are one source, not a side-channel). The force path re-uses §7.6/§7.7 gating + §8.3 audit — the caller gates and logs, the scanner only writes.

## 15. Manual command surface — §7.6.1 (2026-07-04)

Single manual path (MANUAL-mode-only, no override). Each command-bearing module publishes a self-describing `{value,label}` catalog. `FB_ModuleBase` owns the generic request latch, and `FB_UnitBase.ManualCommandTo` is the mode/access/release gate. `FB_ConfigurableCylinderCM` demonstrates that the HMI, generic interface, and typed PLCopen path all reach the same validated dispatch and interlocks. `FB_ManualCmd_Tests` covers publication, rejection outside MANUAL, and acceptance in MANUAL.

## 16. Mode control bar + switch policy + run styles — §3.4.1/§3.4.2 (2026-07-04)

*(Refinements: `_M_StepGate` gained a per-step `Steppable` input — a step passed as FALSE runs through even in SINGLE_STEP/HOLD_TO_RUN, both styles honouring it identically. `StopPending` property (TRUE while stop requested + still BUSY) drives a blinking stop button in the HMI. On the pinned 4024 binding every method input is explicit; optional method inputs require 4026+.)*


Resolved the tension in the brief (immediate-interrupt vs safe-finish vs disabled-per-mode) with the rule **Stop is graceful, mode-change is the interrupt**, and made the interrupt behaviour per-mode policy. Spec §3.4.1: two orthogonal axes — `E_ModeSwitchShield` (INTERRUPTIBLE/CONFIRM/BLOCKED_WHILE_RUNNING) × `E_ModeSwitchStyle` (GRACEFUL/IMMEDIATE) — as `ST_ModePolicy[E_Mode]`, station config with safety defaults (AUTO=CONFIRM+GRACEFUL, CHANGEOVER/CALIBRATION=BLOCKED, HOME=INTERRUPTIBLE+IMMEDIATE). The policy of the mode being LEFT governs. §3.4.2: `E_RunStyle` (CONTINUOUS/SINGLE_STEP/HOLD_TO_RUN), optional per mode via `_M_SupportsRunStyle`, consulted by the sequence author through `_M_StepGate` at step boundaries. **HOLD_TO_RUN over HMI is explicitly NON-SAFETY** (no dead-man; interlocks still apply) — spec callout + code comments.
Code (FB_UnitBase): `ModePolicy[]`, `RunStyle`, shield check in `SetMode` (BLOCKED returns FALSE while BUSY — graceful rejection, not a fault), style applied in the pending-mode path (GRACEFUL sets `_stopReq` to finish the cycle; IMMEDIATE keeps the OnModeExit/OnAbort path), `_M_InitModePolicy`, `SetRunStyle`/`_M_SupportsRunStyle`, `StepRequest`, `SetHoldRun`, `_M_StepGate`. 116 PLC files pass.
HMI: `ModeBar` on the right (mode icon + selector top, play/stop bottom, step toggle), reads `running`/`runStyle`/`supportedModes`/`supportedRunStyles`/`modePolicy`; prompts/blocks per policy; MANUAL hides run controls; hold-to-run is press-and-hold labelled non-safety. Repo methods `setRunStyle`/`stepRequest`/`setHoldRun` on both impls. 19 Dart files pass.

## 17. Show-why-blocked release transparency — §7.6.0 (2026-07-04)

Rule: pressing any not-released control shows why. Full rollup (user's choice), persistent bottom panel (user's choice). Spec §7.6.0: every gated action publishes, on demand, the complete set of withholding reasons (not first-out) across mode/access/alarm/interlock sources; live; read-only (never bypasses). Code: `ST_ReleaseReason` DUT; `FB_PermIntlk.AppendFailed` (enumerates every defined+FALSE+non-bypassed condition into a caller list); `FB_UnitBase.WhyBlocked(action, list)` assembles framework reasons (access via Access.Permits, mode-pending, AlarmLog.Blocking, not-READY, not-MANUAL) + delegates child interlocks to overridable `_M_AppendModuleReasons`; probe Unit demonstrates the override via `Cyl.Intlk.AppendFailed`. 117 PLC files pass. HMI: `ReleaseReason` + `ModuleNode.blockReasons` (per GatedAction), `whyBlocked` on both repos, `WhyBlockedPanel` at the bottom of the module view (auto-updates, shows 'released' when free), blocked Start (amber, reveals why) + blocked manual buttons (reveal panel) — pressing a blocked control shows reasons instead of no-op. 20 Dart files pass. Objective O3 (diagnosability) applied pre-action, not just post-fault.

## 18. Release panel wiring fix — blocked buttons now actually open it (2026-07-04)

### 18.1 Extended to all gated controls (2026-07-04)
Applied the same act-or-explain rule to the remaining controls. PLC: `FB_UnitBase.WhyBlockedAction(E_GatedAction)` — a general rollup (access + per-action state: CHANGEOVER not-while-running, ALARM_RESET needs a blocking alarm, MODE_CHANGE not-while-pending) using the same predicate as the gates; Start keeps its richer `WhyBlockedStart` (interlocks), manual keeps `WhyBlockedManual` (target). HMI: generic `whyBlockedAction`/`showWhyBlockedAction`; mode-bar **step** and module-detail **Stop**, **operator-reset**, **changeover** now explain-when-blocked via the release panel (changeover made always-visible instead of hidden below access). **Force** (fieldbus, channel-scoped not Unit-scoped) explains inline via a snackbar rather than the Unit panel — routing a channel concern through the Unit release report would be a category error. Every gated control is now pressable and either acts or explains; no silent dead buttons remain. 20 Dart + PLC gates pass.


Audit prompted by 'are the buttons ready to open it when not released?' found the honest answer was NO/inconsistent: (1) the mode-bar Start used `onPressed: permits && !stopPending ? .. : null` — a null onPressed can't fire, so the access-denied case was a DEAD button that couldn't open the panel; (2) two parallel release mechanisms had accreted across turns — `blockReasons`(node map)+`showWhyBlocked`+`why_blocked_panel.dart` vs this turn's PLC-query `releaseReport`+`showWhyBlockedStart/Manual`+`release_panel.dart` — with the mode bar mixing them; (3) module_detail had a duplicate Start/Stop (`: null` when blocked, never explained); (4) the dead sim `_blockReasonsA` built `ReleaseReason(str, str)` — a signature that no longer matched the domain (`description, kind`) and would not compile. Fix: consolidated on the PLC-query path, deleted `why_blocked_panel.dart` + `blockReasons` + `blockPanel*` + dead `whyBlocked(singular)`; made every blocked-press (mode-bar Start, module_detail Start, manual buttons) stay pressable and call `showWhyBlockedStart/Manual` (act-or-explain); sim `whyBlockedStart` returns reasons for all four causes so the panel is never empty. Rule now uniform: a blocked control is pressable and either acts or explains — never a silent dead button. 20 Dart files pass.

## 19. Rename WhyBlocked → ReleaseReport (2026-07-04)

Renamed the live release-query API for consistency with `ST_ReleaseReport` / the release panel: PLC `WhyBlockedStart/Manual/Action` → `ReleaseReportStart/Manual/Action`; HMI `whyBlocked*` → `releaseReport*`, `showWhyBlocked*` → `showReleaseReport*`. The rename also flushed out **orphaned dead code** from the earlier (list-based) release iteration that the prior consolidation had missed: `FB_UnitBase.WhyBlocked : INT` and its `_M_AppendModuleReasons` hook (uncalled) were deleted, and stale `WhyBlocked`/`why_blocked_panel` references in the spec §7.8 and HMI_CONTRACT were updated (a stale contract paragraph removed). Historical change-log entries in this file (§17/§18) intentionally retain the old names — they record what the code was called at the time. 120 PLC + 20 Dart files pass; reference audit clean.

## 20. AAS / digital nameplate — verification & completion (2026-07-11)

Follow-up to the trends gap analysis (item 2). Found a prior session had already built most of it: §3.10.1 spec, `ST_Nameplate` (IDTA-02006-shaped), `SetNameplate` on `FB_ControlModuleBase` (inherits everywhere), HMI `Nameplate` domain + `NameplateCard` + sim data, and **Annex K** (AAS/IEC 63278 mapping, sibling of Annex J). This session verified and completed rather than duplicated:
- **Fixed compile-blocking literal `\n` bugs**: `SetNameplate`'s body (prior session) and `FB_ProbeUnitManual`'s `SetAir`/`_M_AppendInterlocks` (this conversation's own earlier edit) contained literal backslash-n instead of newlines — XML-valid, VAR-balanced, invisible to the structural gates, but not compilable ST. Fixed both files (8 occurrences); added a literal-`\n` scan to the gate run.
- **Example now honours the §3.10.1 'shall'**: `MAIN` publishes nameplates for both root Units at the instantiation site (per-serial identity, shared type data), demonstrating that identity belongs to the machine builder, not the type.
- **`Nameplate_roundtrip` test** added to `FB_Hmi_Tests` (nameplate is part of the HMI contract); first version referenced a nonexistent `_probe`, caught and corrected to `_p` before delivery.
- Audit extended to annex letters A–K; HMI_CONTRACT gained the nameplate section. 121 PLC files + Dart pass.

## 21. OEE + trend HMI — §8.5.1 (2026-07-11)

Trends gap item 3. OEE is a derivation from existing contracts (GoodCount/NokCount §8.11, ExecState §6.1, Blocking §8.3) — only time accounting added. Spec §8.5.1: run/down/idle buckets per scan (idle excluded from A — no demand ≠ downtime; buckets published so deployments re-derive); A×P×Q with per-factor validity, invalid factors OMITTED from the product (never 100%, O7); Performance only with a configured per-model ideal cycle (§3.8), capped at 1.0; bounded trend ring (60 × 1 min defaults), long-horizon = historian; ResetOee DATA_WRITE-gated + §8.3-audited.
Code: ST_Oee/ST_OeeSample; FB_UnitBase `_M_OeeUpdate` (F_Now deltas, UDINT-ms wrap-safe subtraction) split from pure `_M_OeeCompute` (testable without clock control), SetIdealCycle, ResetOee. Tests FB_Oee_Tests via probe driver: Q from counters, A from buckets, invalid-P omitted (OEE=A×Q proves no fake 100%), P cap at 1.0. Time *accumulation* is runtime-verified, stated in the suite header. 124 PLC files pass.
HMI: OeeSnapshot domain, OeeCard (exception colouring vs 0.85 target, per-factor bars, '—' for invalid, CustomPaint sparkline — zero packages), resetOee on all repos, act-or-explain reset via the release panel. Sim: quality live from counters, availability dips on the CylB fault, 24-sample trend. 20 Dart files pass.
Watch items for first compile: TIME_TO_UDINT (recurring), REAL comparisons in TcUnit (AssertEquals_REAL Delta signature).

## 22. Alarm shelving + rationalization — §8.9/§8.10 (2026-07-12)

Roadmap closer. Spec already governed shelving (§8.10); added the hard rule: **shelving suppresses annunciation, never control** (shelved blocking alarm still blocks; interlocks/release reports untouched; SAFETY never shelvable; unrationalized reasons not shelvable — rationalize first).
Code: E_GatedAction += ALARM_SHELVE=9 (ordinal-safe append; ST_AccessPolicy widened 0..9); ST_AlarmEvent += Shelved/ShelvedUntil (appended, mirror-safe); ST_AlarmMeta + FB_AlarmLog.RegisterMeta/Meta catalog; FB_AlarmLog.Shelve/Unshelve (SAFETY+meta checks, capped at MAX_SHELF_S, self-logging) + Cyclic auto-expiry countdown (F_Now deltas), ticked from FB_UnitBase; gated ShelveAlarm/UnshelveAlarm on the Unit. MAIN registers example rationalization (discrepancy non-shelvable, work-timeout shelvable). Tests FB_Shelve_Tests: unrationalized refused, SAFETY refused, **shelved-still-blocks (the O7 test)**; expiry timing runtime-verified.
**Collisions found & fixed while wiring:** (1) `CYL_BOTH_SENSORS` declared TWICE in PL_ModuleReasons (10103 + 10203) — duplicate-identifier compile error; production one renamed CYL_POS_IMPLAUSIBLE. (2) The basic-cylinder band 10201–10206 **squatted on the axis CM's registered band 10201–10204** (§8.8 registry = one number space) — renumbered to 10110–10116 inside the cylinder CM 100-block and registered. Audit extended: GVL duplicate scan + band-squat check now run every pass.
HMI: GatedAction.alarmShelve (ordinal 9 verified), AlarmEvent += reasonCode+shelved, AlarmMeta joined onto rows ('→ operator action'), shelved rows de-emphasized + banner-excluded (never hidden), shelve/unshelve buttons with act-or-explain. 126 PLC + 20 Dart pass.

## 23. Release implementation audit — hidden issues found & fixed (2026-07-12)

User-requested audit of §7.8 (PLC + HMI). Verified clean: FB_PermIntlk.AppendFailed member usage (_conds/.Defined/.Description/.Reason/.Bypassable, _bypass, Cond — all exist as used); AlarmLog.Raise call-site parameter names (Kind/Reason/Text/Source/Severity/Category/ResetClass match); E_Reason.NONE exists; module-detail Start/Stop are Unit-only; ReleaseReason ctor usage matches the domain.
Three real issues found and fixed:
1. **Sim query≠gate drift (O7 violation):** `releaseReportStart`'s mode reason was gated on `!_convWarn` — a ConveyorB flag unrelated to StationA — so a blocked-by-mode Start could report Released=TRUE. Also sim `start()` ignored mode entirely while the query reported a mode reason. Fixed both: reason condition is `_modeA != auto`; `start()` gate is now the same predicate the query reports.
2. **Stale release panel:** nothing re-ran the query while visible, so "stays while blocked / clears when released" and the panel's green 'Now released' state could never occur. Fixed: app-state stores the active query closure and re-runs it on every forest update (re-entrancy-guarded); clearRelease drops it. The panel is now live, matching §7.8's contract.
3. **ReleaseReportManual originally ignored its exact target and command:** the selected child's §7.6 conditions couldn't be appended, and a directional device could not distinguish extend from retract. The query and hook now carry `(TargetPath, Value, Report)`; the base preserves its Unit-level fallback while concrete Units may delegate to the selected child's pure release query.
Known remaining (unchanged, cosmetic): mode-bar Stop-while-running-without-access falls back to releaseReportStart. All gates pass.

## 24. Full-codebase semantic audit — both PLC and HMI (2026-07-12)

New checks beyond the structural gates: (1) named-parameter call sites vs actual METHOD signatures across all POUs; (2) every `PL_*.<CONST>` reference exists in its GVL; (3) every `E_*.<MEMBER>` reference exists in its enum (proper parser incl. single-line enums); (4) method calls on typed FB instances resolve through inheritance; (5) orphaned-public-method scan; (6) full HMI↔PLC enum-ordinal matrix (15 pairs); (7) both repositories implement all 20 contract methods; (8) all `app.<x>` UI references exist in app_state.

**Compile-blocking bugs found & fixed (root cause: `if X not in file` idempotency guards silently no-op'ing when an OLD artifact already carried the name):**
1. `FB_PermIntlk.AppendFailed` was still the OLD §7.6.0 list-based signature (`List/Count/Source`) — the §7.8 guard skipped writing the Report-based one; every current call site targeted a nonexistent signature. Replaced (verified single, Report-based).
2. Four `PL_Fraktal` constants never landed (`MAX_OEE_SAMPLES`, `OEE_SAMPLE_MS`, `MAX_ALARM_META`, `MAX_SHELF_S`): `MAX_RELEASE_REASONS` already existed at 24 (not the expected 16), so the OEE anchor missed and each later constant chained on the previous missing one — a silent cascade. All four added with post-verification.
3. Invalid event-kind members in `FB_Shelve_Tests` exposed a duplicate taxonomy. Alarm presentation now uses the single `E_Severity` axis.
4. Orphaned `_M_AppendModuleReasons` override in FB_ProbeUnitManual (base counterpart deleted in the rename turn) calling the old AppendFailed signature — deleted.
**HMI:** all contract enum ordinals match; repositories are complete and UI→state references are clean. Fixed `_Blink` running its ticker permanently (now animates only while active). `E_Severity` is mirrored as Dart `Severity`; event kind is no longer a second priority axis. Remaining orphan-scan hits are intentional HMI/OPC-UA entry points and adapter seams.
**Process change:** idempotency guards are retired in favour of anchored edits with post-assertions; the combined semantic gate (checks 1–4) joins the standard gate run.

## 25. TCP/IP device CMs — byte-transport seam + ASCII device base (2026-07-12)

Answering "do we have a base for TCP/IP devices (Keyence IV3, Datalogic Matrix 220)?": we had the *upper* half (FB_DeviceConnectorBase §3.15 link supervision, transport-agnostic) but no transport seam and no request/response CM base. Added, spec-first (Core §3.15.1a + TC3 §3.15):
- **`I_ByteChannel`** — THE porting seam (O4/O8): non-blocking Open/Close/Send/Poll/State/Tick, cyclic-poll semantics. TC3 binds via Tc2_TcpIp (TF6310); CODESYS SysSocket/NBS; Siemens TSEND_C — device CMs never name a socket API and port unmodified.
- **`FB_AsciiDeviceCM`** (CM base): configurable terminator framing, one-outstanding-request state machine, response timeout ⇒ fault, RX-overflow guard, bounded-backoff reconnect, LinkState published (Annex D facet — zero new HMI code). Reason band **10401–10406** (`PL_TcpDevReasons`, registered §8.8).
- **`FB_SimByteChannel`** — scripted channel: device CMs TcUnit-test end-to-end with no socket/hardware. `FB_TcpDev_Tests`: request→scripted reply→parse (terminator stripped, judgement set); SwallowNext→**10402 timeout** (cyclic test, runtime TON).
- **`FB_TcpChannelTc3`** skeleton naming FB_SocketConnect/Close/Send/Receive with TODO bodies — verify signatures/TF6310 license/TcpIpServer against InfoSys.
- **Profiles** `FB_Iv3VisionCM` / `FB_Matrix220CM` (`Fraktal_Modules`): publish 'Trigger' (§7.6.1), Execute path completes on parsed response, IV3 OK/NG judgement, Matrix decoded-code/NOREAD. **Protocol strings are Setup-visible parameters explicitly marked VERIFY-vs-vendor-manual — typical forms, not confirmed facts.**
132 PLC files pass the combined gate. Watch items: `TIME * INT` backoff doubling, `FIND/DELETE` string semantics, `'$R'` terminator escape — first-compile checks.

## 26. Device-category CMs — configure first, extend second (2026-07-12)

User correctly flagged a philosophy inconsistency in §25: the CM layer is function-first (`FB_ConfigurableCylinderCM`, not `FB_FestoCylinderCM`), yet the TCP layer jumped to vendor-model CMs. Restructured to match the standard's own philosophy:
- **`FB_TcpVisionCM`** and **`FB_TcpCodeReaderCM`** (new `DeviceCMs/` in the Core library, non-abstract): CATEGORY CMs directly usable for most devices via configuration alone — protocol strings are §3.8-able parameters (TriggerCmd, Ok/NgPrefix + ResultSep payload extraction; NoReadText + optional MatchCode verification). Both publish Trigger (§7.6.1), complete Execute on the parsed response, fault DEV_PROTOCOL on garbage.
- **Model FBs became thin presets**: FB_Iv3VisionCM / FB_Matrix220CM now EXTEND the category CMs and contain only preconfigured strings in Setup — demonstrating the extension seam ("override _M_OnResponse only for genuinely special formats"). Chain: preset → category → FB_AsciiDeviceCM → FB_ControlModuleBase.
- **Tests retargeted to the category level**: the vision CM is CONFIGURED (not subclassed) for an IV3-style dialect in the test itself — proving the configure-first claim; reader test covers decoded-code + NOREAD + match verification; timeout test unchanged.
- Spec §3.15.1a amended with the category layer and its honest boundary: covers ASCII request/response; binary/unsolicited-streaming protocols need a different base (deferred until demanded).
134 PLC files pass. Watch item added: MID(str, len, pos) argument order in the payload extraction.

## 27. Cross-runtime latent-defect audit (2026-07-12)

Confirmed defects fixed at their shared seams: the Unit pending diagnostic now overlays `Status` only after the common mirror refresh; OEE and shelf expiry use the monotonic `TIME()` clock rather than assigning wall-clock `DT`; alarm-slot reuse clears shelving state and zero-duration shelves are refused; manual commands validate the published catalog and enter the inherited PLCopen lifecycle; typed cylinder/clamp dispatch rejects unsupported command values with registered reason 2008; failed `SetModel` restores the prior published identity; Step/Hold writes are PLC-gated; terminal Unit runs can be released by `Stop`; common-base `OnInit` and edge-triggered `OnAbortInError` now cover every module tier, and Unit initialization no longer erases an injected access provider. The HMI access-policy mirror now covers all ten gated actions and fails closed on a stale short array, configuration writes use the repository instead of a placeholder snackbar, multi-root simulation keeps independent sessions, and duplicated detail controls no longer bypass the mode bar's switch policy. Regression coverage was added for the status overlay, automatic Unit fault capture, manual actuation, shelf reuse/zero duration, and HMI policy cardinality.

## 28. HMI connection bootstrap and execution roadmap (2026-07-12)

Added `Specification/IMPLEMENTATION_ROADMAP.md`, converting the objective/coherence review into ordered phases with explicit exit gates: executable root-Unit forest; inherited composite behavior; physical four-structure contract and transactional recipes; authoritative manual release; trustworthy diagnostics/KPIs; production HMI transport; generated interoperability projections; security and a second binding.

The HMI now starts behind `ConnectionBootstrap`. First use or an endpoint never proven `LIVE` opens a wizard; previously proven settings reconnect behind a full-screen interaction lock. `STALE`/`DOWN` removes the shell immediately, no writes are queued, and connection editing appears only after 30 seconds without `LIVE`. `everConnected` is persisted only after a repository reports `LIVE`. SDK-only persistence keeps the zero-package policy (native JSON file / Web local storage). Widget tests prove first-use, 30-second timeout, and live-link-loss behavior. The production OPC UA/gateway repository remains deployment work and therefore fails closed rather than presenting an empty interactive HMI.

## 29. Reusable-module library identity (2026-07-12)

Renamed the former example-oriented project to `Fraktal_Modules`. The project contains reusable shipping module types, simulation models, and configured device presets; calling it “Examples” understated its supported-library role and encouraged copy/paste use. The physical directory and `.plcproj`, TwinCAT project name/title/default namespace/placeholder, dependent test-library reference, documentation, and `PL_ModuleReasons` symbol now share one identity. Object and project GUIDs were deliberately preserved so the rename does not manufacture new TwinCAT objects.

## 30. Aggregate test-gate identity (2026-07-12)

Renamed the aggregate PLC test project to `Fraktal_Tests`. Its single TcUnit runner covers both `Fraktal_Core` framework behavior and `Fraktal_Modules` reusable types, so a Core-only name misrepresented the gate. The directory, `.plcproj`, TwinCAT name/title/default namespace, normative binding text, and working documentation now agree. It is an executable test application and therefore deliberately has no library placeholder metadata. Project and object GUIDs remain unchanged. If independent release trains later justify separate gates, split this aggregate into per-library Core and Modules test applications; until then, one aggregate name matches the existing one-gate architecture.

## 31. Contract vocabulary and ownership cleanup (2026-07-12)

Resolved the semantic conflicts found by the whole-standard review. A root Unit tree is one **station**; a PLC/cell scope may host a forest of stations. `FB_ModuleBase` now owns the common PLCopen lifecycle, `FB_CompositeModuleBase` owns recursive child behavior, and the CM/EM/Unit bases are tier wrappers—so Unit no longer inherits an Equipment-Module identity. CM and EM interfaces share `ExecuteCommand`/`AbortCommand`; the duplicate `ST_CmStatus` was removed.

Recipe lookup now uses `(ModelCode, RecipeKey)`, and Unit changeover prepares and validates the complete subtree before commit. The shipping Cylinder and Clamp modules publish physical `ParCfg`/`ParCmd`/`OutCmd`/`OutImm` structures. `FB_BasicCylinder` was renamed `FB_ConfigurableCylinderCM` to express capability and tier. Alarm priority now has one axis, `E_Severity`; the redundant event-kind axis was removed from PLC and HMI. `E_Mode` remains an append-only Core/HMI ordinal contract until a generated identifier mapping replaces ordinals.

The TcUnit runner was also corrected to instantiate every compiled suite; previously nine compiled suites were silently absent from execution. Source/XML/project-list and Flutter gates are rerun after this migration. TwinCAT compilation remains required before declaring the draft binding release-ready.

## 32. First pinned TwinCAT compiler feedback (2026-07-12)

The first build log from TwinCAT 3.1.4024 reduced 514 reported errors to a few parser root causes. Fixed across all projects: TwinCAT does not accept `VAR PROTECTED`; `VAR_TEMP` is not allowed in methods; keywords are case-insensitive and cannot be identifiers (`Action`, `Log`, `Min`, `Max`, `S`, `R`, `DT`); and an apostrophe inside a STRING uses `$'`, not doubled SQL-style quotes. Public timing fields are now `Minimum`/`Maximum`, access arguments use `Gate`, audit locals use `AuditSlot`, and elapsed-time locals use `CurrentTime`/`DeltaMs`. A reserved-keyword scan is now part of the structural gate.

The same log exposed packaging conflicts: the reusable `Fraktal_Modules` library contained `MAIN` and `PlcTask`, and `Fraktal_Tests` contained `PlcTask` while still carrying library placeholder metadata. TwinCAT correctly refused those runtime objects as library content. Demo application objects now live in `Fraktal_Demo`, and the placeholder was removed from the executable test project. The demo hosts two real `FB_ClampStationUnit` roots rather than presenting Equipment Modules as root Units. `Fraktal_Core` and `Fraktal_Modules` are libraries; `Fraktal_Demo` and `Fraktal_Tests` are applications.

## 33. Second pinned TwinCAT compiler feedback (2026-07-12)

The next 4024.12 compile removed the parser cascade and exposed binding-level assumptions. Beckhoff added optional method inputs only in 3.1.4026, so all default-valued method inputs were removed and every 4024 call now supplies every argument. TwinCAT also enforces IEC encapsulation: another POU can access only a function block's `VAR_INPUT`/`VAR_OUTPUT`, not its local `VAR`. The four-structure contract and common published data are now mapped accordingly; private lifecycle state remains local. Test-only mutation of Unit OEE internals was replaced by a probe method, and access-policy setup uses a bounded configuration method.

`I_Module` now extends `__System.IQueryInterface`, satisfying `__QUERYINTERFACE` for Unit capability cascade. `Fraktal_Demo` directly references `Tc3_Module`, resolving the generated task FB's `IecTaskModule`, `S_OK`, and `fb_init` dependencies. The test application remains non-library in the canonical project; any repeated “Object not added to library” message identifies a stale copied `.plcproj`.

## 34. Third pinned TwinCAT compiler feedback (2026-07-12)

The third 4024.12 compile reduced the binding to eleven test-only access errors. A child function block exposed through a parent's `VAR_OUTPUT` is readable, and its public methods are callable, but TwinCAT does not permit a caller to assign that nested child's `VAR_INPUT` through the parent output. Access tests now use `FB_AccessManager.RequestLogin`/`RequestLogout`; the EM and manual-command probes own their fault/abort injection methods. These seams preserve encapsulation and leave the OPC UA request-symbol contract unchanged. Login/logout request bits are now consumed directly and self-cleared; the former `R_TRIG` implementation cleared the bit only after sampling it, so the trigger never observed a low scan and could ignore a consecutive request.

The compile log still referenced a separate copied solution under `FraktalAutomation\FraktalAutomation`. The canonical `Fraktal_Tests.plcproj` has no library placeholder metadata; a repeated “Object not added to library” message for `PlcTask.TcTTO` therefore comes from the stale copied project and requires replacing or refreshing that project in the XAE solution.

## 35. Safety and control-power foundation (2026-07-13)

Added the optional Core §9.8 profile and `SAFETY_AND_CONTROL_POWER_PROFILE.md`. Every module now inherits hidden-by-default `Safety : ST_SafetyStatus` and `ControlPower : ST_ControlPowerStatus` facets. The records cover device kind/state, demand, reset, muting, keyed bridge, affected power groups, group request/feedback, safety permit, fieldbus health/reaction, and deliberate rearm. `POWER_CONTROL=10` was appended to the access-policy ordinal contract; existing ordinals are unchanged.

`FB_PowerGroupCM` is the first basic reusable implementation. It owns an ordinary functional-enable request, never a safety output; it withdraws that request when its safety permit drops or a configured fieldbus-loss reaction requires power removal, latches rearm, and never self-energizes when health returns. Its reserved reason band is 10500–10599. The HMI renders both facets generically and the simulation demonstrates a door, light curtain, safety valve, and two valve-island zones. Certified door locking, muting/override, bridge, FSoE safe output mapping, and risk validation remain in TwinSAFE by design.

The ownership model was corrected before coordinator implementation: safety/control power is an optional cell-scope **control domain**, not inherently Unit-owned. `ST_ControlDomainStatus` carries a stable ID, readiness, safety/power aggregates, and member root paths. `FB_UnitBase.ControlDomain` accepts zero or one domain; several Units may consume the same record. That application-fed input is explicitly excluded from OPC UA. `Start` gates only an assigned domain's `ReadyForStart`; `Present=FALSE` deliberately adds no gate. The Unit republishes read-only `Domain`, `Status.ControlDomainId`, and facet mirrors for discovery. The domain coordinator itself remains deployment/application infrastructure rather than a fourth module tier.

The HMI connection settings schema is now v2. After the endpoint reaches LIVE, the wizard requires a root-Unit assignment. `ScopedPlcRepository` filters discovery and rejects reads/writes outside the saved assignment; legacy v1 settings migrate to an incomplete selection and therefore reopen step 2. Missing paths fail closed. ADMIN can reopen the assignment editor after login.

## 36. Catalog-owned HMI language and module content (2026-07-13)

Operator-facing PLC strings were converted to stable `std.*`/`project.*` localization keys, including command catalogs, diagnostics, interlocks, release reports, steps, audits, hardware, and I/O descriptions. Structured identity/protocol data remains untranslated. `ST_CommandInfo.Label`, timing/step/condition labels, and hardware description fields were widened or added for keys. The HMI now owns runtime standard/project catalogs, first-run language selection, locale switching, validated CSV import/export, module descriptions, PDF upload/viewing, and per-module section access policies. `file_picker`, `pdfrx`, and the Flutter-published `cupertino_icons` asset are the reviewed package exceptions. Local content storage is the shipped commissioning implementation; the `ContentStore` seam is the production shared-store boundary. See `Specification/LOCALIZATION_AND_MODULE_CONTENT.md`.

## 37. Pneumatic press worked application and two contract repairs (2026-07-13)

Added `Fraktal_Press_Demo`, an executable one-root virtual-commissioning application, and reusable
`FB_PneumaticPressUnit` / `FB_TwoHandStartCM` types in `Fraktal_Modules`. Three ordinary cylinder CMs
implement ram, door, and part slide; `FB_PowerGroupCM` supplies the functional pneumatic request. AUTO,
HOME, MANUAL, transactional ALUMINUM/PLASTIC/STEEL recipes, collision prevention, localization keys,
nameplate, alarm rationalization, control-domain facets, and TcUnit coverage use the existing contracts.
The two-hand CM consumes a certified result and only produces a release-before-rearm functional edge;
it explicitly does not calculate simultaneity or anti-tie-down. `E_SafetyDeviceKind.TWO_HAND_CONTROL`
was appended without disturbing existing ordinals.

Building the example exposed two shared seams. First, the HMI already offered Control On/Off but the
PLC had no published write endpoint. `FB_UnitBase` now owns edge-consumed `ReqControlOn/ReqControlOff`,
applies `POWER_CONTROL`, gives Off priority, and publishes one-scan coordinator requests. Power groups
no longer publish equivalent MANUAL commands. Second, cylinder collision rules were previously either
application-only or a generic forced interlock. `FB_CylinderCM.SetDirectionalPermits` now applies exact
extend/retract conditions to typed and manual execution. The manual release query now includes the
command value and delegates to `AppendDirectionalRelease`, so act-or-explain evaluates the same
directional permit as dispatch instead of reporting only the target.

The simulation also moved safe-output filtering to final output authority. Ordinary Unit logic runs
first; simulated certified logic then removes all requests on power loss and independently removes
ram-down without guard plus evaluated two-hand permission. This fixes a one-scan overwrite hazard in
the first draft and documents the required TwinSAFE/FSoE replacement. See
`Specification/PNEUMATIC_PRESS_EXAMPLE.md`.

## 38. CX2030 training-station physical I/O binding (2026-07-13)

Integrated the supplied `TrainningStation_IOs_V2.xlsx` map into the press application without leaking
terminal details into reusable modules. `GVL_PressIO` declares wildcard process-image symbols for the
EL1809/EL2809 channels; `MAIN` alone maps them into the cylinder, two-hand, power, part-presence, and
air-pressure HALs. The physical feeder retracts inside and extends outside, so that application mapping
deliberately inverts the generic slide position names. AUTO now requires part presence plus the valid
high-air/low-air combination before accepting the evaluated two-hand edge.

Simulation remains the default and explicitly clears every mapped output. Physical mode is fail-closed:
`GVL_PressSafety` input aliases default false until linked to evaluated safety results, and the ambiguous
`SwitchControlOn`/`EnableControlOn` pair remains off until its electrical behavior is confirmed. The
worksheet lists the E-stop and two-hand buttons only on ordinary EL1809 inputs and provides no safe
guard, safe pneumatic output/feedback, or evaluated two-hand result; these channels are therefore raw
diagnostic mirrors, not a safety implementation. It also calls reserved output channel 9 `EL2810`
while the other outputs are `EL2809`, and lists no physical Control On/Off input buttons. These items
are tracked in `Specification/CX2030_PRESS_IO_MAPPING.md` rather than guessed in code.

## 39. Electrical-tag diagnostic join (2026-07-13)

`ST_Diagnostic` now carries optional `IoTag` and `IoAddress` structured identity. The cylinder CM can
be configured with application sensor/output tags without importing terminal knowledge into reusable
device behavior; its position timeout and sensor-conflict first-outs attach the exact approved tag.
`FB_AlarmLog.RaiseDiag` preserves both fields through the active alarm and closed-event lifecycle;
the ordinary `Raise` API remains source-compatible and supplies empty channel context.
`ST_IoChannel` now separates exact `Name`, localized `DescriptionKey`, physical `Address`, unique
force/audit `Path`, and owning `ModulePath`, plus fault-highlight fields.

The press application publishes its supplied EL1809/EL2809 list as a bounded OPC UA fieldbus table.
The HMI renders tags verbatim, descriptions in the active language, cross-navigates to the module, and
highlights a channel whose tag matches a live first-out. The application publisher currently consumes
the aggregate standard-I/O health alias; it is a label/value adapter, not a replacement for the
deployment-deferred EtherCAT scanner/master diagnostic integration required by Core §10.5.1.

## 40. I/O responsibility distribution made normative (2026-07-13)

The first press fieldbus implementation proved the data contract but placed project metadata, live
process-image copying, topology validation, health propagation, and diagnostic correlation in one
application FB while `MAIN` also performed raw channel mapping. That shape contradicted the intended
“basic reusable mechanism + thin composition” architecture even though it was functionally correct.

Core §10.2.1 now defines mandatory ownership. `FB_IoTopologyPublisher` is reusable infrastructure for
bounded registration, validation, health and exact-tag diagnostic joins over `ST_FieldbusTopology`.
`FB_PressIoCatalog` is static project engineering data and injects `ST_CylinderIoIdentity` role records.
`FB_PressIoDriver` alone accesses `GVL_PressIO`, maps semantic HALs, writes physical outputs and refreshes
live topology values. `FB_PressSimulationDriver`, `FB_PressControlDomain`, and
`FB_PressOutputAuthority` isolate simulation plant behavior, domain aggregation, and final functional
withdrawal respectively. `MAIN` selects paths and orders calls without individual channel assignments
or domain-device construction. The project-specific catalog remains intentionally explicit until
generated from the approved I/O workbook; reusable algorithms no longer live beside those rows.

## 41. Native OPC UA repository and acknowledged HMI mailbox (2026-07-13)

The original connection wizard exposed `opc.tcp` while its external repository
was a throwing placeholder. Windows now builds a native `fraktal_opcua` DLL from
pinned open62541 1.4.12 and Mbed TLS 3.6.6. Dart FFI calls run exclusively in a
worker isolate; a generic flat snapshot mapper discovers modules only through
`Status : ST_ModuleStatus`. Web compiles a client for the same snapshot/write
contract over the versioned Fraktal WebSocket gateway protocol.

The integration audit also exposed that several HMI operations existed only as
IEC methods, which OPC UA cannot call. `FB_UnitBase` now publishes
`ST_HmiRequest`/`ST_HmiResponse`: arguments first, changing Sequence last,
AckSequence last after processing. The base routes supported requests through
the existing gated methods and publishes property-only mode/running/stop state
as data. Type/project-specific configuration writes and fieldbus output force
remain fail-closed override hooks; identity-based alarm shelving is explicitly
refused until its slot-resolution adapter is supplied.

## 42. Explicit press mode sequences and discoverable recipes (2026-07-13)

Pinned TwinCAT feedback found an undefined `_airPressureOk` symbol in the press ram permit; the Unit
now consumes `AirPressureMonitor.OutImm.PressureOk` directly. The review also confirmed a visibility
problem: AUTO and HOME were step-number regions inside one large dispatcher, CHANGEOVER was not
supported, the project recipes were anonymous declarations in `MAIN`, and the native OPC UA mapper
did not project `CurrentStep` or `Decision`. The PLC contained behavior that the real HMI could not
show.

`FB_PneumaticPressUnit` now has a thin `_M_Dispatch` and separately reviewable
`_M_SequenceAuto`, `_M_SequenceHome`, and `_M_SequenceChangeover` methods. CHANGEOVER establishes the
load-safe position and waits for deliberate tooling/material confirmation. `FB_PressRecipeCatalog`
owns the ALUMINUM/PLASTIC/STEEL engineering records and feeds the generic local provider. Units may
publish a bounded available-model catalog; the HMI renders it as a selector, performs the
mode→transactional model→Start flow, and projects live step conditions and decision prompts over the
same generic OPC UA mapper. `_M_TakeDecision` now consumes and clears the answer, preventing a stale
answer from automatically satisfying a later prompt.

## 43. TF6100 filtered root publication fix (2026-07-14)

A live CX2030 trace separated transport failure from address-space failure: TCP port 4840 accepted
the connection, open62541 opened a SecureChannel and activated an anonymous session, TF6100 loaded
`Port_854.tmc` successfully (`loadSymbols ret=0`) and kept ADS health checks alive, but browsing
`Objects` returned only namespace-zero `Server`. The retained rotated importer logs begin midway
through the 18-second import, so they cannot prove whether the earlier direct root record was parsed.

The trace proves the immediate blocker is TF6100 authorization/publication rather than networking:
the anonymous identity is activated but cannot browse the configured PLC Data Access object. Both
executable examples now also mark every root Unit declaration in `MAIN`, making the intended forest
explicit in addition to the supported type-level inheritance. Part I, Part II, the transport guide,
and `AGENTS.md` record the rule. The HMI's empty-forest diagnostic names the instance marker, TMC
reload, and OPC UA namespace authorization as distinct checks. The endpoint hostname returned by
`FindServers` was not the cause—the redirected session reached `Activated` before the empty browse.

The audit also corrected an overstatement in `OPCUA_TRANSPORT.md`: username support exists in the
native ABI but is not yet surfaced by connection settings. The current wizard connects anonymously;
persisting a server password in its JSON or sending one over `SecurityPolicy=None` would be an unsafe
shortcut. Temporary anonymous namespace rights are therefore commissioning-only; certificate trust,
secure credential handling, and authenticated least-privilege writes remain the Phase 7 production
security exit gate.

Because the copied server trace was older than the next HMI attempt and the active TF6100 files live
only on the remote PLC, the native snapshot now also reads the standard OPC UA
`Server/NamespaceArray`. An empty-forest error reports those URIs beside `Objects` children: a PLC
namespace present there but absent from `Objects` proves identity permissions are filtering browse;
an absent PLC namespace proves the remote Data Access NodeManager/TMC was not loaded. This diagnostic
is read remotely and does not assume TF6100 is installed on the HMI PC.

The subsequent synchronized client/server capture made the authorization diagnosis conclusive. The
client read `urn:BeckhoffAutomation:Ua:PLC1` from `NamespaceArray`, while the matching TF6100 trace
accepted an `AnonymousIdentityToken` and printed `Roles assigned to session` with no following role
entries. The same session received only `Server` when it browsed `Objects`. The HMI now recognizes
this combination and reports an access-filtering error directly instead of also suggesting a missing
TMC or root publication marker. The remote TF6100 user/group mapping and recursive PLC1 browse/read
rights must be corrected; anonymous access remains commissioning-only.

## 44. Authorized large-tree browse and HMI mailbox starvation fix (2026-07-14)

After assigning the commissioning identity to TF6100's Users role, discovery
advanced to `LIVE` and the HMI rendered `PneumaticPress`. Mode controls still
appeared inert and the Dart debugger repeatedly reported that it was waiting for
the `fraktal-opcua` isolate. This separated a PLC mode/enum problem from a client
scheduling defect: the native snapshot recursively browsed and individually
read up to 20,000 nodes every 500 ms. The single worker isolate therefore spent
nearly all of its time in snapshot FFI; mailbox writes queued behind it, while a
concurrent repository refresh could return early and test stale acknowledgement
data. Depth-first discovery could also consume the cap inside an implementation
subtree before reaching shallow `HmiRequest` leaves.

The native bridge now discovers breadth-first in bounded multi-node Browse
services, caches path-to-NodeId discovery for the session, and reads cached
variables with bounded multi-node Read services. Snapshots report `truncated`.
The Dart repository shares an in-flight refresh instead of skipping it, so a
mailbox request observes fresh acknowledgement data. Request start, individual
write/commit failure, acknowledgement with PLC diagnostic, and timeout are
logged without transported secrets. The request-kind and mode ordinals already
matched the PLC DUTs; no wire-contract ordinal change was required.

The resulting bring-up lessons are consolidated in
`Specification/FIRST_PROJECT_AGENT_GUIDE.md`, referenced by `AGENTS.md`. Part I
now requires layer-specific client status and acknowledged command success;
Part II records the TF6100 host, authorization, namespace, root, and mailbox
acceptance ladder.

## 45. TF6100 reference aliases projected as duplicate stations (2026-07-14)

The first cached/batched live browse exposed three root projections named
`PneumaticPress`; Flutter's station dropdown correctly asserted because three
items carried the same Fraktal path. The PLC application declares only one root,
but several infrastructure FBs retain `UnitRef` references. TF6100 can expose
those reference/owner paths with the referenced Unit's `Status`, and the flat
mapper previously treated any parentless `Status : ST_ModuleStatus` Unit as a
deployed root.

The first correction compared a candidate's local browse segment with the whole
`Status.Name`. The next live run proved nested modules intentionally publish
qualified identities such as `PneumaticPress.PressRam`, so that comparison
removed every legitimate child while retaining the root. The final mapper
compares the local browse segment with the **final dotted identity segment**,
deduplicates every module by the full `Status.Name`, constructs parentage from
the dotted prefix, and chooses the shallowest OPC UA path for each identity.
`UnitRef`-shaped aliases are discarded; direct children remain. Discarded paths
are logged once per changed alias set. `AppState` also removes duplicate root
paths defensively so an invalid repository payload cannot crash a station
selector. Regression fixtures prove the direct root and qualified child survive
both alias forms. Part I §4.8 and the HMI/transport contracts now state the
local-browse versus qualified-identity distinction explicitly. No
station-specific UI rule was added.

## 46. Login-result feedback and release-query feedback loop (2026-07-14)

Live commissioning exposed two HMI contract errors. First, the Unit mailbox acknowledges LOGIN when
`FB_AccessManager.RequestLogin` queues the attempt; the access provider evaluates it later in the same
PLC scan. Treating `HmiResponse.Accepted` as authentication success therefore displayed a false
success for a bad PIN. The OPC UA repository now uses the post-attempt `Access.LoginFailed`,
`CurrentUser`, and `CurrentLevel` snapshot as the authoritative result. The login dialog remains open,
clears the PIN, and gives localized generic feedback on failure.

Second, `AppState` refreshed an open release panel on every forest snapshot. Each release mailbox query
causes a fresh snapshot, so one rejected Start created an unbounded RELEASE_START loop. The panel now
appears immediately in a checking state, performs one query, and uses a controlled non-overlapping
two-second refresh while open. Empty rejected reports render an explicit publication/contract message.
Regression tests cover mailbox-consumed versus authenticated login, inline failure feedback, immediate
release visibility, and absence of snapshot-driven request recursion. No PLC wire ordinal changed.

## 47. §6.1 reset provenance, post-dispatch stall views, first-connect backoff (2026-07-14)

Running the full TcUnit gate against the live build exposed five Core defects that the press
example depends on; all were fixed at the base so every module type inherits the corrections.

**Execute-drop reset (§6.1) ran after output mapping and consumed non-command faults.**
`FB_ModuleBase.Cyclic` reset a terminal state at the bottom of the scan, so the scan in which
`Execute` dropped still published stale `Done`/`Error`/`Aborted` (T1/T4 red), and any fault raised
OUTSIDE a command — the §3.8 migrate-or-fault at Setup, cyclic condition monitors — was silently
consumed one scan later because `Execute` was low (T5 red). The reset now runs at the TOP of the
scan and is gated on command provenance (`_cmdArmed`, armed at the accepted rising edge): a
command-produced terminal state resets before this scan's mapping; a non-command fault latches. A
fresh command edge may retry from a latched non-command ERROR — the edge clears the diagnostic and
re-runs validation, which re-faults immediately if the cause remains. HOME/AUTO therefore recover a
CM whose idle condition fault has cleared; a bad recipe stays visible until remedied.

**`Starved`/`Blocked` were derived in `OnCyclic`, one scan before dispatch updated the step.**
The §8.11.4(f)/§8.11.3 views are now derived in `FB_UnitBase._M_PublishStatus`, which the base
calls after `_M_Dispatch`, so the wait class reflects the step record set THIS scan.

**`FB_AsciiDeviceCM` delayed the FIRST connect by the retry backoff and rejected same-scan sends.**
The CLOSED branch armed the 500 ms backoff before the first `Open()`, so every request in the
first half-second faulted `DEV_NOT_CONNECTED` (10404) instead of reaching the device — the TcUnit
suites saw exactly that. Backoff now spaces RE-tries only; the first `Open()` is immediate, and
`SendRequest` checks the live channel state instead of the one-scan-old `LinkState` cache.

**`FB_ConfigurableCylinderCM_Tests` looped a TON-based sim inside one scan.** TwinCAT task time is
frozen within a scan, so 20 ms travel/30 ms settle could never elapse; the three time-based tests
now use the standard multi-scan TcUnit pattern (one iteration per cycle, assert + `TEST_FINISHED`
on the terminal state or a 100-scan budget). The sims stay time-based — they are shared with
virtual commissioning (§5.7); `Timeout_faults` (PT=0) was already scan-exact and is unchanged.

## 48. Press example feature completion: run styles, §3.16 traceability, rationalization, users (2026-07-14)

A spec-coverage review of the press example found four normative capabilities the Core already
promised but the example (and in one case the Core) did not exercise.

**Run styles (§3.4.2).** `FB_UnitBase` had the full pacing machinery (`StepRequest`, `SetHoldRun`,
`_M_StepGate`) but no shipped Unit ever declared support. `FB_PneumaticPressUnit` now advertises
SINGLE_STEP and HOLD_TO_RUN and passes every motion boundary in AUTO/HOME/CHANGEOVER through
`_M_StepGate(Steppable := TRUE)` — the step record is set first so the HMI shows where the sequence
is paused. Settle/dwell timers are process steps and are deliberately not gated. CONTINUOUS is the
default; existing tests are unaffected because the gate returns TRUE there.

**Traceability (§3.16).** The contract existed as types only (`I_PartCarrier`, `ST_PartContext`,
reasons 2020–2023) with no implementation, no Unit wiring, and no lifecycle events. Added: the four
`EVENT_PART_*` reason codes (2024–2027, MESSAGE ring entries via the instant come+gone pattern);
`FB_LocalPartCarrier` in `Connectivity/` (BY_POSITION serials from a configured prefix, bounded
produced-results ring — joins the local provider family); `FB_UnitBase` publishes
`Part : ST_PartContext` and gains `SetPartCarrier` plus the protected helpers `_M_PartReceived`,
`_M_PartStarted`, `_M_PartRecord`, `_M_PartProcessed`, `_M_PartAborted`. ERROR entry raises
PROCESSING_ABORTED automatically next to the §8.3 fault capture. The press AUTO chain raises all
four events and records the applied dwell; `MAIN` injects the carrier. With no carrier injected
every helper is a no-op, so traceability stays a selectable feature (§3.9). `FB_PartTrace_Tests`
proves the carrier scan-exactly. The HMI part facet (§3.16.4) is a follow-up — the data is now
published for the generic mapper.

**Rationalization (§8.9) and access (§7.7).** The press registers operator-action/consequence
metadata for its main reasons (interlock, air pressure, recipe, cylinder position timeouts) and a
commissioning user table (operator/tech/admin). `FB_LocalAccessProvider.Register` is now idempotent
by user name — the table is PERSISTENT, so per-boot registration previously duplicated entries.

Deliberately NOT added: CAPABILITY/ADJUSTMENT modes (§3.17 — no press process behind them yet),
signal tower mapping (§8.13 — the training station has no tower and the HMI has no facet), and a
scripted vision/reader child (§3.15.1a — worthwhile, but it needs its own review of the AUTO
chain's quality path: NOK counting, REWORK routing, and the §3.16 verdict source).

## 49. Nexeed reference comparison: sub-sequence extraction and §4.2 folders (2026-07-16)

A Bosch Nexeed reference export (`NexeedReferenceOnly/REF1_Plc.xml`, ~140k lines) was reviewed for
code grouping and distribution. Its architecture maps almost one-to-one onto Fraktal contracts
(the map is recorded in `AGENTS.md`), which validated two things Fraktal already prescribes and
exposed two places the reference implementation did not practice them.

**Adopted 1 — shared sub-sequences (Nexeed `SqS_*` ≈ new `_M_Seq<Name>` methods).** The press
triplicated the ram-up→door-open→slide-outside motion chain across HOME and CHANGEOVER. It is now
ONE reviewable `_M_SeqEstablishLoadPosition(BaseStepNo)` sub-sequence with a private `_seqStep`,
called from both mode chains; the `BaseStepNo` window keeps per-mode step identity for the §6.9 walk
and the §8.11.4 profiler, and the changeover's "repeat position" decision resets the sub-step. The
HOME/CHANGEOVER step labels merged into shared `project.step.pressSafePosition*` keys. Behavior,
scan counts (±1), and the press suite's assertions are unchanged.

**Adopted 2 — §4.2 folder tree in the press application.** The demo was flat; Nexeed's per-location
folders are exactly the spec's instance-tree layout. The project now ships `00_System/` (MAIN, raw
I/O + safety GVLs, hardware driver, domain coordinator, output authority, sim plant) and
`01_PneumaticPress/` (recipe catalog, approved I/O catalog, fieldbus publication GVL); the plcproj
includes were repointed. Library projects keep their artifact-type folders — §4.2 governs
applications, where the instance tree exists.

**Noted, not adopted:** Nexeed's `Unit`+`Extension` pairs and `*Addon` plugins are composition-over-
inheritance seams; Fraktal deliberately uses base-class inheritance + §3.14 hooks + `I_EventSink`
(§2.2 single-sourced lifecycle) — no change. Nexeed models TWO workpiece contexts per station
(`...Wp1/Wp2` part-event addons); Fraktal's Unit publishes one `Part : ST_PartContext`. Multi-
workpiece stations are recorded as an open Part I §3.16 consideration, not silently bolted on.

## 50. Native OPC UA online-change resilience (2026-07-16)

The native client did not survive a TwinCAT PLC online change. Two gaps, both in
`fraktal_opcua_bridge.cpp`:

The discovery cache was permanent — `discoveryComplete` was set once after the
first browse and never invalidated except on a full connect/disconnect. So an
online change that added/removed/renamed symbols or shifted NodeIds was never
re-read: new symbols stayed invisible, removed ones lingered, and writes could
land on stale NodeIds. Reads of gone NodeIds were silently dropped (filtered on
`status != GOOD`), hiding the structural change.

There was also no reconnect path. A PLC online change usually reloads the TF6100
namespace and tears the OPC UA session down, and open62541 only auto-reconnects
when its event loop is pumped — this client is driven by explicit service calls.
So a dropped session left the HMI in `STALE`/`DOWN` indefinitely.

Fix (fully native; the Dart repository already marks link `STALE`/`DOWN` on
snapshot failure and returns to `LIVE` when snapshots succeed again, so no Dart
change was needed): `connect` now caches the endpoint/credentials; a `reconnect`
helper re-establishes the session with them and always clears the NodeId map;
`ensureSession` checks the live `UA_Client_getState` (connect status + activated
session) before every snapshot and reconnects when it degraded — making session
loss transparent. Reads count NodeIds that no longer resolve
(`BadNodeIdUnknown`/`BadNodeIdInvalid`); a surge (>=20% of cached variables)
invalidates the cache so the next snapshot re-browses the fresh structure. Any
service-level read failure reconnects and returns no document rather than a
stale/empty tree. Writes during the reconnect window are rejected, not queued
(§14); reconnect attempts are self-throttled by the connect timeout and the
shared in-flight refresh. `OPCUA_TRANSPORT.md` documents the contract.

## 51. Mode-change default is immediate abort, not graceful (§3.14.4) (2026-07-16)

`Unit_mode_change_is_estop_by_default` was the last red gate (64/65). Root cause: `_M_InitModePolicy`
defaulted `E_ModeSwitchStyle` to GRACEFUL (loop default and AUTO), so a mode change requested while a
sequence ran set `_stopReq` and waited for the cycle to finish. A stalled cycle (the probe waiting on
SimA/SimB) never finishes, so the Unit stayed BUSY and the mode never committed — the opposite of the
test's premise and of spec §3.14.4: "By framework default, a mode change performs an immediate software
abort." GRACEFUL completion is the opt-in (a Unit overrides OnModeExit to stop-after-cycle, or station
config sets Style := GRACEFUL for a mode).

Fix: the framework default Style is now IMMEDIATE for every mode (the OnCyclic mode block then calls
OnAbort on a BUSY mode change, completing the abort→Execute-drop reset→commit sequence in three scans).
Shield defaults are unchanged (CONFIRM, with CHANGEOVER/CALIBRATION BLOCKED_WHILE_RUNNING and
HOME/MANUAL INTERRUPTIBLE). No test or Unit opted into GRACEFUL, so nothing else moved. This is purely
a framework-default alignment to the spec; a station that wants finish-before-switch still gets it via
ModePolicy station config (§3.8a) or an OnModeExit override.

## 52. §8.11 cycle-time capture completed + HMI cycle-time analysis charts (2026-07-16)

Audit verdict: §8.11.4(a)/(b)/(e)/(f) were fully implemented (command timing in the module base,
the step-fed profiler with time classes, fixed arrays, Starved/Blocked derivation); the HMI had a
waterfall and step Pareto. Missing: §8.11.1 throughput markers, §8.11.2 verdict-driven counts and
ReworkCount, §8.11.3 machine-state classification, §8.11.4(c) guard-vs-actual and command-timing
drill-through in the HMI, §8.11.4(d) degradation events, and any per-model ideal cycle in the press.

**Core.** `FB_CycleProfiler` now publishes `LastCycleTime`/`MinCycleTime` (§8.11.1) and a bounded
`History` ring of `ST_CycleSummary` (per-cycle work/wait-class totals — the data that EXPLAINS a
cycle-time increase), plus a WORK-time degradation watch: `BaselineWorkMs`/`DegradedBandPct` with a
one-shot `DegradedTrig` per excursion; `FB_UnitBase` turns the trigger into a Low maintenance event
(`CYCLE_TIME_DEGRADED`, §8.11.4(d)) via the new `_M_RaiseMaintenance`. `ST_StepTiming` carries the
step's declared `Expected` guard so the HMI can draw guard-vs-actual (§8.11.4(c)); `_M_SetStep`
forwards it. `FB_UnitBase` adds `ReworkCount`+`CountRework`, `NokReason`, and `MachineState`
(new `E_MachineState`, §8.11.3 classification each scan: DOWN > CHANGEOVER > BLOCKED/STARVED >
PRODUCING > STOPPED > IDLE). §8.11.2 counters now increment inside `_M_PartProcessed` from the part
verdict (single source; an NOK stores its first-out reason). The public Count* methods remain for
carrier-less applications.

**Press.** `ST_PneumaticPressParCfg` v2 adds `IdealCycleMs` (OEE Performance denominator, §8.5.1)
and `BaselineWorkMs`; `CommitRecipe` forwards both, so the references follow the model. The catalog
carries per-model design cycles (5.7–6.8 s). The AUTO finish step now counts through the part
verdict; direct `CountGood()` remains only as the no-carrier fallback.

**HMI (user-requested: extensive cycle-time cause analysis).** New `cycle_trend_view.dart`:
`CycleTrendView` — stacked per-cycle columns split by time class with the MinCycleTime dashed
reference, hover/tap tooltip, dimming, and a legend (a grown green share = the process slowed; a
grown wait share NAMES the external cause), and `CommandTimingView` — the §8.11.4(c) drill-through
table (Count/Last/Min/Avg/Max + bar with Max marker) rendered per child module. The waterfall now
draws the Expected guard tick and outlines overruns in the error color. Unit chips add machine
state, rework, and last/best cycle time. The mapper projects `Profiler/LastCycle|StepStats|History|
LastCycleTime|MinCycleTime`, module `Timing/Rows`, `MachineState`, `ReworkCount`. The analysis
chain reads: trend (why did it move) -> waterfall (which step) -> Pareto (which step, over time) ->
command timing (which module command). Time-class palette re-validated with the dataviz six-checks
(blocked purple -> #AD1457 magenta, external teal -> #0097A7); identity is never color-alone (direct
labels + tables). `flutter analyze`/`flutter test` green; sim repository extended so the demo shows
a work-drift plus one starved excursion.

`FB_Timing_Tests` extends to the new markers/ring and the published Expected guard.

## 53. Ownership/sequence/release refinement from the Nexeed comparison (2026-07-16)

The deeper review of `NexeedReferenceOnly/REF1_Plc.xml` separated reusable architecture ideas from
vendor-specific implementation form. Part I §4.2 now makes ownership primary and distinguishes an
application instance tree from a reusable type library. §6.7 defines three chain roles—Unit mode,
module command, and owner-private sub-sequence—with one owner/step writer, an acyclic call graph, a
promotion rule to EM, and a requirement that private-chain progress stay in the caller's step record.
§7.2.1/§7.8 preserve condition provenance through common + mode/function-specific layering and keep
future step waits out of the Start frontier. The non-normative decision record is
`Specification/NEXEED_REFERENCE_INSIGHTS.md`.

One Core defect became visible under that rule: `ReleaseReportStart()` appended a concrete Unit's
`_M_AppendInterlocks`, while `Start()` independently checked only framework state. A Unit could thus
tell the HMI it was blocked and still start. `Start()` now performs the audited access check and then
consumes the report's authoritative `Released` value. Core conformance row T10 and
`FB_Release_Tests.Start_gate_matches_release_report` lock that equivalence.
`ST_ReleaseReason` also now carries the qualified owning `SourcePath`; `FB_PermIntlk`, framework
reasons, and directional cylinder releases populate it, and the HMI shows the owner plus numeric
reason. Aggregated same-text child conditions are therefore no longer ambiguous.

The press demonstrates the result. Its operating-air condition is an owner-local `FB_PermIntlk`
mode-entry record, appended by `_M_AppendInterlocks`; low air is both reported and enforced. Part
presence/two-hand remain AUTO step-100 waits. AUTO's duplicated return-to-load-position steps were
replaced by the same `_M_SeqEstablishLoadPosition` already used by HOME/CHANGEOVER, preserving the
230–280 step window and traceability record. Application engineering data is further grouped into
`01_PneumaticPress/Recipes` and `01_PneumaticPress/Io`. Published PLC instance names and OPC UA paths
did not change.

Deliberately not adopted: Nexeed Unit+Extension duplication, per-step wrappers, opaque summed release
booleans, direct raw-global coupling, PLC-authored HMI visibility, and ordinary-PLC safety
bridge/muting authority. Those conflict with Fraktal O1/O3/O7 and remain owned by base hooks, condition
records, the generic HMI, and certified safety respectively.

## 54. Compile-driven profiler ownership and TF6100 pointer exclusion (2026-07-16)

The pinned 4024 compiler rejected `Profiler.BaselineWorkMs := ...` in
`FB_PneumaticPressUnit.CommitRecipe`: `BaselineWorkMs` is a published output of the child
`FB_CycleProfiler`, not an assignable input. This is the same nested-FB ownership rule recorded in
Part II §3.3. `FB_CycleProfiler.M_SetBaselineWork(WorkMs)` now owns the mutation and rearms the
degradation excursion latch; the press recipe commit calls that API. The press TcUnit suite gives
the fast/slow records distinct baselines and asserts that each transactional model commit updates
the published profiler reference.

TF6100 also reported `RecipeCatalog.Provider._ptr` as unsupported `UXINT`. Skipping the pointer leaf
did not break discovery, but publishing provider storage was unnecessary and noisy. The provider
instance and its `PVOID` array now explicitly opt out with `OPC.UA.DA := 0`; neither is HMI contract
data. `TwinCAT_SystemInfoVarList._AppInfo.TComSrvPtr` is Beckhoff-owned system metadata and remains a
benign skipped leaf if the server scans that namespace. Part II §3.10 and the commissioning guides
now distinguish an application-owned exclusion defect from that system diagnostic.

## 55. Pinned `0.1.0.1` build set after unresolved Modules cascade (2026-07-16)

A dependent-build report contained more than 500 errors in `Fraktal_Press_Demo` and
`Fraktal_Tests`, but no error row owned by `Fraktal_Core` or `Fraktal_Modules`. The first errors were
unknown `FB_PneumaticPressUnit`, `FB_CylinderCM`, `ST_CylinderHal`, and every other Modules-owned
type; all invalid members/calls and even "type X is not equal to type X" were downstream compiler
recovery noise. The applications were resolving a missing/stale Modules artifact through `*`.

All five projects now identify the source set as `0.1.0.1`. `Fraktal_Modules` pins
`Fraktal_Core, 0.1.0.1`; Demo, Press Demo, and Tests pin both Core and Modules `0.1.0.1`. This makes
the required install order explicit and prevents XAE from silently selecting an older local-library
revision. The recovery is: build/install Core, resolve/build/install Modules, reload application
placeholders, then build applications. No individual Press/Test POU change is justified until that
dependency gate is green.

This section records the then-current recovery. Section 58 supersedes the current pin for Modules
(`0.1.0.2`) and makes `FB_PressDemoUnit` application-owned rather than a Modules-owned type.

## 56. Runtime stack overflow: release reports changed to in-place fill (2026-07-16)

Activating `Fraktal_Tests` exposed a PLC task stack overflow. The first runtime fault named the Tests
application/`PlcTask`; TwinCAT's later PREOP→OP and ADS 1804 messages were fallout from the crashed
PLC server. The immediate regression was the T10 Start change: `Start()` held an
`ST_ReleaseReport`, called `ReleaseReportStart()` whose implementation held another report, and
received the roughly 12.5 KiB record by value. TwinCAT 4024 can materialize additional return and
assignment temporaries, exhausting a bounded task stack.

`ReleaseReportStart`, `ReleaseReportManual`, and `ReleaseReportAction` now fill caller-owned
`VAR_IN_OUT Report` storage and return only the `Released` Boolean. `Start()` builds directly into
the already-published `HmiResponse.Report`; the mailbox and TcUnit callers also use in-place fill.
This preserves the authoritative gate/report predicate and wire data while removing the large nested
stack copies. The TC3 binding and agent guide now prohibit large contract returns by value.

Separately, `Fraktal_Tests` is an executable validation application but not a deployable machine
application. It may run manually on an isolated test runtime or CI worker; Autostart Boot Project
shall remain disabled. If mistakenly booted, recover in Config mode and remove/disable the Tests boot
project before returning the actual machine application to Run.

## 57. Press mode chains converted from ST token ownership to native SFC+ST (2026-07-16)

The press already had explicit HOME, CHANGEOVER, and AUTO behavior, but all three mode tokens lived in
`CASE _step OF` ST chains. Core §5.5/§6.2/§6.8 permits that representation, yet names SFC as the
default/recommended representation for multi-step machine sequences. The reference application should
demonstrate the default, not only the permitted fallback.

`FB_PressDemoHomeSfc`, `FB_PressDemoChangeoverSfc`, and `FB_PressDemoAutoSfc` own native TwinCAT SFC tokens.
Their non-stored ST actions publish `ActiveStep`; `FB_PressDemoUnit._M_Sequence*` remains the ST
Fraktal action adapter that populates `_M_SetStep`/`_M_Await`, drives child PLCopen handshakes, records
traceability, and invokes inherited completion/fault handling. The Unit's `_step` now selects only the
base lifecycle reset/run phases, not individual production transitions. Each reset is asserted and the
chart is called once before `M_Run` clears `SFCReset`, avoiding a reset flag that is set and cleared
without ever being consumed by the SFC runtime.

The reused ram-up/door-open/slide-outside chain remains the single private ST
`_M_SeqEstablishLoadPosition` sub-sequence, invoked as one composite SFC step with a caller-supplied
step-number window. This preserves one implementation across HOME, CHANGEOVER, and AUTO while retaining
detailed HMI progress. `Fraktal_Press_Demo/01_PneumaticPress/Sequences/New-PressModeSfc.ps1`
deterministically regenerates the native TwinCAT
SFC XmlArchive files; static validation checks XML, archive IDs, step/action links, and project includes.
The next pinned-XAE build remains the authority for editor/compiler acceptance of the generated graphical
archives because this workstation does not have the TwinCAT XAE compiler installed.

## 58. Concrete Unit sequences and release policy moved to the application branch (2026-07-16)

The first SFC conversion incorrectly compiled the press Unit and its HOME/AUTO/CHANGEOVER charts into
`Fraktal_Modules`. That made station behavior look reusable and hid the normal project extension point.
The Nexeed reference and Core §4.2 both point to ownership-first application engineering instead.

`FB_PressDemoUnit`, its three native SFCs, their deterministic generator, and
`FB_PressDemoRelease` now live under `Fraktal_Press_Demo/01_PneumaticPress`. The Release component
contains the project cross-device collision rules, named mode-entry condition state, and Start/manual
report appenders. Reusable `FB_CylinderCM`, input, two-hand, pressure, and power-group mechanisms stay
in `Fraktal_Modules`; that library no longer compiles or exports the press Unit or its SFCs. The
aggregate test project links the deployed project sources rather than copying them.

Removing the application Unit from the reusable library is a breaking library-surface correction, so
`Fraktal_Modules` advances to `0.1.0.2`; application/test placeholders are pinned to that version.

## 59. Press physical XTI reconciled into declarative I/O links and HAL (2026-07-16)

The supplied `=000+S-A610-A1 (EtherCAT).xti` is preserved under the press application's
`00_System/Hardware` folder. It establishes the deployed order and names as EK1200-5000 coupler,
EL1809 inputs, EL2809 outputs, EL6001 RS232, and EL9011 end terminal. It also resolves the worksheet's
EL2810/EL2809 ambiguity: the installed output terminal is EL2809 and its channel 9 is Reserve.

Every one of the 23 active `GVL_PressIO` Boolean process-image symbols now carries a `TcLinkTo`
attribute with the exact XTI box, physical channel, and PDO-entry name. Wildcard `%I*`/`%Q*` storage
remains intentional; the declarative link, not a guessed byte offset, owns the physical association.
`FB_PressIoDriver` remains the sole process-image consumer and maps those raw values to the project HAL.
The fieldbus catalog now publishes all five EtherCAT boxes below the CX2030/master node and uses the
exact box/channel address for diagnostic joins. The EL6001 has no HAL consumer because no serial device
or protocol was supplied; inventing one would violate the project-HAL boundary.

The XTI contains System Manager hardware configuration, not PLC application configuration. A deployer
must import it under the XAE solution's I/O Devices tree, preserve the box names, build to resolve all
23 links, activate the configuration, and complete dry-I/O validation. The ordinary EL1809 E-stop and
two-hand signals remain diagnostic/function inputs only. The fail-closed `GVL_PressSafety` aliases still
require evaluated results from TwinSAFE or another validated safety system, and the two control-coil
outputs remain disabled until their electrical sequencing is independently confirmed. The application
version advances to `0.1.0.3` for this physical-deployment mapping.

## 60. Press SFC actions now own their actual step logic (2026-07-16)

Section 57's first SFC conversion made the chart the sole token owner but left every generated action as
only `ActiveStep := N`; `FB_PressDemoUnit._M_Sequence*` still selected and executed the whole chain through
`CASE ActiveStep OF`. That avoided two competing tokens but failed the more important reviewability intent
of the SFC default: an engineer opening a step could not see what that step actually did. This section
supersedes that distribution.

`FB_PressDemoHomeSfc`, `FB_PressDemoChangeoverSfc`, `FB_PressDemoAutoSfc`, and the shared
`FB_PressDemoLoadPositionSfc` now contain the real application behavior in each named action: Fraktal
step/condition records, child PLCopen command/wait,
timers, decisions, traceability/result work, and a step-local transition Boolean. Exit actions clear each
step's transition latch, preventing a completed predecessor from skipping a newly active step. The Unit's
three `_M_Sequence*` methods now contain only the inherited lifecycle's reset/run handshake and no
`ActiveStep` selector or production-state `CASE`.

The project-private `I_PressDemoSequenceHost` bridges only protected Unit services that a separate SFC POU
cannot call directly. The SFCs receive owner-bound references to the child FBs and contract records during
`Setup`, so their actions visibly issue the child commands without illegally writing through the parent's
published child output. Those aliases and the SFC instances opt out of TF6100 publication. The coherent
ram-up/door-open/slide-outside operation is now the shared `FB_PressDemoLoadPositionSfc`, invoked as an
explicit composite parent step. Its own named actions contain the three child command/wait pairs, and its
caller-supplied step-number window projects detailed progress through the normal Fraktal step record. No
project mode or shared motion chain remains an ST state machine; the generator deterministically emits the
complete step-owned SFC set.

Core §5.5/§6.8, Part II TC3 §3.5, the Nexeed insight note, the press documentation, and `AGENTS.md` now
state that a token-only SFC plus external `CASE ActiveStep` is not a conforming claimed SFC implementation.
The press application advances to `0.1.0.4`; the aggregate Tests project advances to `0.1.0.3` because it
links the changed application sequence interface and charts.

## 61. Core FB_SequenceBase: the provided step-chain base + shared transition result (2026-07-17)

Section 60 made every press SFC action own its real step logic, but each generated chart still carried
its own host-interface copy, eleven per-step transition Booleans, per-step exit actions, and one
`I_PressDemoSequenceHost` that existed only because the framework had no sequence base. The Nexeed
reference does this once in `OpconSfcChain` (`_retVal := OK` + `ExecuteUnit(...)`), and Part I §6.8(a)
already PROMISED a provided shared step-chain base. This section delivers it.

Core additions: `E_StepResult` (NONE/ADVANCE/JUMP1..3 — the Fraktal spelling of Nexeed's OK/JUMPx,
integrated with §6.10 branch rules), `I_SequenceHost` (the once-per-framework bridge to protected Unit
services; `FB_UnitBase` implements it, replacing the press-private interface verbatim, plus
`M_SequenceStopPending`/`M_SequenceStopNow`), and `FB_SequenceBase`: `M_Attach`, `M_Step` (step record +
ActiveStep mirror), `M_Await`, `M_Gate`, `M_MayIssue` (one-shot gated issue latch — the §6.1 issue/await
pair collapses into ONE reviewable step; the child's typed Command/Execute stays visible in the action),
`M_Delay` (declared process waits), part/decision/completion/fault forwards, and the shared
`_retVal : E_StepResult` transition with `M_ClearTransition()` as the single shared exit action.
Charts now declare zero transition variables and one transition expression
(`_retVal = E_StepResult.ADVANCE`); a completed predecessor cannot skip a fresh step because the exit
action clears the shared result (same guarantee §60's per-step Booleans provided, at 1/N the state).

Stop honesty fix: AUTO's between-cycles wait previously rode out a full phantom cycle when Stop arrived
while waiting for a part. The wait step now polls `M_StopPending()` and calls `M_StopNow()`, which
abandons the OPEN profiler cycle via the new `FB_CycleProfiler.CycleAbandon()` (a wait-only fragment
is not a production cycle — it would poison MinCycleTime and the trend) and completes the chain.

The press generator now emits charts that EXTEND the base: issue+await merged into single drive steps
(LoadPosition 7→4 steps, AUTO 17→12), the private host interface deleted from the project and the
aggregate tests, and the Unit's Setup passes `THIS^` as `I_SequenceHost`. Generator self-checks verify
`EXTENDS FB_SequenceBase`, genuine step logic, and the `M_ClearTransition` exit per step. Step numbers
keep their §6.5 spacing; step-name keys unchanged except the merged drive steps
(`pressRamUp`/`pressDoorOpen`/`pressSlideInside`/`pressDoorClose`/`pressRamDown`).

Declined from Nexeed, deliberately: raw `BinIo` access inside sequence actions (violates §10.2.1 —
Fraktal actions still drive children only through the §6.1 handshake), `OpconSetTimeout/CheckTimeout`
step pairs (Fraktal timeouts live in the module's ParCfg per §6.1, and stall detection is the §6.9
walk), and per-step `IndexInfoLine` enum juggling (the step record + condition records already name the
wait for the HMI, localized).

Fraktal_Core advances to 0.1.0.2 (new public base + interface + enum; UnitBase implements
I_SequenceHost). The press application and aggregate tests re-pin accordingly.

## 62. Aggregate test manifest moved to the PLC common ancestor (2026-07-17)

The `0.1.0.4` aggregate project linked the deployed Press Demo Unit, release evaluator, and four SFCs
from a sibling directory with raw `Compile Include="..\Fraktal_Press_Demo\..."` paths. Although each
entry supplied a valid virtual `Link`, TwinCAT XAE's **PLC → Add Existing Item** importer inspected the
raw path first, attempted to create a project-tree folder named `..`, and stopped with
"'..' is not a valid folder name." The XML was valid MSBuild but not importable by TwinCAT.

`Fraktal_Tests.plcproj` now lives at `FraktalCore/PLC/`, the nearest common ancestor of
`Fraktal_Tests/` and `Fraktal_Press_Demo/`. All 37 compiled objects use downward repository-relative
paths; the Press sources remain single-source links and are not copied into the test directory. The
nested `Fraktal_Tests/Fraktal_Tests.plcproj` is removed so there is only one selectable manifest.
The aggregate test application advances to `0.1.0.5`; no PLC runtime contract changed.

During the same import audit, `FB_SequenceBase.M_MayIssue` was found with a default-valued method input.
That optional-input syntax is a TwinCAT 3.1.4026+ feature and violates the pinned 4024 binding rule.
The default was removed; every generated press action already supplies `Steppable := TRUE` explicitly,
so behavior and the effective call contract are unchanged.

## 63. Generated SFC charts: arity + optional-input fixes; IecSfc is NOT a dependency (2026-07-17)

The first pinned-XAE compile of the externally generated press charts produced 254 primary
`Unknown type: 'SFCStepType'` messages followed by hundreds of `.x`/`._x`/`.t`/`._t`, assignment, and
transition-BOOL errors. An interim change (from an external agent) added an
`IecSfc, 3.4.2.0 (System)` placeholder to the Press Demo and aggregate Tests manifests on the theory
that the SFC system library was missing. **That diagnosis was wrong and the reference was removed.**
Native TwinCAT SFC support is provided by the compiler for any POU whose implementation is an `<SFC>`
body; it needs no `.plcproj` library reference. The `IecSfc` string that appears in a generated chart
is the SFC `ObjectProperties` **title block** every chart carries — object structure, not a project
dependency. An `SFCStepType` cascade on a generated chart means that POU's SFC
`ObjectProperties`/`XmlArchive` block is malformed (regenerate it); it is not a missing library. The SFC
layer is Fraktal Core's own `FB_SequenceBase` plus native chart bodies — there is no external SFC base.

Two errors in that build were real and their fixes are kept:
- `FB_PressDemoLoadPositionSfc.M_Reset` requires `BaseStepNo`, while the shared generated restart branch
  called it with no inputs. The generator now preserves and passes `_baseStepNo` on that branch; the
  other three charts keep their zero-input reset.
- `FB_SequenceBase.M_MayIssue` had a default-valued method input (`Steppable : BOOL := TRUE`). Optional
  method inputs are a TwinCAT 3.1.4026+ feature and violate the pinned 4024 binding rule. The default was
  removed; every generated press action already passes `Steppable := TRUE` explicitly, so the call
  contract is unchanged.

The same build reported duplicate GUID warnings for Core interface methods. Those arise when a solution
loads the Core source project while an application in that solution also consumes the installed Core
library. Source object GUIDs shall not be randomized to hide the duplicate. Build/install libraries in
a library solution, then unload/remove those source projects (or use a separate application solution)
before compiling consumers.

## 64. Press sequences converted from unparseable native-SFC XML to the ST skeleton (2026-07-18)

Sections 57-63 rebuilt the press mode sequences as "native TwinCAT SFC" via a PowerShell generator that
hand-emitted the SFC `XmlArchive`. That was the wrong call: TwinCAT's SFC serialization is a proprietary
format whose step/transition WIRING (connection graph + layout) the compiler needs to synthesize the
implicit `SFCStepType` and its `.x`/`._x`/`.t` members. The generator emitted step and transition
ELEMENTS but zero connection elements, so a pinned-XAE build produced hundreds of
`Unknown type: 'SFCStepType'` + `'Nxxx._t' is no valid assignment target` errors. This is not fixable by
editing the blob (the format is not documented or reliably hand-authorable), and it was never an `IecSfc`
library problem (see §63 — that reference was a wrong diagnosis and was removed).

Resolution, per Core §6.8 (an ST `CASE StepNo OF` skeleton is a first-class equivalent to native SFC with
identical diagnostics): the four sequences are now plain ST on the SAME `FB_SequenceBase`. Everything the
base contributes is retained — `M_Step`, `M_Await`, `M_Gate`, one-shot `M_MayIssue`, `M_Delay`, the
part/decision/completion forwards, `I_SequenceHost` (still implemented once in `FB_UnitBase`), the shared
`_retVal : E_StepResult`, `CycleAbandon`, and the between-cycles `M_StopNow`. Two base additions make the
pure-ST body work: the `_step` token moved into the base, and `M_Advance(OnAdvance, OnJump1..3)` commits
`_retVal` at the end of each `CASE` branch — advancing to the mapped step and clearing the step-scoped
latches (the guarantee the SFC exit action gave). The generator, the four `*Sfc.TcPOU` files, and the
`SFCReset` two-scan reset handshake are gone; the files are `FB_PressDemoAuto/Home/Changeover/LoadPosition`
and the Unit adapters do a plain reset-then-run. HOME/CHANGEOVER Setup signatures narrowed to the children
they actually use. `M_MayIssue`'s `Steppable` input carries no default (4024 rule). Both manifests and all
four POUs parse; every `M_*` call resolves against the base.

Native graphical SFC remains a permitted §6.8 option, but only when drawn in the XAE SFC editor — a
machine-generated chart is prohibited. Part I §6.8, Part II TC3 §3.5, AGENTS.md, and the press README now
say the shipped reference is the ST skeleton on `FB_SequenceBase`, not a generated chart.
