# Smoke test harness for Hippy against a real IPP printer.
#
# Usage:
#   mix run scripts/smoke.exs attrs ipp://printer.local:631/ipp/print
#   mix run scripts/smoke.exs attrs 'ipp://[fd00::1]:631/ipp/print' --inet6
#   mix run scripts/smoke.exs attrs ipps://printer.local:631/ipp/print --insecure
#   mix run scripts/smoke.exs print ipp://printer.local:631/ipp/print sample.pdf
#   mix run scripts/smoke.exs print ipp://printer.local:631/ipp/print hi.txt --job-name "smoke test"
#
# Flags: --inet6 forces IPv6. --insecure skips TLS cert verification
# (printers usually present self-signed certs).
#
# Exit codes: 0 ok, 1 operation failed, 2 usage error.

defmodule Smoke do
  def opts(flags) do
    Keyword.take(flags, [:inet6, :insecure])
  end

  def report({:ok, %Hippy.Response{status_code: status} = resp}, printer) do
    IO.puts("status: #{inspect(status)}")
    printer.(resp)

    unless ipp_success?(status) do
      IO.puts(:stderr, "IPP status was not successful")
      System.halt(1)
    end
  end

  def report({:error, {:http_status, status, body}}, _) do
    IO.puts(:stderr, "HTTP #{status} (#{byte_size(body)} bytes)")
    System.halt(1)
  end

  def report({:error, {:transport, exception}}, _) do
    IO.puts(:stderr, "transport error: #{Exception.message(exception)}")
    System.halt(1)
  end

  def report({:error, reason}, _) do
    IO.puts(:stderr, "error: #{inspect(reason)}")
    System.halt(1)
  end

  defp ipp_success?(status) when is_atom(status) do
    status |> Atom.to_string() |> String.starts_with?("successful")
  end

  defp ipp_success?(_), do: false
end

{flags, positional, _} =
  OptionParser.parse(System.argv(),
    switches: [inet6: :boolean, insecure: :boolean, job_name: :string]
  )

case positional do
  ["attrs", uri] ->
    uri
    |> Hippy.Operation.GetPrinterAttributes.new()
    |> Hippy.send_operation(Smoke.opts(flags))
    |> Smoke.report(fn %Hippy.Response{printer_attributes: attrs} ->
      map = Hippy.AttributeGroup.to_map(attrs)

      for key <- [
            "printer-name",
            "printer-state",
            "printer-state-reasons",
            "printer-make-and-model",
            "printer-uri-supported",
            "ipp-versions-supported"
          ] do
        IO.puts("#{key}: #{inspect(Map.get(map, key))}")
      end
    end)

  ["print", uri, path] ->
    document = File.read!(path)
    job_name = Keyword.get(flags, :job_name, Path.basename(path))

    uri
    |> Hippy.Operation.PrintJob.new(document, job_name: job_name)
    |> Hippy.send_operation(Smoke.opts(flags))
    |> Smoke.report(fn %Hippy.Response{job_attributes: jobs} ->
      case jobs do
        [job | _] ->
          map = Hippy.AttributeGroup.to_map(job)

          for key <- ["job-id", "job-uri", "job-state", "job-state-reasons"] do
            IO.puts("#{key}: #{inspect(Map.get(map, key))}")
          end

        [] ->
          IO.puts(:stderr, "warning: no job attributes returned by printer")
      end
    end)

  _ ->
    IO.puts(:stderr, """
    usage:
      mix run scripts/smoke.exs attrs <printer-uri> [--inet6] [--insecure]
      mix run scripts/smoke.exs print <printer-uri> <file> [--inet6] [--insecure] [--job-name NAME]
    """)

    System.halt(2)
end
