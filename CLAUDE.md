# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Tomato is a hierarchical DAG engine for composable NixOS configuration management, built as a Phoenix LiveView application. It models system configurations as directed acyclic graphs organized in floors (levels). Walking the graph top-down in topological order composes a valid `configuration.nix` which can be deployed to a NixOS machine via SSH.

## Build & Development Commands

```bash
mix setup             # install deps, compile, setup assets
mix deps.get          # install dependencies
mix compile           # compile the project
mix phx.server        # start Phoenix dev server (localhost:4000)
iex -S mix phx.server # start with interactive shell
mix test              # run all tests
mix test path/to/test.exs      # run a single test file
mix test path/to/test.exs:42   # run a specific test (line number)
mix format            # format code
mix format --check-formatted   # check formatting
```

## Architecture

### Core Data Model

- **Node** (`lib/tomato/node.ex`) — types: `:input`, `:output`, `:leaf`, `:gateway`. Leaf nodes hold a `content` string (Nix config fragment with `${oodn_key}` placeholders). Gateway nodes reference a subgraph on the floor below via `subgraph_id`.
- **Edge** (`lib/tomato/edge.ex`) — directed dependency between two nodes on the same floor.
- **Subgraph** (`lib/tomato/subgraph.ex`) — self-contained DAG on a floor. Must have exactly one `:input`, one `:output`, and at least one other node. Owned by exactly one gateway (strict 1:1).
- **Graph** (`lib/tomato/graph.ex`) — top-level container: subgraphs, OODN registry, oodn_position, metadata.
- **OODN** (`lib/tomato/oodn.ex`) — Out-of-DAG key-value pair. Global variables referenced by leaf nodes via `${key}` syntax. Rendered as a singleton visual node on the canvas.

### Key Modules

- **`Tomato.Store`** — GenServer managing all state. In-memory graph, JSON persistence to `priv/graphs/`, PubSub broadcasting. All mutations serialized, DAG constraints validated synchronously, debounced 200ms JSON flush. Supports multiple graph files (list, load, new, save-as, delete).
- **`Tomato.Walker`** — topological traversal of the graph. Builds OODN map once, passes it unchanged to every depth. Interpolates `${key}` placeholders in leaf content. Recursively descends into gateway subgraphs. Wraps fragments in NixOS module skeleton with boot, SSH, keymap, stateVersion from OODNs.
- **`Tomato.Constraint`** — DAG validation: no cycles (Kahn's algorithm), single input/output per subgraph, minimum 3 nodes, same-floor edges, gateway-subgraph integrity.
- **`Tomato.Deploy`** — SSH/SFTP deployment via OTP `:ssh`. Connects to NixOS target, uploads `configuration.nix`, runs `nixos-rebuild switch`. Config from `config/deploy.secret.exs` or env vars (`TOMATO_DEPLOY_HOST`, `TOMATO_DEPLOY_PORT`, `TOMATO_DEPLOY_USER`, `TOMATO_DEPLOY_PASSWORD`).
- **`Tomato.TemplateLibrary`** — predefined NixOS config templates. Two types: leaf templates (single node) and gateway/stack templates (gateway + pre-wired child nodes). Categories: Stacks, System, Web, Database, Services, Monitoring, Packages.
- **`Tomato.Demo`** — seeds a demo graph on first run (when graph has only input+output nodes).

### LiveView UI

- **`TomatoWeb.GraphLive`** — main LiveView. SVG canvas with Bezier edge rendering, sidebar with node list/properties, modals for content editing, OODN editing, template picker, generated output with deploy status, graph manager.
- **`assets/js/hooks/graph_canvas.js`** — JS hook for drag-and-drop, zoom/pan (trackpad), long-press context menu, double-click navigation, Bezier edge updates during drag.

### Persistence

Each graph is a single JSON file in `priv/graphs/`. On startup, loads the first JSON file found (or creates `default.json` with demo seed). The JSON file is the source of truth. Graph Manager UI allows multiple graphs.

### Deploy Pipeline

1. Walker traverses graph → interpolates OODNs → generates `.nix` file to `priv/generated/`
2. Deploy module connects via SSH → uploads via SFTP to `/etc/nixos/configuration.nix` → runs `nixos-rebuild switch`
3. The NixOS module skeleton always includes SSH config so the deploy target remains accessible.

### OODN Flow

OODN registry lives on the Graph struct. Walker builds a flat `%{"key" => "value"}` map once at walk start. Every leaf node's content is interpolated with `Regex.replace(~r/\$\{(\w+)\}/, content, ...)`. The map is identical at every floor depth — read-only, never mutated during walk. Skeleton values (keymap, state_version) also come from OODNs.

### DAG Constraints (enforced on every mutation)

No cycles; single `:input`/`:output` per subgraph; edges same-floor only; `:input` has no incoming edges; `:output` has no outgoing edges; every gateway must reference a valid subgraph; every subgraph is owned by exactly one gateway.
