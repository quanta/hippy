# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Hippy is an alpha-stage Elixir client for the Internet Printing Protocol (IPP). It builds IPP requests, encodes them to the IPP binary wire format, posts them over HTTP (typically to CUPS), and decodes the binary response. Elixir requirement: `~> 1.11` (driven by HTTPoison 2.x; see [mix.exs](mix.exs)). Current version: `0.4.0-dev`.

## Commands

- `mix deps.get` — fetch deps (HTTPoison, ex_doc)
- `mix compile`
- `mix test` — run full suite
- `mix test test/hippy_server_test.exs` — single file
- `mix test test/hippy_server_test.exs:6` — single test by line
- `mix format` / `mix format --check-formatted` — formatter configured via `.formatter.exs`
- `iex -S mix` — REPL. `.iex.exs` sets `inspect: [limit: :infinity]` so large IPP responses print in full.
- `mix docs` — generate ExDoc

## Architecture

Entry point `Hippy.send_operation/1,2` in [lib/hippy.ex](lib/hippy.ex) delegates to `Hippy.Server`, which runs the full request pipeline:

```
Operation struct → Hippy.Operation.build_request/1 (protocol) → %Hippy.Request{}
                 → Hippy.Encoder.encode/1                     → binary
                 → HTTPoison.post (Content-Type: application/ipp)
                 → Hippy.Decoder.decode/1                     → %Hippy.Response{}
```

Key modules:

- **[`Hippy.Operation`](lib/operation.ex)** — a `defprotocol` with one function, `build_request/1`. Each operation in [lib/operation/](lib/operation) (`PrintJob`, `GetJobs`, `GetJobAttributes`, `GetPrinterAttributes`, `CancelJob`) is a struct plus a `defimpl` returning a `%Hippy.Request{}`. **This is the extension point for new IPP operations.**
- **[`Hippy.Encoder`](lib/encoder.ex)** — serializes `%Hippy.Request{}` to the IPP binary wire format. Handles single values and `{{:set1, tag}, name, [values]}` set tuples per value-tag family (text-like, integer/enum).
- **[`Hippy.Decoder`](lib/decoder.ex)** — parses binary response into `%Hippy.Response{}`. Walks delimiter tags (`0x01` operation, `0x02` job, `0x03` end, `0x04` printer, `0x05` unsupported). Collapses repeated same-name attributes in `printer_attributes` into sets while preserving original order; `job_attributes` is a list-of-groups (one list per job).
- **[`Hippy.AttributeTransform`](lib/attribute_transform.ex)** — per-attribute post-processing invoked by the decoder: `URI.parse/1` for `:uri`, `Range.new/2` for `:range_of_integer`, `DateTime.from_iso8601/1` for `:datetime`, `Hippy.PrintResolution` for `:resolution`, enum-integer → atom via `Hippy.Protocol.Enum.decode!/2`, and unix-time integers to `DateTime` for known `time-at-*` attributes.
- **[`Hippy.Protocol.Enum`](lib/protocol/enum.ex)** — `__using__` macro that turns a map like `%{print_job: 0x0002, ...}` into a module exposing a zero-arity function per key (e.g. `print_job/0`) plus `encode/1`, `encode!/1`, `decode/1`, `decode!/1`. Used by every enum in [lib/protocol/](lib/protocol). The `get_enum_module/1` map in this file wires IPP attribute names (e.g. `"orientation-requested"`) to their enum module so the decoder can auto-translate values.
- **[`Hippy.AttributeGroup.to_map/1,2`](lib/attribute_group.ex)** — flattens a decoded attribute group into a map keyed by attribute name, dropping `{syntax, name, value}` tuples and recursively compacting `:collection` values. Caveat: called on a list-of-groups (e.g. `GetJobs` `job_attributes`), `to_map/1` returns only the head group — use `to_map(groups, index)` for others. This may change.
- **[`Hippy.Request`](lib/request.ex) / [`Hippy.Response`](lib/response.ex)** — plain structs. `Response` implements `Access` by delegating to `Map`.
- **[`Hippy.Server.format_endpoint/1`](lib/server.ex)** — rewrites the URI scheme `ipp` → `http` before the HTTP post; `http`/`https` pass through; anything else returns `{:unsupported_uri_scheme, ...}`. Each operation's `build_request/1` conversely rewrites `http(s)` → `ipp` for the `printer-uri` IPP attribute sent inside the body.

### send_operation options

`Hippy.send_operation/2` accepts a keyword list. A binary second argument is still accepted as a shortcut for `endpoint: binary`.

- `:endpoint` — URL string; overrides the endpoint derived from the operation's `printer_uri`.
- `:inet6` — boolean; when `true`, passes `hackney: [:inet6]` through to HTTPoison/hackney to force IPv6 resolution for this request.

Other options are currently ignored. The inet6 plumbing lives in `Hippy.Server.http_options/1`; add new transport flags there rather than sprinkling them through the pipeline.

## Conventions and gotchas

- IPP attribute tuples are shaped `{syntax_atom, "attribute-name", value}`. Sets on the encode side are `{{:set1, syntax}, name, [values]}` — don't confuse the two.
- Call enum values as zero-arity functions (e.g. `Hippy.Protocol.Operation.print_job()`), not by passing the atom.
- Binary patterns use `::8-signed`, `::16-signed`, `::32-signed` consistently — match that when adding new value tags.
- **Adding a new operation:** define a struct + `new/2` in [lib/operation/](lib/operation), add a `defimpl Hippy.Operation` below it returning a `%Hippy.Request{}`. If the operation introduces an enum-valued attribute, also register the attribute name → enum module in `Hippy.Protocol.Enum.get_enum_module/1`.
- `Hippy.Server.send_request/2` has a known `TODO: Rework error handling.  It's broken.` — non-200 responses and HTTPoison errors currently fall through `with` and return the raw tuple rather than a uniform error shape.
- 2-space indentation; run `mix format` before committing.
