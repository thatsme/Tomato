# Tomato — Hierarchical DAG Engine
## Design Specification v0.1

---

## 1. What Tomato Is

Tomato is a general-purpose hierarchical DAG engine with pluggable code generation backends.

It models systems as directed acyclic graphs organized in floors (levels). Each node on a floor is either a leaf (holds a code generation template) or a gateway (points to a subgraph on the floor below). Walking the graph top-down, in topological order, produces a composed output determined by the active backend.

The first backend target is Nix — Tomato walks the graph and emits a valid `configuration.nix` expression. Future backends may emit Ansible playbooks, Docker Compose files, Kubernetes manifests, EDI workflow configs, or anything else expressible as composed text fragments.

Tomato is not a Nix GUI. Nix is the first consumer. The graph engine is the product.

---

## 2. Core Concepts

### 2.1 Node

The atomic unit of the graph. Every node has:

| Field | Type | Notes |
|---|---|---|
| `id` | UUID4 | Immutable, assigned at creation, never derived from name |
| `name` | string | Display label only, mutable, cosmetic |
| `type` | atom | `:input`, `:output`, `:leaf`, `:gateway` |
| `template_fn` | MFA or nil | Only for `:leaf` nodes — Elixir function reference for code generation |
| `subgraph_id` | UUID4 or nil | Only for `:gateway` nodes — reference to a subgraph on the floor below |
| `inputs` | list(UUID4) | IDs of nodes this node receives from |
| `outputs` | list(UUID4) | IDs of nodes this node feeds into |

Node types:

- `:input` — entry point of a subgraph. Receives data from the floor above. Exactly one per subgraph. No incoming edges. Not user-deletable.
- `:output` — exit point of a subgraph. Surfaces composed result to the floor above. Exactly one per subgraph. No outgoing edges. Not user-deletable.
- `:leaf` — atomic code generator. Holds a `template_fn`. No subgraph. Produces a code fragment when called with resolved inputs.
- `:gateway` — navigational node. References a subgraph on the floor below. Its output is purely the composed output of that subgraph — no additional template logic at the gateway level.

### 2.2 Edge

A directed dependency relationship between two nodes on the same floor.

| Field | Type | Notes |
|---|---|---|
| `id` | UUID4 | Immutable |
| `from` | UUID4 | Source node ID |
| `to` | UUID4 | Target node ID |

Constraints:
- Edges only connect nodes on the same floor.
- No cycles permitted. Validated on every mutation.
- `:input` nodes have no incoming edges.
- `:output` nodes have no outgoing edges.
- Fan-out is permitted: one node can feed multiple downstream nodes.
- Fan-in is permitted: multiple nodes can feed one downstream node.

### 2.3 Subgraph

A self-contained DAG that lives on a specific floor. Every subgraph has:

| Field | Type | Notes |
|---|---|---|
| `id` | UUID4 | Immutable |
| `name` | string | Display label |
| `floor` | integer | Floor number (0 = root, increases downward) |
| `nodes` | list(Node) | Must contain exactly one `:input`, one `:output`, and at least one other node |
| `edges` | list(Edge) | Directed edges within this subgraph |

A subgraph is owned by exactly one gateway node on the floor above. This is a strict 1:1 relationship — subgraphs are not shared between gateways. Reuse is achieved through templates (same `template_fn` instantiated in different subgraphs), not through subgraph sharing.

### 2.4 Floor

A floor is a navigation level. The root is floor 0. Floors increase as you descend. Each floor contains one or more subgraphs.

Navigation is downward only: from a gateway node on floor N, you descend into its subgraph on floor N+1. You ascend by navigating back up through the breadcrumb trail.

There is no hard limit on floor depth.

### 2.5 OODN (Out-Of-DAG Node)

Ambient context that exists outside the graph flow. OODNs are key-value pairs available to any node on any floor during code generation, without being part of the topological walk.

| Field | Type | Notes |
|---|---|---|
| `id` | UUID4 | Immutable |
| `key` | string | Human-readable identifier (e.g. `"nixpkgs"`, `"system_arch"`) |
| `value` | string | The ambient value — always a string, backend interprets it |

OODNs have no edges. They are not walked. They are not owned by any subgraph or floor. The OODN registry lives at the top-level graph and is passed in full to every `template_fn` call on every floor, at every depth, without modification.

**Rule:** anything that is global to the environment and referenced by more than one node belongs in the OODN registry, not hardcoded in a leaf node's content.

#### Standard OODN keys for the Nix backend

