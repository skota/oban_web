defmodule Oban.Web.Jobs.SearchComponent do
  use Oban.Web, :live_component

  @distance_threshold 0.5

  # 1. Sort results by similarity
  # 2. Tab complete the top value

  # - Prevent bubbling keyboard shortcuts

  @impl Phoenix.LiveComponent
  def mount(socket) do
    {:ok, assign(socket, local: nil)}
  end

  @impl Phoenix.LiveComponent
  def update(assigns, socket) do
    terms = assigns.params[:terms]
    local = socket.assigns.local || terms

    {:ok, assign(socket, conf: assigns.conf, local: local)}
  end

  @impl Phoenix.LiveComponent
  def render(assigns) do
    ~H"""
    <form
      class="grow relative mr-3"
      id="search"
      data-shortcut={JS.focus_first(to: "#search")}
      phx-change="suggest"
      phx-submit="search"
      phx-target={@myself}
    >
      <div class="absolute top-2.5 left-0 pl-1.5 flex items-center text-gray-500 pointer-events-none">
        <Icons.magnifying_glass class="w-5 h-5" />
      </div>

      <input
        aria-label="Search"
        aria-placeholder="Search"
        autocorrect="false"
        class="w-full appearance-none text-sm border-none block rounded-md shadow-inner focus:shadow-blue-100 pr-3 py-2.5 pl-8 ring-1 ring-inset ring-gray-300 placeholder-gray-400 dark:placeholder-gray-600 focus:outline-none focus:ring-blue-500 focus:bg-blue-100/10"
        id="search-input"
        name="terms"
        phx-debounce="100"
        phx-focus={JS.show(to: "#search-suggest")}
        placeholder="Search"
        spellcheck="false"
        type="search"
        value={@local}
      />

      <button
        class={"absolute inset-y-0 right-0 pr-3 items-center text-gray-400 hover:text-blue-500 #{clear_class(@local)}"}
        phx-target={@myself}
        phx-click="clear"
        type="reset"
      >
        <Icons.x_circle class="w-5 h-5" />
      </button>

      <nav
        class="hidden absolute z-10 mt-1 p-2 w-full text-sm bg-white shadow-lg rounded-md ring-1 ring-black ring-opacity-5"
        id="search-suggest"
      >
        <.option
          :for={{name, desc, exmp} <- suggestions(@local, @conf)}
          name={name}
          desc={desc}
          exmp={exmp}
        />
      </nav>
    </form>
    """
  end

  attr :name, :string, required: true
  attr :desc, :string
  attr :exmp, :string

  defp option(assigns) do
    ~H"""
    <button
      class="block w-full flex items-center cursor-pointer p-1 rounded-md group hover:bg-blue-600"
      phx-click={JS.push("inject", value: %{prefix: @name}) |> JS.focus(to: "#search-input")}
      phx-target="#search"
      type="button"
    >
      <span class="block px-1 py-0.5 font-semibold rounded-sm bg-gray-100"><%= @name %></span>
      <span class="block ml-2 text-gray-600 group-hover:text-white"><%= @desc %></span>
      <span class="block ml-auto text-right text-gray-400 group-hover:text-white"><%= @exmp %></span>
    </button>
    """
  end

  # Events

  @impl Phoenix.LiveComponent
  def handle_event("clear", _params, socket) do
    send(self(), {:params, :terms, nil})

    {:noreply, assign(socket, local: nil)}
  end

  def handle_event("inject", %{"prefix" => prefix}, socket) do
    local =
      [socket.assigns.local, "#{prefix}"]
      |> Enum.join(" ")
      |> String.trim_leading()

    {:noreply, assign(socket, local: local)}
  end

  def handle_event("search", %{"terms" => terms}, socket) do
    send(self(), {:params, :terms, terms})

    {:noreply, socket}
  end

  def handle_event("suggest", %{"terms" => local}, socket) do
    {:noreply, assign(socket, local: local)}
  end

  # Class Helpers

  defp clear_class(nil), do: "hidden"
  defp clear_class(""), do: "hidden"
  defp clear_class(_terms), do: "block"

  # Suggestion Helpers

  defp suggestions(local, conf) do
    local
    |> to_string()
    |> String.split(" ")
    |> List.last()
    |> String.split(":", parts: 2)
    |> case do
      ["worker", value] -> suggest_workers(value, conf)
      _ -> suggest_default()
    end
  end

  defp suggest_default do
    [
      {"in:", "field qualifier", "account_id in:args"},
      {"node:", "host name", "node:machine@somehost"},
      {"worker:", "worker module", "worker:MyApp.SomeWorker"},
      {"queue:", "queue name", "queue:default"},
      {"priority:", "number from 0 to 3", "priority:1"},
      {"batch:", "a batch id", "batch:abc-123"},
      {"workflow:", "a workflow id", "workflow:abc-123"}
    ]
  end

  defp suggest_workers(partial, conf) do
    conf.name
    |> Oban.Met.labels("worker")
    |> Enum.filter(&similar?(&1, partial))
    |> Enum.map(&{&1, "", ""})
  end

  defp similar?(value, partial) do
    String.starts_with?(value, partial) or
      String.contains?(value, partial) or
      String.jaro_distance(value, partial) >= @distance_threshold
  end
end
