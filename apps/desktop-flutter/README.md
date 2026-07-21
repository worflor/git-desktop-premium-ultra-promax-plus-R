# git_desktop

The Manifold desktop client (Flutter). This is the live app; `apps/*-ts` and the
Rust crates are legacy.

## Command-line bridge

`bin/manifold_cli.dart` is a CLI that talks to the running app over a loopback
socket, so scripts and agents can pull the same warm engine answers the UI shows
— `status`, `blast-radius`, `review`, and friends, with `--json` for piping.
Full command list, options, and protocol notes: [`docs/cli.md`](../../docs/cli.md).

```
dart compile exe bin/manifold_cli.dart -o manifold
manifold status
manifold blast-radius --files lib/backend/git.dart --json
```

## Flutter basics

New to Flutter? Start with the [online documentation](https://docs.flutter.dev/)
for tutorials, samples, and the API reference.
