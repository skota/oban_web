defmodule Oban.Web.StateComponent do
  use Oban.Web, :live_component

  def update(assigns, socket) do
    {:ok,
     assign(
       socket,
       active?: assigns.name == assigns.params[:state],
       count: assigns.stat.count,
       name: assigns.name
     )}
  end

  def render(assigns) do
    ~L"""
    <li id="state-<%= @name %>" class="text-sm cursor-pointer outline-none" tabindex="0" phx-click="filter" phx-target="<%= @myself %>">
      <div class="flex justify-between px-3 py-3 border-l-2 border-transparent hover:bg-gray-50 <%= if @active? do %>border-blue-400<% end %>">
        <span class="font-semibold"><%= @name %></span>
        <span class="text-gray-500 text-right tabular"><%= integer_to_delimited(@count) %></span>
      </div>
    </li>
    """
  end

  def handle_event("filter", _params, socket) do
    new_state = if socket.assigns.active?, do: nil, else: socket.assigns.name

    send(self(), {:params, :state, new_state})

    {:noreply, socket}
  end
end
