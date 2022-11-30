defmodule Myrex.Executor do
  @moduledoc """
  The executor for matching a regular expression.
  The executor manages the execution of the NFA
  and collects the result.
  """

  import Myrex.Types
  alias Myrex.Types, as: T

  alias Myrex.Compiler
  alias Myrex.NFA
  alias Myrex.NFA.Proc
  alias Myrex.NFA.Start

  @doc """
  Initialize a batch matching operation. 
  The client to receive results is the calling process (self).
  The NFA is owned by a separate builder process.
  """
  @spec init_batch(pid(), String.t(), T.options()) :: pid()
  def init_batch(start, str, opts) when is_pid(start) and is_binary(str) and is_list(opts) do
    # don't pass start nfa for teardown
    spawn_link(__MODULE__, :exec, [nil, start, str, opts, self()])
  end

  @doc """
  Initialize a one-shot matching operation. 
  The client to receive results is the calling process (self).
  The NFA is owned by this executor process.
  """
  @spec init_oneshot(T.regex(), String.t(), T.options()) :: pid()
  def init_oneshot(re, str, opts) when is_binary(re) and is_binary(str) and is_list(opts) do
    # no graph output for oneshot execution
    start = Start.init(fn -> Compiler.compile(re, opts) end, nil)
    # pass the start nfa for prompt teardown
    spawn_link(__MODULE__, :exec, [start, start, str, opts, self()])
  end

  @doc """
  Initialize a batch search matching operation. 

  The client to receive results is the calling process (self).
  The existing NFA is owned by a separate builder process (Start).

  Create a new prefix subgraph to implement zero or more any char wildcards.
  Connect the prefix subgraph to the existing NFA.
  Return the new Start process for the prefix subgraph. 
  The client should initiate traversal through the new Start process.
  The executor will tear down the prefix subgraph when the search completes.
  The existing NFA process network is unaffected by the search operation.
  """
  @spec init_search(pid(), String.t(), T.options()) :: pid()
  def init_search(nfa, str, opts) when is_pid(nfa) and is_binary(str) and is_list(opts) do
    # build a prefix subgraph for '.*' linked to a new Start process
    # the executor will teardown the prefix Start process at the end of the search
    dotall? = Keyword.get(opts, :dotall, T.default(:dotall))
    prefix = Start.init(fn -> nfa |> NFA.search(dotall?) |> Proc.input() end, nil)
    # pass prefix nfa subgraph for teardown, not the original NFA
    spawn_link(__MODULE__, :exec, [prefix, prefix, str, opts, self()])
  end

  # entry point for running the executor to look up configuration options
  @spec exec(nil | pid(), pid(), String.t(), T.options(), pid()) :: no_return()
  def exec(teardown, start, str, opts, client) do
    timeout = Keyword.get(opts, :timeout, T.default(:timeout))
    multiple = Keyword.get(opts, :multiple, T.default(:multiple))
    offset = Keyword.get(opts, :offset, 0)
    str = if offset > 0, do: String.slice(str, offset, String.length(str) - offset), else: str
    Proc.traverse(start, {str, offset, [], %{}, self()})
    execute(1, client, teardown, timeout, multiple, :no_match)
  end

  @doc """
  Monitor matching of the input string to the regular expression.
  The function is a blocking synchronous loop
  that will wait until a result is determined.

  The integer argument is the number of traversals
  currently within the NFA network.
  The count of traversals is incremented by `Split` processes
  that implement quantifiers and alternate choices.
  The count is decremented by failed matches.

  If the `:multiple` flag is `:one`, then
  the first successful match to complete execution
  will return a `:match` result and the `Executor` will exit normally.
  The `:one` match is not necessarily the first in order in the input string.

  If the `:multiple` flag is `:all`, 
  the `Executor` will collect all successful matches.
  When all the traversals finish, 
  the `Executor` will return all matches and exit normally.

  If all traversals finish with no successful match,
  then a `:no_match` result is reported, 
  and the `Executor` exits normally.

  After a result is returned, the `Executor` exits normally.
  If a one-shot NFA or search prefix subgraph NFA was built by the `Executor`,
  then all those linked NFA processes will be killed.
  """
  @spec execute(
          T.count(),
          pid(),
          nil | pid(),
          timeout(),
          T.multiple_flag(),
          :no_match | :match | :search
        ) ::
          no_return()

  def execute(0, client, nfa, _timeout, _multi, result_type) do
    notify_result(client, result_type)
    Start.teardown(nfa)
    exit(:normal)
  end

  def execute(n, client, nfa, timeout, multi, result_type) when is_count1(n) do
    receive do
      delta when is_count(delta) ->
        # split fan-out increases number of traversals
        execute(n + delta, client, nfa, timeout, multi, result_type)

      :no_match ->
        # failure reduces number of traversals
        execute(n - 1, client, nfa, timeout, multi, result_type)

      success when is_tuple(success) ->
        # success at end of input
        notify_result(client, success)

        # for a one-shot execution, with all NFA processes linked to this one
        # exiting after the first match will kill the NFA process network
        if multi == :one do
          Start.teardown(nfa)
          exit(:normal)
        end

        # success reduces number of traversals
        # and forces current result type to :match or :search
        execute(n - 1, client, nfa, timeout, multi, elem(success, 0))

      msg ->
        raise RuntimeError, message: "Unhandled message #{inspect(msg)}"
    after
      timeout -> raise RuntimeError, message: "Executor timeout"
    end
  end

  @doc "Send a match result to an executor or client."
  @spec notify_result(
          pid(),
          :no_match
          | :match
          | :search
          | T.match_result()
          | T.search_result()
        ) ::
          any()
  def notify_result(exec, result) when is_pid(exec), do: send(exec, result)
end
