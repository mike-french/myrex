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
  @spec init() :: pid()
  def init(), do: spawn(__MODULE__, :attach, [])

  @doc """
  Wait for attach message from the client process for reporting results.
  """
  @spec attach() :: no_return()
  def attach() do
    receive do
      client when is_pid(client) -> match(1, client, :no_match)
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
  @spec match(T.count(), pid(), T.result()) :: no_return()

  def match(0, client, :no_match) do
    # only report when all traversals finished?
    # send(client, result)
    send(client, :no_match)
    exit(:normal)
  end

  def match(n, client, result) when is_count(n) and is_pid(client) do
    receive do
      m when is_count(m) ->
        # split fan-out increases number of traversals 
        match(n + m, client, result)

      :no_match ->
        # failure reduces number of traversals
        # no_match does not overwrite existing success
        match(n - 1, client, result)

      {:match, _} = success ->
        # assume first match is the only successful match
        # short circuit report to client  
        send(client, success)
        # success reduces number of traversals 
        # exit / kill processes or wait for remaining traversals?
        match(n - 1, client, success)
    end
  end
end
