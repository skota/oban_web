defmodule Oban.Web.DashboardLive do
  use Oban.Web, :live_view

  alias Oban.Web.Plugins.Stats
  alias Oban.Web.{FooterComponent, JobsComponent, LogoComponent}
  alias Oban.Web.{NotificationComponent, RefreshComponent}

  @impl Phoenix.LiveView
  def mount(params, session, socket) do
    %{"oban" => oban, "refresh" => refresh} = session
    %{"socket_path" => path, "transport" => transport} = session
    %{"user" => user, "access" => access, "csp_nonces" => csp_nonces} = session

    conf = await_config(oban)

    :ok = Stats.activate(oban)

    socket =
      assign(socket,
        conf: conf,
        params: %{},
        page: resolve_page(params),

        # Socket Config
        csp_nonces: csp_nonces,
        live_path: path,
        live_transport: transport,

        # Access
        access: access,
        user: user,

        # Refreshing
        refresh: refresh,
        timer: nil
      )

    {:ok, init_schedule_refresh(socket)}
  end

  defp resolve_page(%{"page" => "jobs"}), do: JobsComponent
  defp resolve_page(_params), do: JobsComponent

  @impl Phoenix.LiveView
  def render(assigns) do
    ~L"""
    <meta name="live-transport" content="<%= @live_transport %>" />
    <meta name="live-path" content="<%= @live_path %>" />

    <main class="p-4">
      <%= live_component @socket, NotificationComponent, id: :flash, flash: @flash %>

      <header class="flex justify-between">
        <%= live_component @socket, LogoComponent %>
        <%= live_component @socket, RefreshComponent, id: :refresh, refresh: @refresh %>
      </header>

      <%= live_component @socket, @page, Map.put(assigns, :id, :page) %>

      <%= live_component @socket, FooterComponent %>
    </main>
    """
  end

  @impl Phoenix.LiveView
  def terminate(_reason, %{assigns: %{timer: timer}}) do
    if is_reference(timer), do: Process.cancel_timer(timer)

    :ok
  end

  def terminate(_reason, _socket), do: :ok

  @impl Phoenix.LiveView
  def handle_params(params, uri, socket) do
    socket.assigns.page.handle_params(params, uri, socket)
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

  def handle_info(:refresh, socket) do
    socket = socket.assigns.page.refresh(socket)

    {:noreply, schedule_refresh(socket)}
  end

  def handle_info(message, socket) do
    socket.assigns.page.handle_info(message, socket)
  end

  ## Mount Helpers

  defp await_config(oban_name, timeout \\ 15_000) do
    Oban.config(oban_name)
  rescue
    exception in [RuntimeError] ->
      handler = fn _event, _timing, %{conf: conf}, pid ->
        send(pid, {:conf, conf})
      end

      :telemetry.attach("oban-await-config", [:oban, :supervisor, :init], handler, self())

      receive do
        {:conf, %{name: ^oban_name} = conf} ->
          conf
      after
        timeout -> reraise(exception, __STACKTRACE__)
      end
  after
    :telemetry.detach("oban-await-config")
  end

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
