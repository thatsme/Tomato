# Tomato — Code Intelligence Report

**Generated:** 2026-04-11 | **Giulia v0.2.2.155** | **25 files, 25 modules, 131 functions**

---

## Executive Summary

Tomato is in **early prototype** state — functional and deployable but needs hardening before public release. The core architecture is sound (clean DAG engine, proper GenServer state management, working deploy pipeline). The main concerns are:

1. **Two god modules** need splitting (`Tomato.Store` and `TomatoWeb.GraphLive`)
2. **Three unprotected hubs** with zero specs and no tests
3. **No test coverage** on core business logic (only Phoenix scaffold tests exist)
4. **Missing @spec on 90%+ of public functions**

Overall health: **11 yellow zones, 0 red zones, 14 green** — solid for a prototype.

---

## Topology

| Metric | Value |
|---|---|
| Modules | 25 |
| Functions | 131 (public: ~100, private: ~31) |
| Structs | 6 |
| Types | 7 |
| Specs | 2 |
| Graph vertices | 156 |
| Graph edges | 113 |
| Components | 75 |
| Behaviour integrity | **consistent** |

### Top Hubs (most depended-on)

| Module | Degree | Role |
|---|---|---|
| `Tomato.Store` | 9 | Central state manager — everything talks to it |
| `Tomato.Subgraph` | 8 | Core data struct — used by Store, Walker, Constraint, Graph |
| `TomatoWeb` | 8 | Phoenix web layer (framework, expected) |
| `Tomato.Graph` | 6 | Top-level container |
| `TomatoWeb.GraphLive` | 6 | Main LiveView |

### Cycles Detected

| Cycle | Severity | Notes |
|---|---|---|
| `TomatoWeb` <-> `TomatoWeb.Layouts` | Low | Framework pattern — layouts import from TomatoWeb macros, normal |
| `Tomato.Demo` <-> `Tomato.Store` | Low | Demo seeds via Store, Store triggers Demo on init. Acceptable for dev tooling |

No dangerous cycles.

---

## God Modules

Modules with disproportionate size, complexity, and centrality. Refactoring candidates.

| Module | Functions | Complexity | Centrality | Score | Priority |
|---|---|---|---|---|---|
| **`Tomato.Store`** | 35 | 82 | 2 | 550 | **HIGH** — split into Store (GenServer) + Store.Operations (mutations) + Store.Persistence (JSON) |
| **`TomatoWeb.GraphLive`** | 17 | 92 | 0 | 283 | **HIGH** — 1300+ lines. Split event handlers into LiveView components or extract modals |

### Recommended Splits

**`Tomato.Store`** (35 functions, 82 complexity):
- `Tomato.Store` — GenServer lifecycle, state, PubSub
- `Tomato.Store.Mutations` — add_node, remove_node, add_edge, etc.
- `Tomato.Store.Persistence` — JSON encode/decode, flush, load
- `Tomato.Store.GraphManager` — list_graphs, load_graph, new_graph, save_as

**`TomatoWeb.GraphLive`** (17 handlers, 92 complexity):
- Extract modal components: `ContentEditorComponent`, `OodnEditorComponent`, `TemplatePickerComponent`, `GeneratedOutputComponent`, `GraphManagerComponent`
- Keep `GraphLive` as the orchestrator with assigns and event routing

---

## Unprotected Hubs

Hub modules (in-degree >= 4) with insufficient spec coverage. These are the riskiest to modify without breaking dependents.

| Module | In-Degree | Specs | Docs | Severity | Has Tests |
|---|---|---|---|---|---|
| `Tomato.Subgraph` | 6 | 0/8 (0%) | 1/8 (13%) | **RED** | No |
| `TomatoWeb` | 6 | 0/9 (0%) | 1/9 (11%) | **RED** | No |
| `Tomato.Graph` | 4 | 0/4 (0%) | 0/4 (0%) | **RED** | No |

**Action required:** Add @spec to all public functions in these three modules before public release. They are the foundation — breakage here cascades everywhere.

---

## Change Risk Ranking

Top 5 modules by composite risk score (centrality + complexity + fan-in/out + coupling + API surface):

| Rank | Module | Score | Top Risk Factor |
|---|---|---|---|
| 1 | `Tomato.Store` | 550 | Complexity (82), coupling (19 with GraphLive) |
| 2 | `TomatoWeb.GraphLive` | 283 | Complexity (92), coupling (33 with Store) |
| 3 | `Tomato.Subgraph` | 224 | High centrality (6), 100% public API |
| 4 | `Tomato.Constraint` | 168 | Complexity (22), coupling (13) |
| 5 | `TomatoWeb` | 164 | High centrality (6), framework module |

---

## Convention Violations

### Missing @spec (most impactful)

Nearly all public functions lack @spec. Key ones to add first:

- `Tomato.Store` — all 24 public functions (0 specs)
- `Tomato.Graph` — `new/1`, `root_subgraph/1`, `get_subgraph/2`, `put_subgraph/2`
- `Tomato.Subgraph` — `new/1`, `add_node/2`, `remove_node/2`, `add_edge/2`, etc.
- `Tomato.Walker` — `walk/1`, `walk_subgraph/3`, `interpolate/2`, `finalize/2`
- `Tomato.Deploy` — `deploy/2`, `test_connection/1`

### Missing @moduledoc

- `Tomato.Application` — add `@moduledoc false` (OTP convention)

---

## Struct Lifecycle

All 6 structs have clean lifecycle patterns. Notable:

| Struct | Users | Logic Leaks | Assessment |
|---|---|---|---|
| `Tomato.Subgraph` | 4 | Constraint, Graph, Store, Walker | Expected — core data type |
| `Tomato.Node` | 2 | Store, Subgraph | Clean |
| `Tomato.Edge` | 2 | Store, Subgraph | Clean |
| `Tomato.Graph` | 2 | Store, Walker | Clean |
| `Tomato.OODN` | 1 | Store | Clean |
| `Tomato.TemplateLibrary` | 0 | None | Only used as module attribute data |

No struct anti-patterns detected.

---

## Semantic Duplicates

| Cluster | Similarity | Assessment |
|---|---|---|
| `CoreComponents.flash/1` <-> `Layouts.flash_group/1` | 94.1% | Phoenix framework pattern — flash_group calls flash. Not a real duplicate |
| `Telemetry.start_link/1`, `init/1`, `metrics/0` | 92.2% | Supervisor boilerplate — expected similarity |

No actionable duplicates.

---

## Recommendations (Priority Order)

### Before Public Release

1. **Add @spec to hub modules** — `Subgraph`, `Graph`, `Store` public functions
2. **Add tests for core logic** — `Store`, `Walker`, `Constraint` need unit tests
3. **Remove unused PageController** — `page_controller.ex` and `page_html.ex` are dead code (route replaced by LiveView)

### Next Iteration

4. **Split `Tomato.Store`** — 35 functions is too many for one GenServer
5. **Split `TomatoWeb.GraphLive`** — extract modal components into LiveComponents
6. **Add @moduledoc** to `Tomato.Application`

### Nice to Have

7. Add integration test for the generate + deploy pipeline
8. Add property-based tests for DAG constraint validation
9. Consider Dialyzer for type checking once specs are in place
