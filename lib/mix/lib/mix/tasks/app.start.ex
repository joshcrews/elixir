defmodule Mix.Tasks.App.Start do
  use Mix.Task

  @shortdoc "Starts all registered apps"

  @moduledoc """
  Starts all registered apps.

  The application is started by default as temporary. In case
  `:start_permanent` is set to `true` in your project configuration
  or the `--permanent` flag is given, it is started as permanent,
  which guarantee the node will shutdown in case the application
  crashes permanently.

  ## Command line options

    * `--force` - force compilation regardless of compilation times
    * `--temporary` - start the application as temporary
    * `--permanent` - start the application as permanent
    * `--no-compile` - do not compile even if files require compilation
    * `--no-protocols` - do not load consolidated protocols
    * `--no-deps-check` - do not check dependencies
    * `--no-elixir-version-check` - do not check elixir version
    * `--no-start` - do not start applications after compilation

  """
  @spec run(OptionParser.argv) :: :ok
  def run(args) do
    Mix.Project.get!

    {opts, _, _} = OptionParser.parse args, switches: [permanent: :boolean, temporary: :boolean]
    Mix.Task.run "loadpaths", args

    unless "--no-compile" in args do
      Mix.Project.compile(args)
    end

    unless "--no-protocols" in args do
      path = Path.join(Mix.Project.build_path, "consolidated")

      if File.dir?(path) do
        Code.prepend_path(path)

        Enum.each(File.ls!(path), fn file ->
          module = file |> Path.rootname() |> String.to_atom()
          :code.purge(module)
          :code.delete(module)
        end)
      end
    end

    # Stop the Logger when starting the application as it is
    # up to the application to decide if it should be restarted
    # or not.
    #
    # Mix should not depend directly on Logger so check that it's loaded.
    logger = Process.whereis(Logger)
    if logger do
      Logger.App.stop
    end

    if "--no-start" in args do
      # Start the Logger again if the application won't be starting it
      if logger do
        :ok = Logger.App.start
      end
    else
      start(Mix.Project.config, opts)
    end

    :ok
  end

  @doc false
  def start(config, opts) do
    apps =
      cond do
        Mix.Project.umbrella?(config) ->
          for %Mix.Dep{app: app} <- Mix.Dep.Umbrella.loaded, do: app
        app = config[:app] ->
          [app]
        true ->
          []
      end

    type = type(config, opts)
    Enum.each apps, &ensure_all_started(&1, type)
    check_configured()
    :ok
  end

  defp ensure_all_started(app, type) do
    case Application.ensure_all_started(app, type) do
      {:ok, _} -> :ok
      {:error, {app, reason}} ->
        Mix.raise "Could not start application #{app}: " <>
          Application.format_error(reason)
    end
  end

  @doc false
  def type(config, opts) do
    cond do
      opts[:temporary] -> :temporary
      opts[:permanent] -> :permanent
      config[:start_permanent] -> :permanent
      true -> :temporary
    end
  end

  defp check_configured() do
    configured = Mix.State.get(:configured_application, [])
    loaded = for {app, _, _} <- :application.loaded_applications(), do: app
    _ = for app <- configured -- loaded, :code.lib_dir(app) == {:error, :bad_name} do
      Mix.shell.info """
      You have configured application #{inspect app} but it is not available.
      This usually means one of:

      1. You have not added the application as a dependency in a mix.exs file.

      2. You are configuring an application that does not really exist.

      Please ensure #{inspect app} exists or remove the configuration.
      """
    end
    :ok
  end
end
