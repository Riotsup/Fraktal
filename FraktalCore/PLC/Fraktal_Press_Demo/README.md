# Fraktal pneumatic press example

`Fraktal_Press_Demo` is an executable TwinCAT application. Add the `.plcproj` to
an XAE solution after installing the `Fraktal_Core` and `Fraktal_Modules`
libraries. Keep those source-library projects unloaded in the application solution.
The mode sequences are plain ST (`CASE _step OF` on `FB_SequenceBase`) — no SFC or
other library reference is needed. After pulling a manifest/reference change, close and reopen XAE before rebuilding.
It demonstrates one project-owned root `FB_PressDemoUnit` with seven
children: press, door and part-slide cylinder CMs, a two-hand status/start CM,
a pneumatic power-group CM, part-present input CM, and air-pressure monitor CM.

The supplied physical EtherCAT XTI is preserved under `00_System/Hardware` and
the CX2030 worksheet is implemented through `GVL_PressIO`. Import that XTI under
the XAE solution's I/O Devices tree without renaming its boxes; each of the 23
active PLC symbols uses `TcLinkTo` to bind its exact EL1809/EL2809 channel and
PDO-entry name. The topology also publishes the EK1200-5000, unused EL6001
RS232 terminal, and EL9011 end terminal. See
`Specification/CX2030_PRESS_IO_MAPPING.md` for the exact channel table,
feeder-position inversion, unresolved control-relay semantics, and fail-closed
physical commissioning procedure. Simulation remains enabled by default and
explicitly holds every mapped output off.

`GVL_PressFieldbus.Topology` publishes those same exact electrical tags,
terminal/channel addresses, localized descriptions, live values, and owning
module paths for the generic HMI. `FB_PressIoCatalog` owns the static approved
join; `FB_PressIoDriver` is the only POU that touches `GVL_PressIO`; reusable
`FB_IoTopologyPublisher` logic validates and correlates diagnostics. Cylinder
position faults attach the awaited sensor tag so the HMI highlights the
corresponding row instead of showing only a generic timeout.

The PLC project cannot activate a System Manager I/O tree by itself. After
importing the XTI, build once and verify that XAE reports every allocated
`GVL_PressIO` variable as linked before activating the configuration. Do not set
`UseSimulation := FALSE` until the dry-I/O, control-circuit, and independent
safety checks in the mapping specification pass.

## Safety boundary

This is virtual commissioning logic, not a certified safety application. In
`MAIN`, the `Safe*` aliases deliberately simulate outputs that a real project
must map from TwinSAFE/FSoE. TwinSAFE must implement and validate the normally
closed E-stop, two-hand simultaneity/anti-tie-down, guard monitoring, safety
valve, reset and restart behavior. The standard PLC only consumes those results,
withdraws functional requests, and explains status. In the simulation the safe
filter is the final output authority; ordinary Unit logic cannot overwrite it.

## Simulation sequence

1. Pulse local `SimControlOnButton`, or HMI data request
   `PneumaticPress.ReqControlOn`; wait for `Domain.ReadyForStart`.
2. Release both buttons once (`SimLeftButton=FALSE`, `SimRightButton=FALSE`) to arm.
3. Ensure `SimPartPresent=TRUE` and `SimAirPressureOk=TRUE`, then press both
   buttons (`TRUE`) to create the simulated safe two-hand edge.
4. The Unit retracts the ram, opens the door, moves the slide inside, closes the
   door, presses, dwells, retracts, opens, and returns the slide outside.
5. Release both buttons before the next cycle. Pulse
   `PneumaticPress.ReqControlOff` or pulse `SimControlOffButton` to remove the
   functional power request. Local Control Off wins over a simultaneous On edge.

Set `SimEStopNc=FALSE` to simulate operating the normally closed E-stop circuit.
No request is automatically replayed when it is restored.

## Changeover and modes

`FB_PressRecipeCatalog` registers `ALUMINUM` (300 ms dwell), `PLASTIC` (650 ms),
and `STEEL` (1200 ms), then publishes those identities for the generic HMI
selector. AUTO, HOME, and CHANGEOVER are ST `CASE _step OF` chains
(`FB_PressDemoAuto`, `FB_PressDemoHome`, `FB_PressDemoChangeover`)
under `01_PneumaticPress/Sequences`, together with the shared
`FB_PressDemoLoadPosition`. Every `_step` branch contains its actual
step record, child command/wait, timer/decision/result work, and transition
result (`_retVal` + `M_Advance`). All four extend Core `FB_SequenceBase`; `FB_UnitBase` provides
the single `I_SequenceHost` bridge and the shared transition result.
The Unit's `_M_Sequence*` methods only reset and run their chains. `_M_Dispatch`
is only their mode router. The HMI
changeover action selects CHANGEOVER, applies the recipe transaction, starts the
guided safe-position sequence, and presents its tooling/material confirmation.
AUTO, HOME, and CHANGEOVER embed one owner-private
`FB_PressDemoLoadPosition` for ram-up/door-open/slide-outside; its own step
branches contain those commands and waits, while each caller's step-number window
keeps diagnostics and timing mode-specific. MANUAL exposes the three
cylinder catalogs through the Unit's normal manual route. The same directional
interlocks apply in AUTO and MANUAL:

- door close requires the slide fully inside and not moving;
- either slide direction requires the door fully open and not moving;
- ram down requires door closed, slide inside, evaluated two-hand active, and
  pneumatic power feedback.

Project-specific collision rules and mode-entry permissives are visible in
`01_PneumaticPress/Release/FB_PressDemoRelease`. Its named live condition state
feeds the same authoritative Start/manual release reports the HMI displays, so
low air both blocks motion entry and appears in the release panel. Part presence and the two-hand edge are later AUTO waits,
shown through the live step record rather than used as blanket Start blockers.

The application branch is owner-grouped: its Unit, `Sequences`, `Release`,
`Recipes`, and `Io` stay together under `01_PneumaticPress`. Reusable device
behavior remains in `Fraktal_Modules`; `00_System` remains composition and
deployment infrastructure.

## Run styles, traceability, and access

The Unit supports SINGLE_STEP and HOLD_TO_RUN (§3.4.2): the HMI step toggle
paces AUTO/HOME/CHANGEOVER one commanded motion at a time; settle and dwell
timers run through. Part traceability (§3.16) is active through the shipped
`FB_LocalPartCarrier`: each AUTO cycle assigns a `PRESS-2026-<n>` serial,
raises the four canonical part events into the alarm/event ring, records the
applied dwell, and stores the OK result in the carrier's bounded ring; abort
or fault with a part present raises PROCESSING_ABORTED automatically.
Commissioning logins: `operator`/`1111`, `tech`/`2222`, `admin`/`9999`
(§7.7 — the shipped action policy remains fully open).

The expanded design, safety zoning boundary, recipe table, and commissioning
checklist are in `Specification/PNEUMATIC_PRESS_EXAMPLE.md`.
