defmodule Kitto.CodeReloaderTest do
  use ExUnit.Case

  import Mock

  alias Kitto.CodeReloader

  @jobs_dir "test/fixtures/jobs"
  @valid_job Path.join(@jobs_dir, "valid_job.exs") |> Path.absname()
  @lib_file Path.join("lib", "travis.ex") |> Path.absname()

  setup do
    Application.put_env(:kitto, :jobs_dir, @jobs_dir)

    on_exit(fn ->
      Application.delete_env(:kitto, :jobs_dir)
      Application.delete_env(:kitto, :reload_code?)
    end)
  end

  test "#reload_code? returns true when :reload_code? env is not set" do
    Application.delete_env(:kitto, :reload_code?)

    assert CodeReloader.reload_code?() == true
  end

  test "#reload_code? returns true when :reload_code? env is true" do
    Application.put_env(:kitto, :reload_code?, true)

    assert CodeReloader.reload_code?() == true
  end

  test "#reload_code? returns false when :reload_code? env is false" do
    Application.put_env(:kitto, :reload_code?, false)

    assert CodeReloader.reload_code?() == false
  end

  test "#when a job modification event is received on linux, calls Runner.reload_job/1" do
    self() |> Process.register(:mock_server)

    {:ok, reloader} = CodeReloader.start_link(name: :reloader, server: :mock_server)

    send(reloader, {make_ref(), {:fs, :file_event}, {@valid_job, [:modified, :closed]}})

    receive do
      message -> assert message == {:"$gen_cast", {:reload_job, @valid_job}}
    after
      100 -> exit({:shutdown, "runner did not receive reload message"})
    end
  end

  test "#when a job creation event is received on linux, calls Runner.reload_job/1" do
    self() |> Process.register(:mock_server)

    {:ok, reloader} = CodeReloader.start_link(name: :reloader, server: :mock_server)

    send(reloader, {make_ref(), {:fs, :file_event}, {@valid_job, [:created]}})

    receive do
      message -> assert message == {:"$gen_cast", {:reload_job, @valid_job}}
    after
      100 -> exit({:shutdown, "runner did not receive reload message"})
    end
  end

  test "#when a job deletion event is received on linux, calls Runner.stop_job/1" do
    self() |> Process.register(:mock_server)

    {:ok, reloader} = CodeReloader.start_link(name: :reloader, server: :mock_server)

    send(reloader, {make_ref(), {:fs, :file_event}, {@valid_job, [:deleted]}})

    receive do
      message -> assert message == {:"$gen_cast", {:stop_job, @valid_job}}
    after
      100 -> exit({:shutdown, "runner did not receive stop message"})
    end
  end

  describe "macOS job modifications events" do
    test "#when [:inodemetamod, :modified] is received, calls Runner.reload_job/1" do
      self() |> Process.register(:mock_server)

      {:ok, reloader} = CodeReloader.start_link(name: :reloader, server: :mock_server)

      file_change = {@valid_job, [:inodemetamod, :modified]}

      send(reloader, {make_ref(), {:fs, :file_event}, file_change})

      receive do
        message -> assert message == {:"$gen_cast", {:reload_job, @valid_job}}
      after
        100 -> exit({:shutdown, "runner did not receive reload message"})
      end
    end

    test """
    #when [:created, :renamed, :modified, :changeowner] is received,
    #calls Runner.reload_job/1
    """ do
      self() |> Process.register(:mock_server)

      {:ok, reloader} = CodeReloader.start_link(name: :reloader, server: :mock_server)

      file_change = {@valid_job, [:inodemetamod, :modified]}

      send(reloader, {make_ref(), {:fs, :file_event}, file_change})

      receive do
        message -> assert message == {:"$gen_cast", {:reload_job, @valid_job}}
      after
        100 -> exit({:shutdown, "runner did not receive reload message"})
      end
    end
  end

  test "#when a lib modification file event is received, calls elixir compilation task" do
    test_pid = self()
    mock_run = fn _ -> send(test_pid, :compiled) end

    with_mock Mix.Tasks.Compile.Elixir, run: mock_run do
      {:ok, reloader} = CodeReloader.start_link(name: :reloader, server: :mock_server)

      send(reloader, {make_ref(), {:fs, :file_event}, {@lib_file, [:modified, :closed]}})

      receive do
        :compiled -> :ok
      end
    end
  end
end