| Key | Example value | Used by |
|---|---|---|
| `state_version` | `"24.11"` | System base node |
| `nixpkgs_channel` | `"nixos-24.11"` | All package nodes |
| `system_arch` | `"aarch64-linux"` | Boot/hardware nodes |
| `timezone` | `"Europe/Rome"` | System base node |
| `hostname` | `"tomato-node"` | Networking node |
| `locale` | `"it_IT.UTF-8"` | Console/i18n node |
| `keymap` | `"it"` | Console node |

#### How OODNs reach template functions

The walker builds the OODN map once at walk start, from the graph's `oodn_registry`:

```elixir
oodn = graph.oodn_registry
       |> Map.values()
       |> Map.new(fn %{key: k, value: v} -> {k, v} end)
# => %{"hostname" => "tomato-node", "state_version" => "24.11", ...}
```

This map is carried unchanged in `Walker.Context` and passed as the second argument to every `template_fn` call:

```elixir
# Walker calls every leaf node like this:
{:ok, fragment} = template_fn.(upstream_inputs, oodn)
```

The `oodn` map is identical at floor 0, floor 1, floor 2, and any depth. It never changes during a walk. It is read-only — template functions cannot mutate it.

#### Concrete template function using OODNs

```elixir
# Networking leaf node — uses hostname from OODN instead of hardcoding it
def networking(_inputs, %{"hostname" => hostname}) do
  {:ok, """
  networking.hostName = "#{hostname}";
  networking.networkmanager.enable = true;
  """}
end

# System base leaf node — uses multiple OODNs
def system_base(_inputs, %{"state_version" => sv, "timezone" => tz, "locale" => locale}) do
  {:ok, """
  time.timeZone = "#{tz}";
  i18n.defaultLocale = "#{locale}";
  system.stateVersion = "#{sv}";
  """}
end

# PostgreSQL leaf node — uses nixpkgs_channel to select correct package set
def postgresql(_inputs, %{"nixpkgs_channel" => _channel}) do
  {:ok, """
  services.postgresql = {
    enable = true;
    package = pkgs.postgresql_16;
    settings.port = 5432;
  };
  """}
end
```

#### What does NOT belong in OODNs

