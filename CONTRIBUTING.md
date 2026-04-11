# Contributing to Tomato

Thank you for your interest in contributing to Tomato. This document explains
how to contribute and what to expect from the process.

---

## Before You Start

Tomato is a hierarchical DAG engine for composable NixOS configuration management,
built on Elixir/OTP and Phoenix LiveView. Contributions are welcome, but please
understand the project's philosophy before proposing changes:

- **Graph engine first** — the DAG engine is the product, Nix is just the first backend
- **Composable** — small nodes that compose into complex configurations
- **BEAM-native** — OTP supervision, GenServer state, PubSub
- **JSON as source of truth** — no database dependency
- **Observable** — every mutation is validated and persisted

If your contribution aligns with these principles, it's likely a good fit.

---

## Contributor License Agreement (CLA)

**All contributors must agree to the CLA before their code can be merged.**

By submitting a pull request, you automatically agree to the CLA for minor
contributions (documentation, typos, small fixes).

For significant contributions (new skills, architectural changes, new providers),
you must explicitly sign the CLA by including this statement in your PR:

> I have read the Tomato CLA and agree to its terms.
> My GitHub username is [username] and my legal name is [full name].

Read the full CLA in [CLA.md](CLA.md).

**Why the CLA includes a relicensing clause:** The CLA allows the project to be
relicensed in the future without requiring permission from every contributor. This
is standard practice for projects that may evolve commercially, and does not affect
your right to use your own contributions however you wish.

---

## What We Welcome

- **New templates** — NixOS service templates for the template library
- **New backends** — Ansible, Docker Compose, Kubernetes manifests
- **Bug fixes** — especially around DAG constraints and graph persistence
- **Documentation** — architecture explanations, usage examples
- **UI improvements** — canvas interactions, node rendering, modals

## What We Don't Want

- External dependencies that break the single-JSON persistence model
- Features that require a database
- Complexity for its own sake

---

## How to Contribute

1. **Fork** the repository
2. **Create a branch** — `git checkout -b feature/my-skill` or `fix/router-fallback`
3. **Write your code** — follow the existing patterns in `lib/tomato/`
4. **Add tests** — use `ExUnit`; see existing tests in `test/tomato/`
5. **Open a pull request** — describe what you built and why

### Template Contributions

New templates go in `lib/tomato/template_library.ex`. Each template is a map with:

```elixir
%{
  id: "my-service",
  name: "My Service",
  category: "Services",
  description: "What this service does",
  oodn_keys: ["port"],  # OODN variables used
  content: ~S\"""
  services.myService = {
    enable = true;
    port = ${port};
  };
  \"""
}
```

Gateway/stack templates include a `type: :gateway` and `children: [...]` list.

---

## Code Style

- Standard Elixir formatting — run `mix format` before committing
- No unnecessary abstractions
- Pattern match explicitly — avoid generic catch-alls where possible
- Log with structured metadata: `Logger.info("event", skill: :my_skill, duration: ms)`

---

## Questions

Open an issue or start a discussion on GitHub. The project owner (Alessio Battistutta)
reviews contributions personally.

---

*Tomato — Hierarchical DAG Engine for composable NixOS configuration.*
*Copyright 2026 Alessio Battistutta — Apache License 2.0*
