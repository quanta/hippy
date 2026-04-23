# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Hippy is an alpha-stage Elixir client for the Internet Printing Protocol (IPP). It builds IPP requests, encodes them to the IPP binary wire format, posts them over HTTP (typically to CUPS), and decodes the binary response. Elixir requirement: `~> 1.13` (driven by Req `~> 0.5`; see [mix.exs](mix.exs)). Current version: `0.4.0-dev`.

## Commands

- `mix deps.get` — fetch deps (Req, ex_doc)
- `mix compile`
- `mix test` — run full suite
- `mix test test/hippy_server_test.exs` — single file
- `mix test test/hippy_server_test.exs:6` — single test by line
- `mix format` / `mix format --check-formatted` — formatter configured via `.formatter.exs`
- `iex -S mix` — REPL. `.iex.exs` sets `inspect: [limit: :infinity]` so large IPP responses print in full.
- `mix docs` — generate ExDoc
- `mix run scripts/smoke.exs attrs <printer-uri> [--inet6]` — real-printer smoke test (GetPrinterAttributes). `print <printer-uri> <file>` subcommand submits an actual PrintJob.

## Architecture

Entry point `Hippy.send_operation/1,2` in [lib/hippy.ex](lib/hippy.ex) delegates to `Hippy.Server`, which runs the full request pipeline:

```
Operation struct → Hippy.Operation.build_request/1 (protocol) → %Hippy.Request{}
                 → Hippy.Encoder.encode/1                     → binary
                 → Req.post (Content-Type: application/ipp)
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
- **[`Hippy.Server.format_endpoint/1`](lib/server.ex)** — rewrites URI schemes for the HTTP transport: `ipp` → `http`, `ipps` → `https`; `http`/`https` pass through; anything else returns `{:unsupported_uri_scheme, ...}`. Each operation's `build_request/1` conversely rewrites `http` → `ipp` and `https` → `ipps` for the `printer-uri` IPP attribute sent inside the body (the regex uses a backreference to preserve the `s`).

### send_operation options

`Hippy.send_operation/2` accepts a keyword list. A binary second argument is still accepted as a shortcut for `endpoint: binary`.

- `:endpoint` — URL string; overrides the endpoint derived from the operation's `printer_uri`.
- `:inet6` — boolean; when `true`, translates to `connect_options: [transport_opts: [inet6: true]]` on the Req call, forcing IPv6 for this request.
- `:insecure` — boolean; when `true`, adds `verify: :verify_none` to `transport_opts`, skipping TLS certificate verification. Printers commonly present self-signed certs; opt in per-request rather than weakening the default.

Other options are currently ignored. The transport plumbing lives in `Hippy.Server.http_options/1`; add new transport flags there rather than sprinkling them through the pipeline.

### Error contract

`Hippy.send_operation/1,2` returns one of:

- `{:ok, %Hippy.Response{}}` — HTTP 200, IPP body decoded. The IPP-level outcome lives in `response.status_code` (e.g. `:successful_ok`, `:client_error_not_found`).
- `{:error, :printer_uri_required}` — operation struct has no `printer_uri` and no `:endpoint` was supplied.
- `{:error, {:unsupported_uri_scheme, scheme}}` — `printer_uri` scheme wasn't `ipp`, `http`, or `https`.
- `{:error, {:http_status, status, body}}` — printer returned a non-200 HTTP status. `body` is raw IPP bytes; callers may run `Hippy.Decoder.decode/1` on it.
- `{:error, {:transport, exception}}` — connection/transport error. `exception` is a `%Req.TransportError{}` / `%Mint.TransportError{}`; use `Exception.message/1` for a human-readable summary.

## Conventions and gotchas

- IPP attribute tuples are shaped `{syntax_atom, "attribute-name", value}`. Sets on the encode side are `{{:set1, syntax}, name, [values]}` — don't confuse the two.
- Call enum values as zero-arity functions (e.g. `Hippy.Protocol.Operation.print_job()`), not by passing the atom.
- Binary patterns use `::8-signed`, `::16-signed`, `::32-signed` consistently — match that when adding new value tags.
- **Adding a new operation:** define a struct + `new/2` in [lib/operation/](lib/operation), add a `defimpl Hippy.Operation` below it returning a `%Hippy.Request{}`. If the operation introduces an enum-valued attribute, also register the attribute name → enum module in `Hippy.Protocol.Enum.get_enum_module/1`.
- `Hippy.Server.send_request/3` returns one of the shapes documented in the Error contract section above. The rewrite to Req also calls Req with `retry: false, redirect: false, decode_body: false` — IPP is a non-idempotent RPC over a custom Content-Type and must not be retried, followed, or content-decoded.
- 2-space indentation; run `mix format` before committing.
