# Tomato v0.3 — Refactor Plan

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

## 3. Split `Tomato.Deploy`

Currently 16 functions handling SSH connection, SFTP, exec, diff, rebuild commands, modes, rollback.

### Target structure

```
lib/tomato/deploy.ex            # Public API only (deploy, diff, rollback, etc.)
lib/tomato/deploy/
  ssh.ex                        # connect, disconnect, exec, collect_output
  sftp.ex                       # upload, read_file, make_dir
  rebuild.ex                    # rebuild_command, apply_config
  diff.ex                       # simple_diff
  config.ex                     # merge_config
```

### Approach

1. Extract SSH/SFTP into focused modules
2. Public `Deploy` module orchestrates by calling them
3. Each module is independently testable

**Complexity target:** Deploy public API < 20, each helper module < 25.

---

## 4. Refactor Order

1. **Deploy** first — smallest, clearest split, no UI changes
2. **Store** next — affects mutations but pure functions are easier to test
3. **GraphLive** last — biggest change, depends on having stable Store API

---

## 5. Constraints

- **No behaviour changes** — all 69 tests must still pass after each refactor
- **Phase by phase** — one god module at a time, push between each
- **Giulia validates** — rerun conventions check after each split

---

## 6. New Tests

For each split, add module-level tests:

- `test/tomato/store/mutations_test.exs` — pure mutation tests (no GenServer)
- `test/tomato/store/persistence_test.exs` — JSON roundtrip tests
- `test/tomato/deploy/ssh_test.exs` — connection mocking
- `test/tomato/deploy/diff_test.exs` — already exists, expand
- `test/tomato_web/live/handlers/*_test.exs` — handler unit tests

**Target:** 100+ tests after refactor.

---

*Tomato v0.3 — paying down the technical debt before adding more features.*
