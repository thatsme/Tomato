defmodule TomatoWeb.GraphLive.DeployHandlers do
  @moduledoc """
  Handler functions for the deploy pipeline in `TomatoWeb.GraphLive`:
  generating a `.nix` file from the graph, running `nixos-rebuild`
  remotely (via `Tomato.Deploy`), diffing local vs remote config,
  rolling back, and testing the SSH connection.

  ## Two return shapes

  `handle_event`-style functions take `(params, socket)` and return the
  full `{:noreply, socket}` tuple so `GraphLive.handle_event/3` can
  delegate with a one-liner:

      def handle_event("reconfigure", params, socket),
        do: DeployHandlers.reconfigure(params, socket)

  `handle_info`-style helpers (`handle_deploy_result/2`,
  `handle_diff_result/2`) take `(result, socket)` and return a **bare
  socket** — the tuple wrapping happens in the `GraphLive.handle_info`
  dispatch stub:

      def handle_info({:deploy_result, result}, socket),
        do: {:noreply, DeployHandlers.handle_deploy_result(result, socket)}

  The split keeps the dispatch clause (which pattern-matches on the
  message envelope) in the LiveView where it belongs, while the body
  (which only cares about the inner result) lives here as a pure
  socket-transform function.

  ## Async pattern

  `reconfigure`, `show_diff`, `rollback`, and `test_connection` each
  spawn a `Task.Supervisor` child that runs the blocking `Tomato.Deploy`
  call and sends the result back as `{:deploy_result, ...}` or
  `{:diff_result, ...}`. The LiveView picks that up via `handle_info`
  and delegates to the result helpers above.
  """

  import Phoenix.Component, only: [assign: 3]

  @type socket :: Phoenix.LiveView.Socket.t()
  @type result :: {:noreply, socket()}
  @type socket_result :: socket()

  # --- Generate ---

  @spec generate(map(), socket()) :: result()
  def generate(_params, socket) do
    graph = socket.assigns.graph
    output = Tomato.Walker.walk(graph)
    validation = Tomato.Walker.validate(graph)

    # Write .nix file to disk
    generated_dir = Path.expand("priv/generated", File.cwd!())
    File.mkdir_p!(generated_dir)

    filename =
      case graph.backend do
        :flake -> "flake.nix"
        _ -> Tomato.Store.slugify(graph.name) <> ".nix"
      end

    nix_path = Path.join(generated_dir, filename)
    File.write!(nix_path, output)

    {:noreply,
     socket
     |> assign(:generated_output, output)
     |> assign(:generated_path, nix_path)
     |> assign(:validation_result, validation)
     |> assign(:show_generated, true)}
  end

  @spec close_generated(map(), socket()) :: result()
  def close_generated(_params, socket) do
    {:noreply,
     socket
     |> assign(:show_generated, false)
     |> assign(:deploy_status, nil)
     |> assign(:deploy_output, "")}
  end

  # --- Remote actions (async via Task.Supervisor) ---

  @spec reconfigure(map(), socket()) :: result()
  def reconfigure(params, socket) do
    nix_path = socket.assigns.generated_path
    mode = parse_deploy_mode(params["mode"])

    if nix_path && File.exists?(nix_path) do
      pid = self()

      Task.Supervisor.start_child(Tomato.TaskSupervisor, fn ->
        result = Tomato.Deploy.deploy(nix_path, %{mode: mode})
        send(pid, {:deploy_result, result})
      end)

      {:noreply,
       socket
       |> assign(:deploy_status, "running")
       |> assign(:deploy_output, "Running nixos-rebuild #{mode}...")}
    else
      {:noreply,
       socket
       |> assign(:deploy_status, "error")
       |> assign(:deploy_output, "No .nix file generated yet. Click Generate first.")}
    end
  end

  @spec show_diff(map(), socket()) :: result()
  def show_diff(_params, socket) do
    nix_path = socket.assigns.generated_path

    if nix_path && File.exists?(nix_path) do
      pid = self()

      Task.Supervisor.start_child(Tomato.TaskSupervisor, fn ->
        result = Tomato.Deploy.diff(nix_path)
        send(pid, {:diff_result, result})
      end)

      {:noreply,
       socket
       |> assign(:deploy_status, "running")
       |> assign(:deploy_output, "Fetching current config from machine...")}
    else
      {:noreply, socket}
    end
  end

  @spec rollback(map(), socket()) :: result()
  def rollback(_params, socket) do
    pid = self()

    Task.Supervisor.start_child(Tomato.TaskSupervisor, fn ->
      result = Tomato.Deploy.rollback()
      send(pid, {:deploy_result, result})
    end)

    {:noreply,
     socket
     |> assign(:deploy_status, "running")
     |> assign(:deploy_output, "Rolling back to previous generation...")}
  end

  @spec test_connection(map(), socket()) :: result()
  def test_connection(_params, socket) do
    pid = self()

    Task.Supervisor.start_child(Tomato.TaskSupervisor, fn ->
      result = Tomato.Deploy.test_connection()
      send(pid, {:deploy_result, result})
    end)

    {:noreply,
     socket
     |> assign(:deploy_status, "running")
     |> assign(:deploy_output, "Testing SSH connection...")}
  end

  # --- handle_info result helpers (return bare socket — see moduledoc) ---

  @spec handle_deploy_result({:ok, String.t()} | {:error, String.t()}, socket()) :: socket_result()
  def handle_deploy_result({:ok, output}, socket) do
    socket
    |> assign(:deploy_status, "success")
    |> assign(:deploy_output, output)
  end

  def handle_deploy_result({:error, reason}, socket) do
    socket
    |> assign(:deploy_status, "error")
    |> assign(:deploy_output, reason)
  end

  @spec handle_diff_result({:ok, String.t()} | {:error, String.t()}, socket()) :: socket_result()
  def handle_diff_result({:ok, ""}, socket) do
    socket
    |> assign(:deploy_status, "success")
    |> assign(:deploy_output, "No changes — local config matches the machine.")
  end

  def handle_diff_result({:ok, diff}, socket) do
    socket
    |> assign(:deploy_status, "success")
    |> assign(:deploy_output, "=== Diff (current vs new) ===\n\n" <> diff)
  end

  def handle_diff_result({:error, reason}, socket) do
    socket
    |> assign(:deploy_status, "error")
    |> assign(:deploy_output, "Diff failed: " <> reason)
  end

  # --- Private ---

  defp parse_deploy_mode("test"), do: :test
  defp parse_deploy_mode("dry_activate"), do: :dry_activate
  defp parse_deploy_mode("build"), do: :build
  defp parse_deploy_mode(_), do: :switch
end
