defmodule MixxTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  alias Mixx

  test "parses package only" do
    assert {:ok, %Mixx{package: "sobelow", task: nil, args: [], options: opts}} =
             Mixx.parse(["sobelow"])

    refute Keyword.has_key?(opts, :hex)
  end

  test "parses package with explicit task" do
    assert {:ok,
            %Mixx{package: "sobelow", task: "report", args: ["--format", "json"], options: opts}} =
             Mixx.parse(["sobelow", "report", "--format", "json"])

    refute opts[:task]
  end

  test "uses --task override" do
    assert {:ok, %Mixx{package: "sobelow", task: "custom.task", args: ["--json"], options: opts}} =
             Mixx.parse(["--task", "custom.task", "sobelow", "--json"])

    assert opts[:task] == "custom.task"
  end

  test "returns help banner" do
    assert {:help, banner} = Mixx.parse(["--help"])
    assert banner =~ "Usage: mix x"
  end

  test "errors when package missing" do
    assert {:error, message} = Mixx.parse([])
    assert message =~ "expected a package name"
  end

  test "passes through unknown options" do
    assert {:ok, %Mixx{package: "sobelow", task: nil, args: ["--unknown"], options: opts}} =
             Mixx.parse(["sobelow", "--unknown"])

    refute Keyword.has_key?(opts, :unknown)
  end

  test "errors when required option value missing" do
    assert {:error, message} = Mixx.parse(["--task"])
    assert message =~ "option --task expects a value"
  end

  test "errors on deprecated explicit source flags" do
    assert_raise Mix.Error, ~r/invalid option\(s\): --git/, fn ->
      Mixx.run(["--git", "https://example.com/repo.git", "sobelow"])
    end
  end

  @tag :integration
  @tag timeout: 240_000
  test "installs sobelow package when explicit task provided" do
    capture_io(fn ->
      assert :ok == Mixx.run(["sobelow", "--task", "sobelow", "--version"])
    end)
  end
end
