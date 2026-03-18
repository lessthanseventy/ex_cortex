defmodule ExCortex.Ruminations.RunnerDedupTest do
  use ExCortex.DataCase, async: true

  alias ExCortex.Ruminations
  alias ExCortex.Ruminations.Runner

  describe "compute_fingerprint/2" do
    test "returns consistent hash for same input" do
      fp1 = Runner.compute_fingerprint(1, "hello world")
      fp2 = Runner.compute_fingerprint(1, "hello world")
      assert fp1 == fp2
    end

    test "different inputs produce different fingerprints" do
      fp1 = Runner.compute_fingerprint(1, "hello")
      fp2 = Runner.compute_fingerprint(1, "goodbye")
      assert fp1 != fp2
    end

    test "different rumination_ids produce different fingerprints" do
      fp1 = Runner.compute_fingerprint(1, "hello")
      fp2 = Runner.compute_fingerprint(2, "hello")
      assert fp1 != fp2
    end

    test "normalizes whitespace" do
      fp1 = Runner.compute_fingerprint(1, "hello   world")
      fp2 = Runner.compute_fingerprint(1, "hello world")
      assert fp1 == fp2
    end

    test "trims leading and trailing whitespace" do
      fp1 = Runner.compute_fingerprint(1, "  hello world  ")
      fp2 = Runner.compute_fingerprint(1, "hello world")
      assert fp1 == fp2
    end

    test "handles nil input" do
      fp1 = Runner.compute_fingerprint(1, nil)
      fp2 = Runner.compute_fingerprint(1, nil)
      assert fp1 == fp2
      assert is_binary(fp1)
      assert String.length(fp1) == 64
    end

    test "returns a 64-char lowercase hex string" do
      fp = Runner.compute_fingerprint(1, "test")
      assert String.length(fp) == 64
      assert fp =~ ~r/^[0-9a-f]{64}$/
    end

    test "truncates input to 2048 characters" do
      long_input = String.duplicate("a", 5000)
      truncated_input = String.slice(long_input, 0, 2048)

      fp1 = Runner.compute_fingerprint(1, long_input)
      fp2 = Runner.compute_fingerprint(1, truncated_input)
      assert fp1 == fp2
    end
  end

  describe "latest_daydream/1" do
    test "returns nil when no daydreams exist" do
      assert Ruminations.latest_daydream(-1) == nil
    end

    test "returns the most recent daydream for a rumination" do
      {:ok, rumination} =
        Ruminations.create_rumination(%{name: "test-latest-#{System.unique_integer()}", trigger: "manual"})

      {:ok, _d1} = Ruminations.create_daydream(%{rumination_id: rumination.id, status: "complete"})
      {:ok, d2} = Ruminations.create_daydream(%{rumination_id: rumination.id, status: "running"})

      result = Ruminations.latest_daydream(rumination.id)
      assert result.id == d2.id
    end
  end

  describe "running_daydream_by_fingerprint/1" do
    test "returns nil when no matching daydream exists" do
      assert Ruminations.running_daydream_by_fingerprint("nonexistent_fp") == nil
    end

    test "returns running daydream with matching fingerprint" do
      {:ok, rumination} =
        Ruminations.create_rumination(%{name: "test-dedup-#{System.unique_integer()}", trigger: "manual"})

      fp = Runner.compute_fingerprint(rumination.id, "test input")

      {:ok, daydream} =
        Ruminations.create_daydream(%{
          rumination_id: rumination.id,
          status: "running",
          fingerprint: fp
        })

      result = Ruminations.running_daydream_by_fingerprint(fp)
      assert result.id == daydream.id
    end

    test "does not return completed daydream with matching fingerprint" do
      {:ok, rumination} =
        Ruminations.create_rumination(%{name: "test-dedup-done-#{System.unique_integer()}", trigger: "manual"})

      fp = Runner.compute_fingerprint(rumination.id, "done input")

      {:ok, _daydream} =
        Ruminations.create_daydream(%{
          rumination_id: rumination.id,
          status: "complete",
          fingerprint: fp
        })

      assert Ruminations.running_daydream_by_fingerprint(fp) == nil
    end
  end
end
