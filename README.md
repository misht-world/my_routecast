# RouteCast

**Send a walking / cycling route from [Organic Maps](https://organicmaps.app) to a
Garmin Instinct 3 and follow it on-wrist** — a heading-up route line, a compass bearing
pointer, single-buzz turn cues and off-route alerts. Fully offline, no cloud, no account.

![platform](https://img.shields.io/badge/watch-Garmin%20Instinct%203-black)
![companion](https://img.shields.io/badge/phone-Android-3ddc84)
![offline](https://img.shields.io/badge/network-none%20(offline)-informational)
![status](https://img.shields.io/badge/status-validation%20v0.4.2-orange)

Current development version: **0.4.2**, protocol **v1**. See [CHANGELOG.md](CHANGELOG.md)
for version history, [VERSIONING.md](VERSIONING.md) for release rules, and
[RELIABILITY.md](RELIABILITY.md) for verified fixes and remaining reliability risks.

---

## Why this exists

The Instinct 3 has **no base map and no way to import a route without Garmin's own
ecosystem**. Organic Maps can *Share* a route as GPX, but the only Garmin path it offers is
"Garmin Explore", which needs a manual cloud sync. RouteCast closes that gap: share the GPX
to the phone app and it flies straight to the watch over Bluetooth, where the watch draws the
line itself — no base map, no native navigation, no internet.

## Features

- **One-tap share → over-the-air transfer.** Share a GPX from Organic Maps; the companion
  auto-sends it to the watch (a manual *Send* button stays as a fallback).
- **Heading-up map.** The route rotates to your travel direction — GPS course while moving,
  GPS-corrected compass while standing still, smoothed so it doesn't sway.
- **Pseudo turn-by-turn.** Maneuvers are detected on the phone; the watch buzzes **once, at
  the turn** (battery-friendly) and always shows a bearing pointer in the sub-screen.
- **Off-route alert** with a time hysteresis so GPS jitter doesn't false-trigger.
- **Overview + progress + arrival** screens; zoom, pause and finish controls.
- **Privacy by design.** No network calls, no analytics, no telemetry. Nothing leaves the
  phone-to-watch Bluetooth link.

## How it works

```
Organic Maps ──GPX──▶  Android companion  ──BLE via Garmin Connect Mobile──▶  Watch app
                       parse → decimate                (Connect IQ Mobile SDK)   render line
                       → detect maneuvers                                        + pseudo-TBT
                       → chunk + stop-and-wait
```

Connect IQ messages are small, so the route is **decimated (Douglas–Peucker)** and sent in
**chunks with stop-and-wait acks**. Coordinates travel as integer microdegrees (`deg × 1e6`)
as deltas between points. See [protocol.md](protocol.md) for the wire format.

## Install (pre-built)

Grab the latest artifacts from **[Releases](../../releases)**:

| File | Where it goes |
|------|---------------|
| `routecast-watch-instinct3-*.prg` | Copy to `GARMIN\APPS\` on the watch (USB mass-storage), then **safely eject** |
| `routecast-android-hw-*.apk` | `adb install -r <file>.apk` (or open on the phone) |

Requirements: Garmin Connect Mobile installed and the watch paired.

## Usage

1. **Open the RouteCast app on the watch** (Connect IQ can't wake a watch app from the phone —
   this step is deliberate; see [SPEC.md](SPEC.md)).
2. In Organic Maps: build a route → **Share → GPX → RouteCast**.
3. The route transfers automatically and draws on the watch. Walk the line; the pointer shows
   the bearing, and you get one short buzz at each turn.

## Build from source

**Watch (Connect IQ / Monkey C)**
```bash
monkeyc -d instinct3solar45mm -f watch/monkey.jungle -o watch/bin/my_routecast.prg -y <your-dev-key>.der
```
Use VS Code + the Garmin **Monkey C** extension ("Build for Device") for day-to-day work. The
device id lives in `<sdk>/bin/devices.xml`; the app UUID's single source of truth is
`watch/manifest.xml`.

**Android companion (Kotlin / Gradle)**
```bash
cd android
./gradlew :app:assembleHwDebug     # hw flavor = WIRELESS (real watch via GCM)
```
The `sim` flavor uses a TETHERED connection for the Connect IQ simulator.

## Testing

Development follows a **simulator-first** gate ladder (see [testing.md](testing.md)):

1. **Gate 1** — Android logic unit tests (parse / decimate / maneuvers / protocol) on the JVM.
2. **Gate 2** — watch assembly + rendering in the Connect IQ simulator.
3. **Gate 3** — end-to-end transfer.
4. **Gate 4** — real hardware, only for what the simulator can't reproduce.

```bash
cd android && ./gradlew :app:testSimDebugUnitTest      # Gate 1
```

## Design constraints (intentional)

- **Organic Maps GPX only** — no Google Maps, no online routing.
- **Transfer via Connect IQ Mobile SDK over Garmin Connect Mobile** — there is no open BLE
  protocol to push files to the watch directly.
- **Watch app is opened manually** before sharing — Connect IQ has no phone-triggered wake.
- **Offline-only** — no API keys, no required online dependencies.

## Repository layout

```
my_routecast/
├── README.md         # this file
├── SPEC.md           # full specification
├── protocol.md       # phone ↔ watch message schema
├── testing.md        # simulator-first gate ladder
├── android/          # Kotlin companion: Share target → parse → transfer
└── watch/            # Connect IQ app (Monkey C): receive → render line + pseudo-TBT
```
