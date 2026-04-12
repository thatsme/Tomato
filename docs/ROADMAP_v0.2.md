# Tomato v0.2 — Roadmap

## Vision

v0.2 transforms Tomato from a single-file `configuration.nix` generator into a full **flake-native, multi-machine NixOS configuration manager** with Home Manager support.

---

## 1. Flake Backend

### 1.1 Flake Inputs as OODNs

Flake inputs map naturally to the OODN registry. Standard OODN keys for flakes:

| Key | Example Value | Purpose |
|---|---|---|
| `nixpkgs_url` | `github:nixos/nixpkgs?ref=nixos-unstable` | Main nixpkgs input |
| `home_manager_url` | `github:nix-community/home-manager` | Home Manager input |
| `flake_parts_url` | `github:hercules-ci/flake-parts` | Flake-parts for composability |
| `sops_nix_url` | `github:Mic92/sops-nix` | Secrets management |

The OODN editor gets a dedicated "Flake Inputs" section — each entry becomes an `inputs.name.url` in the generated `flake.nix`.

### 1.2 Walker FlakeBackend

New `Tomato.Backend.Flake` module alongside the existing NixOS backend. The walker's `finalize/2` dispatches based on backend selection.

**Generated output structure:**

```nix
{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    # ... from OODNs
  };

  outputs = { nixpkgs, home-manager, ... } @ inputs: {
    nixosConfigurations.${hostname} = nixpkgs.lib.nixosSystem {
      system = "${system_arch}";
      modules = [
        ./hardware-configuration.nix
        # ... composed fragments from the DAG walk
      ];
    };
  };
}
```

### 1.3 Backend Selection

- Add `backend` field to Graph struct (`:nixos_traditional` | `:nixos_flake`)
- UI toggle in the sidebar header next to the Generate button
- Walker dispatches to the appropriate `finalize` function
- Deploy command adapts: `nixos-rebuild switch` vs `nixos-rebuild switch --flake .#hostname`

---

## 2. Multi-Machine Support

### 2.1 Machine as Root Gateway

Each machine gets its own root-level gateway node. The graph structure becomes:

```
Floor 0 (root)
  OODN (flake inputs, shared vars)
  ├── Gateway: "mimas" (workstation)
  ├── Gateway: "phoebe" (server)
  └── Gateway: "mbp" (macbook - home-manager only)

Floor 1 (inside "mimas")
  Input → Networking → System → Services (gateway) → Output
                                  │
Floor 2 (inside Services)         ▼
  Input → PostgreSQL → Gitea → Nginx → Output
```

### 2.2 Machine Config Node

A new node type or a special gateway property: **machine metadata**.

| Field | Example |
|---|---|
| `hostname` | `mimas` |
| `system` | `aarch64-linux` |
| `stateVersion` | `24.11` |
| `type` | `nixos` or `home-manager` |

These override OODN values for that machine's subtree — so `${hostname}` resolves differently per machine.

### 2.3 Generation

Generate produces one of:
- **Traditional:** separate `configuration.nix` per machine
- **Flake:** single `flake.nix` with multiple `nixosConfigurations` entries

---

## 3. Module System

### 3.1 Reusable Modules

Currently leaf nodes hold raw Nix fragments. v0.2 introduces **module nodes** — leaf nodes that generate proper NixOS module structure:

```nix
{ config, lib, pkgs, ... }: {
  options.tomato.myService = {
    enable = lib.mkEnableOption "My Service";
    port = lib.mkOption { type = lib.types.port; default = 8080; };
  };

  config = lib.mkIf config.tomato.myService.enable {
    # ... service config
  };
}
```

The template library gets a "Module" category with option-based templates.

### 3.2 Module References

Leaf nodes can reference modules by name instead of inlining config:

```nix
tomato.myService.enable = true;
tomato.myService.port = 9090;
```

This maps to Nix's module system — define once in a module node, enable/configure in leaf nodes across machines.

---

## 4. Deploy Improvements

### 4.1 Multi-Target Deploy

- Deploy to multiple machines from one graph
- Machine selector in the deploy modal
- Parallel or sequential deployment with per-machine status

### 4.2 Flake Deploy

