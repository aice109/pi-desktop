# Documentation

[English](README.md) · [简体中文](README.zh-CN.md)

Central index for PiDesktop docs. **Load on demand** — open only the page your task needs.

> Agent rules and entry point live in [`../AGENTS.md`](../AGENTS.md).

| Doc | Contents | When to read |
| --- | --- | --- |
| [architecture.md](architecture.md) | Structure, modules, data flow, state | Adding a module / tracing calls |
| [design-system.md](design-system.md) | Liquid Glass, native components, color, type, motion | Writing or reviewing UI |
| [coding-conventions.md](coding-conventions.md) | Swift naming, concurrency, errors, file layout | Before writing code |
| [workflows.md](workflows.md) | Build, run, test, debug, commit, troubleshoot | Before building / committing |
| [pi-agent.md](pi-agent.md) | pi integration, event model, sessions, tool calls | Working on agent logic |
| [decisions/](decisions/README.md) | Architecture Decision Records (ADRs) | Major trade-offs / history |

Chinese mirrors use the `.zh-CN.md` suffix (e.g. `architecture.zh-CN.md`). English is the default;
keep both in sync.

## Documentation rules

- **Single source of truth**: describe knowledge once; link elsewhere.
- **Docs ship with code**: code changes that affect docs must update them in the same commit.
- **Layers**: root `README.md` for users; `AGENTS.md` for agent rules; `docs/` for details;
  `docs/decisions/` for decisions.
- **ADR triggers**: new third-party dependency, core framework change, data-model/persistence change,
  or any wide-reaching trade-off.
- Prefer extending an existing doc; register any new file in this table.
