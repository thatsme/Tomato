# Tomato v0.3 — Refactor Plan

## Status (as of 2026-04-13)

| Section | Status |
|---|---|
| §1 GraphLive split | In progress — canvas / modals / sidebar extracted; event handler split pending |
| §2 Store split | Done (`4f069d6`) |
| §3 Deploy split + SSH key auth | Done (`27fd2f7`) |
| §4 Local Nix-fragment validation | Pending |

`lib/tomato_web/live/graph_live.ex` is now ~905 lines (from ~1600 at the start of v0.3). The remaining bulk is ~50 `handle_event` clauses and a handful of helpers — the target of the handler split.

## Why

Giulia detected three god modules growing out of control during v0.2:

| Module | Functions | Complexity | Δ from v0.1 |
|---|---|---|---|
| `TomatoWeb.GraphLive` | 27 | 137 | +45 |
| `Tomato.Store` | 44 | 104 | +22 |
| `Tomato.Deploy` | 16 | 49 | +29 |

These need splitting before they become unmanageable.

---

## 1. Split `TomatoWeb.GraphLive`

**Status:** canvas components done (`c81d879`), modal components done (`22809c0`), sidebar components done (`f96e643`), event handler split pending.

Currently 27 handlers + 6 SVG components + 6 modal components in one file (~1600 lines).

### Target structure

```
lib/tomato_web/live/
  graph_live.ex                 # Mount, render, event routing only
  graph_live/
    canvas_components.ex        # graph_node, edge_line, oodn_node, minimap (SVG)
    sidebar_components.ex       # node_list, properties_panel, search
    modal_components.ex         # content_editor, oodn_editor, template_picker,
                                #   generated_output, graph_manager
    event_handlers/
      node_handlers.ex          # add/remove/update node, content edit
      edge_handlers.ex          # add/remove/reverse edge, connect modes
      machine_handlers.ex       # add/update machine, machine type
      oodn_handlers.ex          # add/update/remove/move OODN
      backend_handlers.ex       # toggle backend, generate, deploy
      history_handlers.ex       # undo/redo
      search_handlers.ex        # search nodes, navigate
      template_handlers.ex      # template picker, add from template
      graph_handlers.ex         # graph manager, new/load/save
```

### Approach

1. Extract SVG components into `CanvasComponents` (function components, no state)
2. Extract modal components into `ModalComponents`
3. Keep event handlers in the main LiveView but **delegate** to handler modules:

```elixir
def handle_event("add_node", params, socket) do
  Tomato.LiveView.Handlers.Node.add(params, socket)
end
```

4. Each handler module is a plain module returning `{:noreply, socket}` tuples
5. Tests for each handler in isolation

**Complexity target:** GraphLive < 30, no module > 60.

---

## 2. Split `Tomato.Store`

**Status:** done (`4f069d6`). Additionally, `bf44913` parameterized the store name and scoped the PubSub topic per instance to enable isolated test instances — see §7 below.

Currently 44 functions managing graph state, persistence, history, OODN, machines, gateways, graph files.

### Target structure

```
lib/tomato/store.ex                       # GenServer lifecycle, dispatch only
lib/tomato/store/
  state.ex                                # State struct + history operations
  mutations.ex                            # add_node, remove_node, etc. (pure)
  oodn.ex                                 # OODN-specific mutations
  machine.ex                              # add_machine, update_machine
  persistence.ex                          # JSON encode/decode, flush, load
  graph_files.ex                          # list, new, load, save_as, delete
```

### Approach

