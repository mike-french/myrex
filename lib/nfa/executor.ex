defmodule Myrex.NFA.Executor do
  @moduledoc """
  The start node for matching a regular expression.
  The executor also manages the execution of the NFA
  and collects the result.

  Future types of executor may also build and tear down the NFA network.
  For example, successful result and exit may kill linked NFA processes.
  """
  import Myrex.Types
  alias Myrex.Types, as: T

  @doc "Initialize a traversal."
  @spec init(timeout()) :: pid()
  def init(timeout), do: spawn_link(__MODULE__, :attach, [timeout])

  @doc """
  Wait for attach message from the client process for reporting results.
  """
  @spec attach(timeout()) :: no_return()
  def attach(timeout) do
    receive do
      {:attach, client} when is_pid(client) -> match(1, client, timeout)
      msg -> raise RuntimeError, message: "Unhandled message #{inspect(msg)}"
    end
  end

  @doc """
  Match the input string to the regular expression.

  The integer argument is the number of traversals
  currently within the NFA network.

  The result argument is the current status of the match result.
  The default is `:no_match`. One match will flip this to success.

  In principle, the result could be returned at that point,
  and the NFA network torn down, 
  but in this executor, we continue to collect further results
  until all traversals are completed. 
  In this way, a single NFA network can be used to process multiple inputs concurrently.
  """
  @spec match(T.count(), pid(), timeout()) :: no_return()

  def match(0, client, _timeout) do
    notify_result(client, :no_match)
    exit(:normal)
  end

  def match(n, client, timeout) when is_count1(n) do
    receive do
      delta when is_count(delta) ->
        # split fan-out increases number of traversals 
        match(n + delta, client, timeout)

      :no_match ->
        # failure reduces number of traversals
        match(n - 1, client, timeout)

      {:match, _} = success ->
        # assume first match is the only successful match
        notify_result(client, success)
        exit(:normal)

      msg ->
        raise RuntimeError, message: "Unhandled message #{inspect(msg)}"
    after
      timeout -> raise RuntimeError, message: "Executor timeout"
    end
  end

  @doc "Notify the executor that the number of traversals has increased."
  @spec add_traversals(pid(), T.count()) :: any()
  def add_traversals(exec, m) when is_pid(exec) and is_count(m), do: send(exec, m)

  @doc "Send a match result to an executor or client."
  @spec notify_result(pid(), T.result()) :: any()
  def notify_result(exec, result) when is_pid(exec) and is_result(result), do: send(exec, result)
end
