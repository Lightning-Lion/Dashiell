# log-gen

Build-time event catalog + call-site generator for ArkTS logs.
It is shared verbatim with the watch client repo; only `--app` (and each repo's
`LogAppConfig.ets`) differs.

```bash
node tools/log-gen/cli.mjs --write --app Dashiell   # scan call sites, emit LogEvents.generated.ets
node tools/log-gen/cli.mjs --check --app Dashiell   # verify generated file is fresh
node --test tools/log-gen/test/generator.test.mjs
```

## Pipeline

```text
logging/events.json
  → schema.mjs       strict validation (bilingual text, unique names, field types)
  → scanner.mjs      mask comments/strings; find LogEvents.<name>( with line/column
  → scope.mjs        brace-aware class/struct + method attribution
  → emit.mjs         deterministic Writer → ArkTS
  → LogEvents.generated.ets
```

## Rules

- Exactly one literal `LogEvents.<name>(` call per event.
- Comments, strings and `foo.LogEvents.x()` are ignored.
- `class`/`method` overrides in the event catalog handle unusual formatting.
- Output is deterministic; the header records Events/Sites SHA-256.
- A failed generation writes nothing (validate first, then temp+rename).
- `--check` exits non-zero when the output differs from the current sources.

## Options

- `--events PATH` — event catalog (default `logging/events.json`)
- `--src DIR` — ArkTS source root (default `entry/src/main/ets`)
- `--out FILE` — generated file (default `entry/src/main/ets/utils/log/LogEvents.generated.ets`)
- `--app NAME` — app name in the generated header (default: repo directory name)
- `--write` / `--check` — regenerate or verify only

## Shared files

These files must stay byte-identical with the watch client repo:

- `tools/log-gen/{cli,schema,scanner,scope,emit}.mjs`, `test/generator.test.mjs`, `README.md`
- `entry/src/main/ets/utils/log/{LogCore,LogFormatter,LogMask,LogErrorCapture,LogSourceLocator,Logger}.ets`

Allowed per-repo differences: `LogAppConfig.ets`, `logging/events.json`,
`LogEvents.generated.ets`, and the `Logger.init` call in `EntryAbility`.

## Why Node instead of Rust

The generator runs on every Hvigor build so line numbers stay correct after any edit.
Node is already part of the HarmonyOS toolchain; a Rust dependency would make the
Hvigor PreBuild step fail on machines without Cargo. The architecture (descriptor →
node tree → writer, SHA header, `--check`, tests) follows Dashiell `tools/json-gen`.