1. **Pure mutation modules** — `Store.Mutations.add_node(graph, sg_id, attrs)` returns `{:ok, new_graph, node}` or `{:error, ...}`. No GenServer state.
2. **Persistence module** — handles JSON encode/decode separate from state mgmt
3. **Store GenServer** — thin layer that calls pure mutations and manages history/flushing
4. Easier to test (pure functions don't need GenServer setup)

**Complexity target:** Store GenServer < 30, mutation modules < 40 each.

---

## 3. Split `Tomato.Deploy` (+ SSH key auth)

**Status:** done (`27fd2f7`).

Currently 16 functions handling SSH connection, SFTP, exec, diff, rebuild commands, modes, rollback. Today the connection path is **password-only** (`deploy.ex:156`) — credentials live in `config/deploy.secret.exs` or env vars and are passed in plain text to `:ssh.connect/3`. This refactor also closes that gap.

### Target structure

```
lib/tomato/deploy.ex            # Public API only (deploy, diff, rollback, etc.)
lib/tomato/deploy/
  ssh.ex                        # connect, disconnect, exec, collect_output
  sftp.ex                       # upload, read_file, make_dir
  rebuild.ex                    # rebuild_command, apply_config
  diff.ex                       # simple_diff
  config.ex                     # merge_config + auth resolution
```

### Approach

1. Extract SSH/SFTP into focused modules
2. Public `Deploy` module orchestrates by calling them
3. Each module is independently testable
4. **SSH key authentication** — `ssh.ex` resolves credentials in this order:
   - explicit `identity_file` in opts / config / `TOMATO_DEPLOY_IDENTITY_FILE` env var
   - `~/.ssh/id_ed25519`, `~/.ssh/id_rsa` (auto-discovered, in that order)
   - fall back to password auth (existing behaviour) only if no key is found
   Implemented via `:ssh.connect/3` with `user_dir` pointing at the key's directory; password remains as a last resort for lab use, with a one-line `Logger.warning` so users know they're on the legacy path.
5. **Config/env additions** — `TOMATO_DEPLOY_IDENTITY_FILE`, `:identity_file` key in `deploy.secret.exs.example`, README updated to recommend keys.

**Complexity target:** Deploy public API < 20, each helper module < 25.

---

## 4. Local Nix-fragment validation

**Status:** pending.

Today the walker treats leaf content as opaque strings (`walker.ex:118`) — a syntax error in a fragment passes through generation, gets uploaded via SFTP, and only fails at `nixos-rebuild` time on the remote machine. Painful feedback loop.

### Approach

1. New module `Tomato.NixValidator` — wraps `nix-instantiate --parse` (or `nix eval --expr` if `nix-command` is the only available CLI).
2. Walker calls `NixValidator.check_fragment/2` for each leaf as it's collected; failures are accumulated rather than raised, so all errors surface at once.
3. Generate flow returns `{:ok, output}` or `{:error, [%{node_id, line, message}, ...]}`; the LiveView surfaces them in the generated-output modal with the offending node highlighted.
4. **Graceful fallback** — if no `nix` binary is on PATH, log once and skip validation (don't break dev environments without Nix installed locally).
5. Validation is opt-in via config (`config :tomato, :validate_fragments, true`), default on.

**Why a separate section, not part of a god-module split:** this is new behaviour, lives in `walker.ex` + a new module, and is independent of the three refactors. Slot it in whenever the Deploy or Store work has a quiet moment.

---

## 5. Refactor Order

1. ~~**Deploy + SSH key auth** first — smallest split, no UI changes, unblocks the README's security promise~~ ✓
2. ~~**Store** next — affects mutations but pure functions are easier to test~~ ✓
3. **GraphLive** last — biggest change, depends on having stable Store API. Canvas ✓, modals ✓, sidebar ✓; event handler split is the remaining phase.
4. **Nix-fragment validator** — independent, slot in alongside any of the above (not yet started).

---

## 6. Constraints

- **No behaviour changes** in the splits — the existing test suite must still pass after each refactor (new feature work in §3.4 and §4 obviously adds behaviour, with its own tests)
- **Phase by phase** — one god module at a time, commit between each (single `v0.3` branch, no per-phase PRs since the project is pre-fork)
- **Giulia validates** — rerun conventions check after each split

---

## 7. New Tests

For each split, add module-level tests:

- ✓ `test/tomato/store/mutations_test.exs` — pure mutation tests (no GenServer)
- ✓ `test/tomato/store/persistence_test.exs` — JSON roundtrip tests
- ⬜ `test/tomato/deploy/ssh_test.exs` — connection mocking, **key vs password resolution** (not yet)
- ✓ `test/tomato/deploy/config_test.exs` — config resolution + auth ordering
- ⬜ `test/tomato/nix_validator_test.exs` — fragment parse success/failure, fallback when `nix` is missing
- ⬜ `test/tomato/walker_test.exs` — extend with fragment-validation error aggregation
- ⬜ `test/tomato_web/live/handlers/*_test.exs` — handler unit tests (will come with the handler split)
- ✓ `test/tomato_web/live/graph_live_test.exs` — GraphLive smoke test (15 cases, isolated per-test store, covers mount/CRUD/navigation/modals/undo-redo)

**Target:** 100+ tests after refactor. **Current:** 129 tests, 0 failures.

---

*Tomato v0.3 — paying down the technical debt before adding more features.*
