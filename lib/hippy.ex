defmodule Hippy do
  @moduledoc """
  IPP client API.

  `send_operation/2` accepts a keyword list of options:

    * `:endpoint` - override the URL derived from the operation's `printer_uri`
    * `:inet6` - when `true`, force the underlying HTTP connection to use IPv6

  For backward compatibility, passing a binary as the second argument is
  equivalent to `endpoint: binary`.
  """

  defdelegate send_operation(op), to: Hippy.Server
  defdelegate send_operation(op, opts_or_endpoint), to: Hippy.Server
end
