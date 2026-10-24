# ADR 0001: VirtualizationBackend boundary

## Status: accepted

## Context
quickgui originally invoked `quickemu`/`quickget` via raw `Shell().run`
calls scattered across pages, coupling UI to CLI internals.

## Decision
All external virtualization operations go through `VirtualizationBackend`
(`lib/infrastructure/virtualization/`), implemented by `QuickemuBackend`
(JSON contract preferred, CSV/text fallback). Presentation code never
spawns processes directly; use cases return typed `Result`/`Failure`.

## Consequences
- Tests run with `FakeVirtualizationBackend` — no VM or quickemu needed.
- Older quickemu releases keep working via parsing fallbacks.
- Backend absence/incompatibility surfaces as typed failures.
