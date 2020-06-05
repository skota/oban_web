defmodule ObanWeb.Query do
  @moduledoc false

  import Ecto.Query

  alias Oban.Job
  alias Oban.Pro.Beat
  alias ObanWeb.Config

  @default_node "any"
  @default_queue "any"
  @default_state "executing"
  @default_limit 30
  @default_worker "any"

  @doc false
  def fetch_job(%Config{repo: repo, verbose: verbose}, job_id) do
    case repo.get(Job, job_id, log: verbose) do
      nil ->
        {:error, :not_found}

      job ->
        {:ok, relativize_timestamps(job)}
    end
  end

  @doc false
  def delete_jobs(%Config{repo: repo, verbose: verbose}, [_ | _] = job_ids) do
    Job
    |> where([j], j.id in ^job_ids)
    |> repo.delete_all(log: verbose)

    :ok
  end

  @doc false
  def deschedule_jobs(%Config{repo: repo, verbose: verbose}, [_ | _] = job_ids) do
    updates = [state: "available", completed_at: nil, discarded_at: nil]

    Job
    |> where([j], j.id in ^job_ids)
    |> repo.update_all([set: updates], log: verbose)

    :ok
  end

  @doc false
  def discard_job(%Config{repo: repo, verbose: verbose}, job_id) do
    updates = [state: "discarded", discarded_at: NaiveDateTime.utc_now()]

    Job
    |> where(id: ^job_id)
    |> repo.update_all([set: updates], log: verbose)

    :ok
  end

  @doc false
  def get_jobs(config, opts) when is_map(opts), do: get_jobs(config, Keyword.new(opts))

  def get_jobs(%Config{repo: repo, verbose: verbose}, opts) do
    node = Keyword.get(opts, :node, @default_node)
    queue = Keyword.get(opts, :queue, @default_queue)
    state = Keyword.get(opts, :state, @default_state)
    limit = Keyword.get(opts, :limit, @default_limit)
    terms = Keyword.get(opts, :terms)
    worker = Keyword.get(opts, :worker, @default_worker)

    Job
    |> filter_node(node)
    |> filter_queue(queue)
    |> filter_state(state)
    |> filter_terms(terms)
    |> filter_worker(worker)
    |> order_state(state)
    |> limit(^limit)
    |> repo.all(log: verbose)
    |> Enum.map(&relativize_timestamps/1)
  end

  defp filter_node(query, "any"), do: query

  defp filter_node(query, node) do
    where(query, [j], fragment("?[1] = ?", j.attempted_by, ^node))
  end

  defp filter_queue(query, "any"), do: query
  defp filter_queue(query, queue), do: where(query, queue: ^queue)

  defp filter_state(query, state), do: where(query, state: ^state)

  defp filter_terms(query, nil), do: query
  defp filter_terms(query, ""), do: query

  defp filter_terms(query, terms) do
    ilike = terms <> "%"

    where(
      query,
      [j],
      fragment("? ~~* ?", j.worker, ^ilike) or
        fragment("? % ?", j.worker, ^terms) or
        fragment("to_tsvector('simple', ?::text) @@ plainto_tsquery('simple', ?)", j.args, ^terms)
    )
  end

  defp filter_worker(query, "any"), do: query
  defp filter_worker(query, worker), do: where(query, worker: ^worker)

  defp order_state(query, state) when state in ~w(available retryable scheduled) do
    order_by(query, [j], asc: j.scheduled_at)
  end

  defp order_state(query, "executing") do
    order_by(query, [j], asc: j.attempted_at)
  end

  defp order_state(query, _state) do
    order_by(query, [j], desc: j.attempted_at)
  end

  # Once a job is attempted or scheduled the timestamp doesn't change. That prevents LiveView from
  # re-rendering the relative time, which makes it look like the view is broken. To work around
  # this issue we inject relative values to trigger change tracking.
  defp relativize_timestamps(%Job{} = job, now \\ NaiveDateTime.utc_now()) do
    relative = %{
      relative_attempted_at: maybe_diff(now, job.attempted_at),
      relative_completed_at: maybe_diff(now, job.completed_at),
      relative_discarded_at: maybe_diff(now, job.discarded_at),
      relative_inserted_at: maybe_diff(now, job.inserted_at),
      relative_scheduled_at: maybe_diff(now, job.scheduled_at)
    }

    Map.merge(job, relative)
  end

  defp maybe_diff(_now, nil), do: nil
  defp maybe_diff(now, then), do: NaiveDateTime.diff(then, now)

  @doc false
  def node_counts(%Config{repo: repo, verbose: verbose}, seconds \\ 60) do
    since = DateTime.add(DateTime.utc_now(), -seconds)

    subquery =
      from b in Beat,
        select: %{
          node: b.node,
          queue: b.queue,
          running: b.running,
          limit: b.limit,
          paused: b.paused,
          rank: over(rank(), :nq)
        },
        windows: [nq: [partition_by: [b.node, b.queue], order_by: [desc: b.inserted_at]]],
        where: b.inserted_at > ^since

    query =
      from x in subquery(subquery),
        where: x.rank == 1,
        select: {
          x.node,
          x.queue,
          fragment("coalesce(array_length(?, 1), 0)", x.running),
          x.limit,
          x.paused
        }

    repo.all(query, log: verbose)
  end

  @doc false
  def queue_counts(%Config{repo: repo, verbose: verbose}) do
    Job
    |> group_by([j], [j.queue, j.state])
    |> select([j], {j.queue, j.state, count(j.id)})
    |> repo.all(log: verbose)
  end
end