- Node-specific configuration (a postgresql port that only postgresql uses — that's leaf node content).
- Values that differ between nodes of the same type — use leaf node parameters for those.
- Secrets or credentials — OODNs are stored in plaintext JSON.

#### OODN vs leaf node content — decision rule

Ask: "Is this value used by more than one node, or is it a property of the environment rather than a specific service?"

- Yes → OODN
- No → hardcode in leaf node content

### 2.6 Template Function

A leaf node's code generation unit. A template function is a standard Elixir function with the signature:

```elixir
@spec template_fn(inputs :: map(), oodn :: map()) :: {:ok, String.t()} | {:error, term()}
```

- `inputs` — a map of resolved outputs from upstream nodes on the same floor
- `oodn` — the full OODN registry (key → value)
- Returns `{:ok, code_fragment}` or `{:error, reason}`

Template functions are hot-loadable via Elixir's dynamic compilation. The module name is derived from the node's UUID to avoid collisions.

---

## 3. Graph Persistence

The entire Tomato graph state is stored in a single JSON file — one file per named environment/project.

### 3.1 JSON Schema (top level)

```json
{
  "id": "<uuid4>",
  "name": "my-cluster",
  "version": "0.1.0",
  "created_at": "<iso8601>",
  "updated_at": "<iso8601>",
  "oodn_registry": {
    "<uuid4>": { "key": "nixpkgs", "value": "github:nixos/nixpkgs/nixos-23.11" }
  },
  "subgraphs": {
    "<uuid4>": {
      "id": "<uuid4>",
      "name": "root",
      "floor": 0,
      "nodes": { "<uuid4>": { ...node } },
      "edges": { "<uuid4>": { ...edge } }
    }
  },
  "root_subgraph_id": "<uuid4>"
}
```

### 3.2 Write Strategy

All mutations flow through a single `Tomato.Store` GenServer:

1. Mutation applied to in-memory state (ETS).
2. DAG constraint validation runs synchronously (cycle detection, edge validity).
3. If valid, debounced async JSON flush is scheduled (200ms window).
4. If invalid, mutation is rejected and error returned to caller.

The JSON file is the source of truth. On startup, Tomato loads the file into ETS. No separate database required.

---

## 4. The Walker

`Tomato.Walker` traverses the graph top-down and produces composed output.

### 4.1 Algorithm

```
walk(subgraph, context):
  sorted = topological_sort(subgraph.nodes, subgraph.edges)
  results = %{}
  for node in sorted:
    case node.type:
      :input  → results[node.id] = context.input
      :output → return results[node.id]  (collected from upstream)
      :leaf   → results[node.id] = call template_fn(upstream_results, context.oodn)
      :gateway →
        child_subgraph = load_subgraph(node.subgraph_id)
        child_context = %{input: upstream_results, oodn: context.oodn}
        results[node.id] = walk(child_subgraph, child_context)
  return results[output_node.id]
```

### 4.2 Walker Context

```elixir
%Tomato.Walker.Context{
  input: term(),          # data flowing into this subgraph from above
  oodn: map(),            # full OODN registry
  backend: module(),      # e.g. Tomato.Backend.Nix
  depth: non_neg_integer  # current floor, for debugging/logging
}
```

### 4.3 Backend Protocol

```elixir
defprotocol Tomato.Backend do
  @spec finalize(backend :: t(), fragments :: list(String.t())) :: {:ok, String.t()} | {:error, term()}
end
```

The backend receives the ordered list of code fragments from the walk and is responsible for final composition — joining, wrapping, validating syntax.

---

## 5. DAG Constraints

Enforced on every mutation before the state is committed:

| Constraint | Description |
|---|---|
| No cycles | Topological sort must succeed |
| Single `:input` per subgraph | Exactly one input node |
| Single `:output` per subgraph | Exactly one output node |
| Minimum 3 nodes | input + output + at least one other |
| Edge same-floor | Edges must not cross subgraph boundaries |
| `:input` no incoming edges | Input is a source, not a sink |
| `:output` no outgoing edges | Output is a sink, not a source |
| Gateway has subgraph | A `:gateway` node must reference a valid subgraph ID |
| Subgraph ownership | A subgraph is referenced by exactly one gateway node |

---

## 6. Nix Backend

The first concrete backend. `Tomato.Backend.Nix` emits valid NixOS module expressions.

### 6.1 Leaf Template Contract (Nix)

Each leaf node's `template_fn` returns a Nix expression fragment as a string. Example:

```elixir
def postgresql(%{version: version, port: port}, _oodn) do
  {:ok, """
  services.postgresql = {
    enable = true;
    package = pkgs.postgresql_#{version};
    port = #{port};
  };
  """}
end
```

### 6.2 Finalization

`Tomato.Backend.Nix.finalize/2` wraps collected fragments in a NixOS module skeleton:

```nix
{ config, pkgs, lib, ... }:
{
  # --- composed fragments ---
  <fragment_1>
  <fragment_2>
  ...
}
```

### 6.3 Validation

After generation, the output is validated with:

```bash
nix-instantiate --parse <output_file>
```

Syntax errors are surfaced as `{:error, reason}` with the parser output attached.

---

## 7. Project Structure

```
tomato/
├── lib/
│   ├── tomato/
│   │   ├── node.ex           # Node struct and type validation
│   │   ├── edge.ex           # Edge struct
│   │   ├── subgraph.ex       # Subgraph struct
│   │   ├── oodn.ex           # OODN struct
│   │   ├── store.ex          # GenServer — ETS + JSON persistence
│   │   ├── walker.ex         # DAG traversal engine
│   │   ├── constraint.ex     # DAG constraint validation
│   │   ├── template.ex       # Hot-loadable template function compiler
│   │   └── backend/
│   │       └── nix.ex        # Nix backend implementation
├── test/
│   ├── tomato/
│   │   ├── store_test.exs
│   │   ├── walker_test.exs
│   │   ├── constraint_test.exs
│   │   └── backend/
│   │       └── nix_test.exs
├── mix.exs
└── README.md
```

---

## 8. What Tomato Is NOT

- Not a Nix package manager wrapper.
- Not a visual GUI (the engine is headless; a UI is a separate concern).
- Not a general-purpose workflow engine (no retries, no scheduling, no async execution — it is a code generator, not a runtime).
- Not opinionated about storage beyond the JSON file (no database dependency in the core).

---

## 9. Open Questions (Deferred)

- Template function versioning: when a `template_fn` changes, how are existing nodes migrated?
- Multi-user concurrent edits: the GenServer serializes writes, but conflict resolution across sessions is undefined.
- Backend plugin system: how are third-party backends registered?
- UI layer: Phoenix LiveView application consuming the Tomato core library — separate project.

---

*Tomato v0.1 — designed over aperitivo, April 2026* 🍅
