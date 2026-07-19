# Echoes macro architecture

The files directly in this directory are stable entrypoints used by Echoes and
by downstream build metadata. Keep those paths stable even when their
implementation moves.

Implementation details live under `internal/`, grouped by the feature they
compile:

- `system/` parses listener metadata and emits system lifecycle methods.
- `query/` owns generated query names and mutation-safe listener iteration.
- `storage/` assigns component storage IDs.
- `generic/` retains imports across Haxe generic-build passes.
- `CompilerSetup` owns initialization hooks used from HXML files.

The system macro follows this pipeline:

1. `SystemBuilder` reads the current class and performs generic substitution.
2. `SystemMetadata` and `ListenerSpec` turn fields into analyzed listener data.
3. `SystemEmitter` adds constructors, listener bridges, and lifecycle fields.
4. `QueryBuilder` remains the public query facade and delegates naming and
   iteration emission to `internal/query`.

Macro-global registries intentionally remain small and isolated. Their output
is compilation-order-sensitive, so behavior changes to them should be tested
on both JavaScript and HashLink and with the Haxe compilation server enabled.
