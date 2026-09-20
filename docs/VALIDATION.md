# Initial import validation

Checked on 2026-09-19.

## Completed

- Imported the existing `analog_power_dial_edge130plus` project from Thomas's local `analog_power_dial_edge130plus_ready` folder.
- SHA-256 comparison confirmed all ten imported app, resource, configuration, helper, and preview files match their originals exactly.
- Compiled the repository copy with Connect IQ SDK **9.2.0**, SDK build `2026-06-09-92a1605b2`, for **edge130plus**. Result: **BUILD SUCCESSFUL**.
- Used the original signing key by local path; did not copy the key into the repository or include it in Git history.
- Confirmed Git ignores the signing key filename and compiled output.
- Left the original source folder and its existing compiled app untouched.

## Pending runtime review

No simulator session or physical-device test was performed for this import. Before a release, record the device/firmware or simulator version and verify:

- [ ] Full gauge in a field at least 220 pixels tall; labels and watts are readable.
- [ ] Compact gauge in smaller supported field layouts; no unacceptable clipping.
- [ ] Readings at 0, 100, 400, and 800 W place the needle appropriately.
- [ ] Readings above 800 W keep the needle within the scale and retain the digital value.
- [ ] Abrupt power changes produce the expected damped movement.
- [ ] Missing power shows `--`, needle decays, and power reconnection restores readings.
- [ ] Sideloaded app appears as Analog Power Dial and runs during a cycling activity.

## Rev-counter and AI fuel change

- [ ] Full-screen dial labels 0–200% FTP without clipping on Edge 130 Plus.
- [ ] Check-engine lamp is outlined at or below FTP and filled above FTP.
- [ ] Fuel starts at 100%, falls with accumulated mechanical work, and clamps at 0%.
- [ ] Fuel shows 20 segments plus exact remaining percentage and kJ.
- [ ] HR deviation, power percentage, exertion score, and short feedback update once per second.
- [ ] Garmin Connect Mobile changes to FTP, fuel, and HR profile values appear in the running field.
- [ ] Garmin Connect OAuth consent backfills the complete cycling activity history.
- [ ] Each sync increments the learned profile revision and counts every eligible ride.
- [ ] Companion calibration returns bounded power/HR values without exposing either provider token.

The import preserves existing behaviour, including any pre-existing limitations. Compilation alone is not a runtime test. There are no automated unit tests or CI checks configured in this initial repository.
