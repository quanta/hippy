defmodule Hippy.Server do
  @supported_schemes ["ipp", "ipps", "http", "https"]

  def send_operation(op), do: send_operation(op, [])

  def send_operation(_op, nil) do
    {:error, :printer_uri_required}
  end

  def send_operation(op, endpoint) when is_binary(endpoint) do
    send_operation(op, endpoint: endpoint)
  end

  def send_operation(op, opts) when is_list(opts) do
    case Keyword.get(opts, :endpoint) do
      nil -> resolve_and_send(op, opts)
      endpoint when is_binary(endpoint) -> dispatch(op, endpoint, opts)
    end
  end

  defp resolve_and_send(%{printer_uri: nil}, _opts), do: {:error, :printer_uri_required}

  defp resolve_and_send(op, opts) do
    with {:ok, endpoint} <- format_endpoint(op.printer_uri) do
      dispatch(op, endpoint, opts)
    end
  end

  defp dispatch(op, endpoint, opts) do
    op
    |> Hippy.Operation.build_request()
    |> send_request(endpoint, opts)
  end

  def send_request(req, endpoint, opts \\ [])

  def send_request(%Hippy.Request{} = req, endpoint, opts) do
    case post(endpoint, Hippy.Encoder.encode(req), opts) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        {:ok, Hippy.Decoder.decode(body)}

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, {:http_status, status, body}}

      {:error, exception} ->
        {:error, {:transport, exception}}
    end
  end

  def format_endpoint(printer_uri) when is_nil(printer_uri) do
    {:error, :printer_uri_required}
  end

  def format_endpoint(printer_uri) do
    with %URI{scheme: scheme} = uri when scheme in @supported_schemes <- URI.parse(printer_uri),
         %URI{} = uri <- adjust_scheme(uri) do
      {:ok, to_string(uri)}
    else
      %URI{scheme: scheme} ->
        {:error, {:unsupported_uri_scheme, scheme}}

      error ->
        error
    end
  end

  defp adjust_scheme(%URI{scheme: "ipp"} = uri) do
    # Translate scheme back to http if we've found an ipp scheme in the URI.
    %{uri | scheme: "http"}
  end

  defp adjust_scheme(%URI{scheme: "ipps"} = uri) do
    # IPP-over-TLS: translate to https for the underlying transport.
    %{uri | scheme: "https"}
  end

  defp adjust_scheme(%URI{scheme: scheme} = uri) when scheme in ["http", "https"] do
    # Leave as is.
    uri
  end

  defp adjust_scheme(%URI{scheme: scheme}) do
    {:error, {:unsupported_uri_scheme, scheme}}
  end

  defp post(url, body, opts) do
    Req.post(
      url,
      [
        body: body,
        headers: [{"content-type", "application/ipp"}],
        retry: false,
        redirect: false,
        decode_body: false
      ] ++ http_options(opts)
    )
  end

  @doc false
  # Transport options. These thread through Req → Finch → Mint; if Req's default
  # adapter ever changes, revisit this mapping.
  #
  # `:inet6` — force IPv6 for the TCP connect.
  # `:inet4` — when explicitly `false`, disables Mint's family fallback
  #   (`Mint.Core.Transport.TCP` retries without `:inet6` if the first attempt
  #   fails). Disabling the fallback surfaces the real error instead of masking
  #   it as `:nxdomain` when the fallback attempts to DNS-resolve an IPv6
  #   literal string. When the caller does not set `:inet4`, the key is omitted
  #   entirely so Mint keeps its default (`inet4: true`) — preserving the
  #   pre-existing IPv4 / hostname path.
  # `:insecure` — skip TLS certificate verification. Printers commonly present
  #   self-signed certs; opt in per-request rather than weakening the default.
  def http_options(opts) do
    transport =
      [
        if(Keyword.get(opts, :inet6, false), do: {:inet6, true}),
        if(Keyword.has_key?(opts, :inet4), do: {:inet4, Keyword.fetch!(opts, :inet4)}),
        if(Keyword.get(opts, :insecure, false), do: {:verify, :verify_none})
      ]
      |> Enum.reject(&is_nil/1)

    case transport do
      [] -> []
      tops -> [connect_options: [transport_opts: tops]]
    end
  end
end
