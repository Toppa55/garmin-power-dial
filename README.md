# Garmin Power Dial

A monochrome rev-counter cycling power dashboard for the **Garmin Edge 130 Plus**, written in Monkey C for Garmin Connect IQ.

This repository preserves Thomas's existing app source, application ID, resources, and Windows build/install helpers. The initial import changes project documentation and repository housekeeping, not the app's behaviour.

![Original design preview](PREVIEW.png)

*Original project preview; not a screenshot of a validation run.*

## Features

- 240-degree nonlinear rev-counter dial from 0–400% of FTP, with extra space around the most useful riding range.
- Damped needle with a large live watt readout and a marked FTP redline.
- Check-engine-style warning lamp that fills when live power exceeds FTP.
- Twenty-segment hard-effort reserve that drains above FTP and gradually recovers below FTP.
- Live HR-versus-power comparison, 0–100 exertion score, and short cues such as `HOLD`, `EASE OFF`, `HR DRIFT`, and `FUEL LOW`.
- FTP, fuel, and heart-rate model settings editable through Garmin Connect Mobile.
- Secure companion service that learns a cumulative rider profile from the complete Garmin Connect activity history through OAuth 2.0.
- Live numerical coaching from power, HR, cadence, temperature, reserve, sleep, and night-shift context, with occasional AI cues on meaningful changes.
- Local desktop dashboard for schedule, recovery context, learned profile, and AI training advice.
- Background phone-message receiver for compact live targets, risk, confidence, and cues on the Edge.
- Compact watt and fuel display for shorter data-field layouts.

## Project layout

```text
source/                   App entry point and gauge rendering
resources/                App name and launcher icon
backend/                  Secure OpenAI-powered calibration service
manifest.xml              App identity, Edge 130 Plus target, minimum API 3.2.0
monkey.jungle              Connect IQ build configuration
BUILD_AND_INSTALL.cmd     Windows launcher
BUILD_AND_INSTALL.ps1     Existing compiler discovery and USB install helper
PREVIEW.png               Original design preview
docs/VALIDATION.md         Import checks and device review checklist
docs/AI_COMPANION.md       Secure AI architecture and local setup
.github/                  Pull request template
```

## Build

Install the [Garmin Connect IQ SDK](https://developer.garmin.com/connect-iq/sdk/), its required Java runtime, and the **Edge 130 Plus** device files using SDK Manager. Make the SDK's `bin` directory available on your command path, or use the compiler's full path.

You also need a local developer signing key. **The key is deliberately not stored in Git.** The build helper checks `GARMIN_DEVELOPER_KEY`, `developer_key.der` in the project root, and the local `Documents/Garmin Connect IQ/Keys/garmin-power-dial-developer-key.der` path. Keep the same key for update continuity, with a secure backup outside the repository. Do not commit keys or send them in pull requests.

From the project root, in PowerShell:

```powershell
New-Item -ItemType Directory -Force build | Out-Null
monkeyc -d edge130plus -f monkey.jungle -o build/AnalogPowerDial.prg -y "C:\path\to\developer_key.der"
```

This builds the app without installing it. Output goes into the ignored `build/` folder.

## Install on the device

For the existing one-click Windows workflow, place your signing key at `developer_key.der` in the project root (ignored by Git), connect the Edge by USB, and run `BUILD_AND_INSTALL.cmd`.

The helper builds the app and copies it to the first detected drive containing `GARMIN/APPS`, replacing an existing `AnalogPowerDial.prg` there. Connect only the intended Garmin device. If no device is found, it leaves the compiled file in `build/` for manual copying.

After copying, safely eject/disconnect the Edge and add **Analog Power Dial** as a Connect IQ field on a cycling data screen. Use a tall field layout to see the full dial. Power readings require an appropriate power source supplying activity power data.

## Making changes

Use **branch → change → commit → push → pull request → review → merge**. See [CONTRIBUTING.md](CONTRIBUTING.md) for commands and what each step means. The first import is proposed on `feature/import-power-dial`; `main` initially contains only the repository's starting commit until that pull request is merged.

## Validation and scope

See [validation notes](docs/VALIDATION.md) for actual checks and the remaining simulator/device checklist. A successful compiler run does not establish runtime or hardware correctness. There is no automated CI build configured yet.

Only the Edge 130 Plus is declared in the manifest. No other Garmin devices are claimed to be supported. No open-source licence has been selected; repository visibility does not grant reuse rights.

## AI calibration

The OpenAI API key stays in the companion backend and is never included in the Garmin app or Git history. Garmin Connect supplies completed ride history to the service after OAuth consent; the service aggregates every ride and updates a versioned rider profile. See [AI companion architecture](docs/AI_COMPANION.md) for the data flow and setup. The dashboard applies that learned profile offline to compare live HR and power every second.
