# Keeping WireDash current

`main` is the integration branch and GitHub default branch. It contains the
accepted Android Auto implementation and the existing WireDash features.
The latest upstream import is ZigDash 3.2.0, commit
`a1da985` from <https://github.com/giladtamam/zigdash>.

## Feature work

Start short-lived `feat/<name>` branches from current `main`. Merge reviewed,
tested changes back into `main`. Historical branches, including those attached
to local worktrees, can stay as references. Check their contents before deleting
them; some predate the original integration and have different commit IDs for
changes already present in `main`.

## Importing upstream

Keep `origin` pointed at `VadimSurpin/WireDash` and `upstream` pointed at
`giladtamam/zigdash`. Enable Git's recorded conflict resolutions locally:

```sh
git config rerere.enabled true
git fetch origin
git fetch upstream
git switch main
git pull --ff-only origin main
git switch -c sync/upstream-YYYY-MM-DD
git merge --no-ff --no-commit upstream/main
```

Resolve conflicts on the sync branch and inspect any resolutions reused by
`rerere`. Preserve the upstream parent: complete this as a normal merge, and
merge the sync PR with **Create a merge commit**. Squashing or rebasing an
upstream import loses the ancestry that tells Git which upstream changes have
already been incorporated. Never force-push shared `main`.

Keep the fork's application ID and Kotlin package `pro.surpin.wiredash`, Dart
package `wiredash`, branding, telemetry removal, Wiren Board discovery and
controls, embedded WireGuard, background reconnection, and Android Auto support.
The registered Home Assistant OAuth callback remains `zigdash://auth`; local
home invitations use `wiredash://home/join`. MQTT protocol namespaces and stored
settings need compatibility review before renaming.

Merge localization source files by key, preserving fork strings and newly
added upstream translations. Regenerate generated Dart files rather than
resolving generated output by hand:

```sh
tool/flutter pub get
tool/flutter gen-l10n
tool/flutter pub run build_runner build --delete-conflicting-outputs
tool/flutter analyze
tool/flutter test
```

See the README for the native JavaScript engine needed by Linux tests. When
upstream intentionally changes screens, regenerate the affected golden images
and inspect them before committing. Run the Go and Android Auto native tests
through the `Check` workflow as well. The workflow checks `sync/**` branches and
PRs, including an Android build. Keep private signing keys local.

Commit the resolved merge, push the sync branch and open a PR against `main`.
After checks pass, merge normally, update local `main` with `--ff-only`, and
record the new imported upstream version and commit here and in the README.
WireDash's version and Android build number advance independently of upstream.
