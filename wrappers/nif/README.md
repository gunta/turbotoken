# turbotoken NIF Support

Shared NIF C bridge sources for BEAM ecosystem wrappers.

## Scope

This is not a standalone package. It provides native glue consumed by:
- `wrappers/elixir`
- `wrappers/gleam`

Primary file:
- `wrappers/nif/turbotoken_nif.c`

## Publish

This directory is support-only glue and is not published as a standalone package.
