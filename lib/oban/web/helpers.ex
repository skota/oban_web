defmodule Oban.Web.Helpers do
  @moduledoc false

  alias Oban.Job
  alias Oban.Web.{AccessError, Resolver, Timing}
  alias Phoenix.VerifiedRoutes

  # Routing Helpers

  @doc """
  Construct a path to a dashboard page with optional params.

  Routing is based on a socket and prefix tuple stored in the process dictionary. Proper routing
  can be disabled for testing by setting the value to `:nowhere`.
  """
  def oban_path(route, params \\ %{})

  def oban_path(route, params) when is_list(route) do
    route
    |> Enum.join("/")
    |> oban_path(params)
  end

  def oban_path(route, params) do
    params =
      params
      |> Enum.reject(fn {_, val} -> is_nil(val) or val == "" end)
      |> Map.new(fn
        {key, [_ | _] = val} -> {key, Enum.join(val, ",")}
        {key, val} -> {key, val}
      end)

    case Process.get(:routing) do
      {socket, prefix} ->
        VerifiedRoutes.unverified_path(socket, socket.router, "#{prefix}/#{route}", params)

      :nowhere ->
        "/"

      nil ->
        raise RuntimeError, "nothing stored in the :routing key"
    end
  end

  @doc """
  Construct a map without any default values included.
  """
  def without_defaults(%_params{}, _defaults), do: %{}

  def without_defaults(params, defaults) do
    params
    |> Enum.reject(fn {key, val} -> val == defaults[key] end)
    |> Map.new()
  end

  # Title Helpers

  def page_title(%Job{id: id, worker: worker}), do: page_title("#{worker} (#{id})")
  def page_title(prefix), do: "#{prefix} • Oban"

  # Authorization Helpers

  @doc """
  Check an action against the current access controls.
  """
  @spec can?(Resolver.access(), atom() | keyword()) :: boolean()
  def can?(_action, :all), do: true
  def can?(_action, :read_only), do: false
  def can?(action, [_ | _] = opts), do: Keyword.get(opts, action, false)

  @doc """
  Enforce access by raising an error if access isn't allowed.
  """
  @spec enforce_access!(Resolver.access(), atom() | keyword()) :: :ok
  def enforce_access!(action, opts) do
    unless can?(action, opts), do: raise(AccessError)

    :ok
  end

  # Formatting Helpers

  @doc """
  Delimit large integers with a comma separator.
  """
  @spec integer_to_delimited(integer()) :: String.t()
  def integer_to_delimited(integer) when is_integer(integer) do
    integer
    |> Integer.to_charlist()
    |> Enum.reverse()
    |> Enum.chunk_every(3, 3, [])
    |> Enum.join(",")
    |> String.reverse()
  end

  @doc """
  Truncate strings beyond a fixed limit and append an ellipsis.
  """
  @spec truncate(String.t(), Range.t()) :: String.t()
  def truncate(string, range \\ 0..90) do
    if String.length(string) > Enum.max(range) do
      String.slice(string, range) <> "…"
    else
      string
    end
  end

  @doc """
  Select an absolute timestamp appropriate for the provided state and format it.
  """
  @spec absolute_time(String.t(), Job.t()) :: String.t()
  def absolute_time(state, job) do
    case state do
      "available" -> "Available At: #{truncate_sec(job.scheduled_at)}"
      "cancelled" -> "Cancelled At: #{truncate_sec(job.cancelled_at)}"
      "completed" -> "Completed At: #{truncate_sec(job.completed_at)}"
      "discarded" -> "Discarded At: #{truncate_sec(job.discarded_at)}"
      "executing" -> "Attempted At: #{truncate_sec(job.attempted_at)}"
      "retryable" -> "Retryable At: #{truncate_sec(job.scheduled_at)}"
      "scheduled" -> "Scheduled At: #{truncate_sec(job.scheduled_at)}"
    end
  end

  defp truncate_sec(datetime), do: NaiveDateTime.truncate(datetime, :second)

  @doc """
  Select a duration or distance in words based on the provided state.
  """
  @spec relative_time(String.t(), Job.t()) :: String.t()
  def relative_time(state, job) do
    case state do
      "cancelled" -> Timing.to_words(job.relative_cancelled_at)
      "completed" -> Timing.to_words(job.relative_completed_at)
      "discarded" -> Timing.to_words(job.relative_discarded_at)
      "executing" -> Timing.to_duration(job.relative_attempted_at)
      _ -> Timing.to_words(job.relative_scheduled_at)
    end
  end

  @doc """
  Convert a stringified timestamp (i.e. from an error) into a relative time.
  """
  def iso8601_to_words(iso8601, now \\ NaiveDateTime.utc_now()) do
    {:ok, datetime} = NaiveDateTime.from_iso8601(iso8601)

    datetime
    |> NaiveDateTime.diff(now)
    |> Timing.to_words()
  end

  @doc """
  Round numbers to human readable values with a scale suffix.
  """
  def integer_to_estimate(nil), do: "0"

  def integer_to_estimate(number) when number < 1000, do: to_string(number)

  def integer_to_estimate(number) when number < 10_000 do
    power = 3
    mult = Integer.pow(10, power)
    base = floor(number / mult)
    part = round(rem(number, mult) / Integer.pow(10, power - 1))

    case part do
      0 -> "#{base}k"
      10 -> "#{base + 1}k"
      _ -> "#{base}.#{part}k"
    end
  end

  def integer_to_estimate(number) when is_integer(number) do
    {power, suffix} =
      cond do
        number < 1_000_000 -> {3, "k"}
        number < 1_000_000_000 -> {6, "m"}
        true -> {9, "b"}
      end

    mult = Integer.pow(10, power)
    base = round(number / mult)

    "#{base}#{suffix}"
  end

  @doc """
  Extract the name of the node that attempted a job.
  """
  def attempted_by(%Job{attempted_by: [node | _]}), do: node
  def attempted_by(%Job{}), do: "Not Attempted"

  @doc """
  Format job tags using a delimiter.
  """
  def formatted_tags(%Job{tags: []}), do: "..."
  def formatted_tags(%Job{tags: tags}), do: Enum.join(tags, ", ")

  @doc """
  A normalized, globally unique combination of instance and node names.
  """
  def node_name(%{"node" => node, "name" => name}), do: node_name(node, name)

  def node_name(node, name) do
    [node, name]
    |> Enum.join("/")
    |> String.trim_leading("Elixir.")
    |> String.downcase()
  end

  # State Helpers

  @doc """
  Whether the job can be cancelled in its current state.
  """
  @spec cancelable?(Job.t()) :: boolean()
  def cancelable?(%Job{state: state}) do
    state in ~w(inserted scheduled available executing retryable)
  end

  @doc """
  Whether the job can be ran immediately in its current state.
  """
  @spec runnable?(Job.t()) :: boolean()
  def runnable?(%Job{state: state}) do
    state in ~w(inserted scheduled)
  end

  @doc """
  Whether the job can be retried in its current state.
  """
  @spec retryable?(Job.t()) :: boolean()
  def retryable?(%Job{state: state}) do
    state in ~w(completed retryable discarded cancelled)
  end

  @doc """
  Whether the job can be deleted in its current state.
  """
  @spec deletable?(Job.t()) :: boolean()
  def deletable?(%Job{state: state}), do: state != "executing"

  @doc """
  Whether the job was left in an executing state when the node or producer running it shut down.

  # TODO: This isn't accurate enough. We need to use the UUIDs from all nodes.
  """
  def orphaned?(%Job{} = job, %MapSet{} = nodes) do
    case {job.state, job.attempted_by} do
      {"executing", [node | _]} -> not MapSet.member?(nodes, node)
      _ -> false
    end
  end
end
