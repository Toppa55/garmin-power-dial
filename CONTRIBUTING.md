# Working on Power Dial

Keep each pull request focused on one clear change. Preserve the application ID and signing key continuity unless an intentional migration is being reviewed.

## Everyday workflow

After the initial import pull request has been merged:

```sh
git switch main
git pull --ff-only
git switch -c feature/describe-your-change
```

A **branch** gives the change its own history while `main` stays at the reviewed version. Choose a descriptive branch name, such as `feature/adjust-power-scale`.

Make your change, compile for `edge130plus`, and check the relevant cases in [the validation checklist](docs/VALIDATION.md). Inspect exactly what will be saved:

```sh
git status
git diff
git add source/AnalogPowerView.mc
git diff --cached
git commit -m "feat: describe the user-visible change"
git push -u origin feature/describe-your-change
```

A **commit** is a local save point with a useful explanation. A **push** uploads those commits to GitHub; it does not merge them into `main`. Stage the specific files you intended to change, and check that generated builds and signing keys are absent.

Open a **pull request** on GitHub from the feature branch into `main`. Explain the problem, changed behaviour, and checks performed. Mark untested cases honestly. Inspect AI-generated changes just as carefully as other changes.

The reviewer checks the diff and validation evidence, requests fixes where needed, and merges when satisfied. For a solo project, Thomas can perform this review himself; another reviewer can provide an additional independent check. This is a documented workflow, not an enforced branch protection rule.

After merging, switch back to `main` and pull again. Deploying to the Garmin is a separate deliberate action; merging a PR does not install anything on the device.

## Commit messages

- `feat: ...` for new behaviour.
- `fix: ...` for a correction.
- `docs: ...` for documentation.
- `chore: ...` for repository maintenance.

Avoid unrelated refactors in a behaviour change. Keep private signing keys and generated output out of all commits.
