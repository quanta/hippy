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

  describe "http_options/1" do
    # These tests pin down the Req transport plumbing. Default IPv4 / hostname
    # paths must stay untouched when no flags are set; new `:inet4` handling is
    # explicit so it never leaks into the IPv4 default case.
    test "returns an empty list when no transport flags are set (IPv4 path unchanged)" do
      assert [] = Server.http_options([])
      assert [] = Server.http_options(inet6: false)
    end

    test "sets inet6 when :inet6 is true" do
      assert [connect_options: [transport_opts: [inet6: true]]] =
               Server.http_options(inet6: true)
    end

    test "omits :inet4 when the caller does not provide it" do
      opts = Server.http_options(inet6: true)
      refute Keyword.has_key?(opts[:connect_options][:transport_opts], :inet4)
    end

    test "threads :inet4 when explicitly set alongside :inet6" do
      assert [connect_options: [transport_opts: [inet6: true, inet4: false]]] =
               Server.http_options(inet6: true, inet4: false)
    end

    test "threads :inet4 even when :inet6 is absent" do
      assert [connect_options: [transport_opts: [inet4: false]]] =
               Server.http_options(inet4: false)
    end

    test "sets verify_none when :insecure is true" do
      assert [connect_options: [transport_opts: [verify: :verify_none]]] =
               Server.http_options(insecure: true)
    end

    test "combines all transport flags in a stable order" do
      assert [
               connect_options: [
                 transport_opts: [inet6: true, inet4: false, verify: :verify_none]
               ]
             ] = Server.http_options(inet6: true, inet4: false, insecure: true)
    end
  end
end
