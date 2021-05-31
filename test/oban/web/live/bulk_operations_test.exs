defmodule Oban.Web.Live.BulkOperationsTest do
  use Oban.Web.DataCase

  import Phoenix.LiveViewTest

  alias Oban.Web.Plugins.Stats

  setup do
    start_supervised_oban!(plugins: [Stats])

    {:ok, live, _html} = live(build_conn(), "/oban")

    {:ok, live: live}
  end

  test "cancelling selected jobs", %{live: live} do
    job_1 = insert_job!([ref: 1], state: "available", worker: WorkerA)
    _job_ = insert_job!([ref: 2], state: "available", worker: WorkerB)
    job_3 = insert_job!([ref: 3], state: "available", worker: WorkerC)

    click_state(live, "available")
    select_jobs(live, [job_1, job_3])
    click_bulk_action(live, "cancel")

    assert hidden_job?(live, job_1)
    assert hidden_job?(live, job_3)
  end

  test "deleting selected jobs", %{live: live} do
    job_1 = insert_job!([ref: 1], state: "available", worker: WorkerA)
    _job_ = insert_job!([ref: 2], state: "available", worker: WorkerB)
    job_3 = insert_job!([ref: 3], state: "available", worker: WorkerC)

    click_state(live, "available")
    select_jobs(live, [job_1, job_3])
    click_bulk_action(live, "delete")

    assert hidden_job?(live, job_1)
    assert hidden_job?(live, job_3)
  end

  defp click_state(live, state) do
    live
    |> element("#sidebar #states #state-#{state}")
    |> render_click()
  end

  defp select_jobs(live, jobs) do
    for %{id: id} <- jobs do
      live
      |> element("#listing #job-#{id} .js-toggle")
      |> render_click()
    end
  end

  defp click_bulk_action(live, action) do
    live
    |> element("#bulk-action #bulk-#{action}")
    |> render_click()
  end

  defp hidden_job?(live, %{id: id}) do
    has_element?(live, "#job-#{id}.js-hidden")
  end
end
