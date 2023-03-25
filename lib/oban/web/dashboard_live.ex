defmodule Oban.Web.DashboardLive do
  use Oban.Web, :live_view

  alias Oban.Web.{JobsPage, QueuesPage}

  @impl Phoenix.LiveView
  def mount(params, session, socket) do
    %{"oban" => oban, "refresh" => refresh} = session
    %{"prefix" => prefix, "resolver" => resolver} = session
    %{"live_path" => live_path, "live_transport" => live_transport} = session
    %{"user" => user, "access" => access, "csp_nonces" => csp_nonces} = session

    conf = await_init([oban], :supervisor)
    _met = await_init([oban, Oban.Met], :met)
    page = resolve_page(params)

    Process.put(:routing, {socket, prefix})

    socket =
      socket
      |> assign(conf: conf, params: params, page: page, resolver: resolver)
      |> assign(live_path: live_path, live_transport: live_transport)
      |> assign(csp_nonces: csp_nonces, access: access, user: user)
      |> assign(refresh: refresh, timer: nil)
      |> init_schedule_refresh()
      |> page.comp.handle_mount()

    {:ok, socket}
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <%= render_page(@page, assigns) %>
    """
  end

  defp render_page(page, assigns) do
    assigns =
      assigns
      |> Map.put(:id, "page")
      |> Map.drop([:csp_nonces, :live_path, :live_transport, :refresh, :timer])

    live_component(page.comp, assigns)
  end

  @impl Phoenix.LiveView
  def terminate(_reason, %{assigns: %{timer: timer}}) do
    if is_reference(timer), do: Process.cancel_timer(timer)

    :ok
  end

  def terminate(_reason, _socket), do: :ok

  @impl Phoenix.LiveView
  def handle_params(params, uri, socket) do
    socket.assigns.page.comp.handle_params(params, uri, socket)
  end

  @impl Phoenix.LiveView
  def handle_info(:clear_flash, socket) do
    {:noreply, clear_flash(socket)}
  end

  def handle_info({:update_refresh, refresh}, socket) do
    socket =
      socket
      |> assign(refresh: refresh)
      |> schedule_refresh()

    {:noreply, socket}
  end

  def handle_info(:pause_refresh, socket) do
    socket =
      if socket.assigns.refresh > 0 do
        assign(socket, refresh: -1, original_refresh: socket.assigns.refresh)
      else
        socket
      end

    {:noreply, socket}
  end

  def handle_info(:resume_refresh, socket) do
    socket =
      if socket.assigns[:original_refresh] do
        socket
        |> assign(refresh: socket.assigns.original_refresh)
        |> schedule_refresh()
      else
        socket
      end

    {:noreply, socket}
  end

  def handle_info(:refresh, socket) do
    socket =
      socket
      |> socket.assigns.page.comp.handle_refresh()
      |> schedule_refresh()

    {:noreply, socket}
  end

  def handle_info(message, socket) do
    socket.assigns.page.comp.handle_info(message, socket)
  end

  ## Mount Helpers

  defp await_init([oban_name | _] = args, proc, timeout \\ 15_000) do
    case apply(Oban.Registry, :whereis, args) do
      nil ->
        ref = make_ref()

        :telemetry.attach(
          ref,
          [:oban, proc, :init],
          &__MODULE__.relay_init/4,
          {args, self()}
        )

        receive do
          {^args, %{name: ^oban_name} = conf} ->
            :telemetry.detach(ref)

            # Sleep briefly to prevent race conditions between init and child process
            # initialization.
            Process.sleep(5)

            conf
        after
          timeout ->
            raise RuntimeError, "no config registered for #{inspect(args)} instance"
        end

      pid when is_pid(pid) ->
        Oban.config(oban_name)
    end
  end

  @doc false
  def relay_init(_event, _timing, %{conf: conf}, {args, pid}) do
    send(pid, {args, conf})
  end

  ## Render Helpers

  defp resolve_page(%{"page" => "jobs"}), do: %{name: :jobs, comp: JobsPage}
  defp resolve_page(%{"page" => "queues"}), do: %{name: :queues, comp: QueuesPage}
  defp resolve_page(_params), do: %{name: :jobs, comp: JobsPage}

  ## Refresh Helpers

  defp init_schedule_refresh(socket) do
    if connected?(socket) do
      schedule_refresh(socket)
    else
      assign(socket, timer: nil)
    end
  end

  defp schedule_refresh(socket) do
    if is_reference(socket.assigns.timer), do: Process.cancel_timer(socket.assigns.timer)

    if socket.assigns.refresh > 0 do
      interval = :timer.seconds(socket.assigns.refresh) - 50

      assign(socket, timer: Process.send_after(self(), :refresh, interval))
    else
      assign(socket, timer: nil)
    end
  end
end
