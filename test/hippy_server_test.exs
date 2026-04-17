defmodule Hippy.ServerTest do
  use ExUnit.Case

  alias Hippy.{Server, Operation.GetJobs}

  test "nil printer_uri in operation returns an error when using send_operation/1" do
    op = %GetJobs{printer_uri: nil}
    {:error, :printer_uri_required} = Server.send_operation(op)
  end

  test "nil endpoint returns an error when using send_operation/2" do
    op = %GetJobs{printer_uri: "http://valid"}
    {:error, :printer_uri_required} = Server.send_operation(op, nil)
  end

  test "nil printer_uri and no endpoint opt returns an error" do
    op = %GetJobs{printer_uri: nil}
    {:error, :printer_uri_required} = Server.send_operation(op, inet6: true)
  end

  test "unsupported scheme returns an error when derived from printer_uri" do
    op = %GetJobs{printer_uri: "ftp://nope"}
    {:error, {:unsupported_uri_scheme, "ftp"}} = Server.send_operation(op)
  end

  test "format_endpoint translates ipp scheme to http" do
    assert {:ok, "http://localhost:631/printers/foo"} =
             Server.format_endpoint("ipp://localhost:631/printers/foo")
  end

  test "format_endpoint passes http and https through unchanged" do
    assert {:ok, "http://localhost:631/printers/foo"} =
             Server.format_endpoint("http://localhost:631/printers/foo")

    assert {:ok, "https://localhost/printers/foo"} =
             Server.format_endpoint("https://localhost/printers/foo")
  end
end
