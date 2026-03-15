defmodule ExCortex.Nextcloud.ClientTest do
  use ExCortex.DataCase, async: true

  alias ExCortex.Nextcloud.Client

  describe "base_url/0" do
    test "returns configured URL" do
      assert is_binary(Client.base_url())
    end
  end

  describe "auth_headers/0" do
    test "returns basic auth header" do
      headers = Client.auth_headers()
      assert [{"authorization", "Basic " <> _}] = headers
    end
  end

  describe "webdav_url/1" do
    test "builds path under remote.php/dav/files" do
      url = Client.webdav_url("/Documents/test.md")
      assert String.contains?(url, "remote.php/dav/files/")
      assert String.ends_with?(url, "/Documents/test.md")
    end
  end

  describe "ocs_url/1" do
    test "builds OCS API path" do
      url = Client.ocs_url("/apps/notes/api/v1/notes")
      assert String.contains?(url, "ocs/v2.php")
    end
  end
end
