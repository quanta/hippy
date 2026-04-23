defmodule Hippy.Operation.CupsGetPrinters do
  @moduledoc """
  CUPS extension: list printers on the server.

  `printer_uri` is the server URI (e.g. `ipp://localhost:631/`), not a
  specific printer queue. CUPS-Get-Printers targets the server itself and
  does not include a `printer-uri` attribute in the IPP body; the HTTP
  target alone identifies the server.
  """

  @def_charset "utf-8"
  @def_lang "en"
  @def_atts ["all"]

  @enforce_keys [:printer_uri]

  defstruct printer_uri: nil,
            charset: @def_charset,
            language: @def_lang,
            requested_attributes: @def_atts

  def new(printer_uri, opts \\ []) do
    %__MODULE__{
      printer_uri: printer_uri,
      charset: Keyword.get(opts, :charset, @def_charset),
      language: Keyword.get(opts, :language, @def_lang),
      requested_attributes: Keyword.get(opts, :requested_attributes, @def_atts)
    }
  end
end

defimpl Hippy.Operation, for: Hippy.Operation.CupsGetPrinters do
  def build_request(op) do
    %Hippy.Request{
      request_id: System.unique_integer([:positive, :monotonic]),
      operation_id: Hippy.Protocol.Operation.cups_get_printers(),
      operation_attributes: [
        {:charset, "attributes-charset", op.charset},
        {:natural_language, "attributes-natural-language", op.language},
        {{:set1, :keyword}, "requested-attributes", op.requested_attributes}
      ],
      data: <<>>
    }
  end
end