```bash
# Instead of scp + nixos-rebuild
nixos-rebuild switch --flake .#hostname --target-host root@machine
```

Or with `deploy-rs` / `colmena` integration for fleet management.

### 4.3 Dry Run / Test Mode

- `nixos-rebuild test` — activate without adding to boot menu
- `nixos-rebuild dry-activate` — show what would change without applying
- `nixos-rebuild build` — build only, don't activate
- UI shows diff of what will change before applying

### 4.4 Rollback

- `nixos-rebuild switch --rollback` button in the UI
- Show current and previous generation numbers
- One-click rollback to previous config

---

## 5. Home Manager Integration

### 5.1 Home Manager Nodes

New gateway type or tag: `home-manager`. Contains user-level configuration:

```nix
programs.git = {
  enable = true;
  userName = "Alessio";
  userEmail = "...";
};

programs.zsh.enable = true;
programs.tmux.enable = true;
```

### 5.2 Template Library Expansion

New category: **Home Manager**

- Shell (zsh, fish, bash config)
- Git
- Editors (neovim, helix, emacs)
- Terminal (alacritty, kitty, wezterm)
- Desktop (i3, sway, hyprland)
- Dev tools (direnv, nix-direnv)

### 5.3 Mixed Modules

Modules that apply to both NixOS and Home Manager (like in NobbZ's `mixed/` directory). A special gateway type that appears in both trees.

---

## 6. UI Improvements

### 6.1 Graph Canvas

- **Minimap** — small overview of the full graph in the corner
- **Snap to grid** — optional grid alignment for node positions
- **Multi-select** — shift+click to select multiple nodes, move/delete together
- **Search** — find nodes by name or content across all floors
- **Undo/redo** — revert last N mutations

### 6.2 Node Rendering

- **Content preview** inside the node (first 2-3 lines of Nix content)
- **Status indicators** — green dot for valid, red for syntax errors
- **Node groups** — visual grouping without gateways (cosmetic borders)

### 6.3 OODN Node

- **Sections** — group OODNs by category (Flake Inputs, System, Deploy)
- **Type hints** — URL, string, number, boolean
- **Validation** — check OODN values against expected format

### 6.4 Diff View

Before deploying, show a diff between:
- Current on-disk `configuration.nix` (fetched via SSH)
- Newly generated config

Side-by-side or unified diff in the deploy modal.

---

## 7. nixpkgs Integration

### 7.1 Options Search

Connect to NixOS option search (search.nixos.org/options API or local options.json):

- When editing a leaf node, autocomplete NixOS options
- Show option type, default, description inline
- Validate that options exist before generating

### 7.2 Package Search

Search nixpkgs packages from the template picker:

- `environment.systemPackages` autocomplete
- Package description and version info
- Dependency tree visualization

### 7.3 Deprecation Warnings

Parse `nixos-rebuild` output for deprecation warnings and surface them in the UI per-node — like the `services.postgresql.port` → `services.postgresql.settings.port` rename we caught live.

---

## 8. Persistence Improvements

### 8.1 Git-Backed Graphs

- Optional: save graphs to a git repo instead of loose JSON files
- Commit on every save with auto-generated message
- History view — see who changed what, when
- Branch support — test configs on a branch before merging to main

### 8.2 Import/Export

- Import existing `configuration.nix` → parse into graph nodes
- Import `flake.nix` → parse inputs as OODNs, modules as nodes
- Export graph as standalone directory (flake-ready)

---

## Priority Order

| Phase | Features | Effort |
|---|---|---|
| **Phase 1** | Flake backend, backend selection, deploy --flake | Medium |
| **Phase 2** | Multi-machine gateways, per-machine OODN override | Medium |
| **Phase 3** | Home Manager nodes + templates | Medium |
| **Phase 4** | Dry run, diff view, rollback | Small |
| **Phase 5** | nixpkgs options search + autocomplete | Large |
| **Phase 6** | UI improvements (minimap, multi-select, undo) | Medium |
| **Phase 7** | Git-backed persistence, import/export | Large |
| **Phase 8** | Module system (options, mkEnableOption) | Large |

---

*Tomato v0.2 — from aperitivo prototype to real infrastructure tool.*
