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

  @default_timeout 1_000
  @default_multiple :first
  @default_dotall false

  @doc """
  Initialize a batch matching operation. 
  The client to receive results is the calling process (self).
  The NFA is owned by a separate builder process.
  The client should initiate traversal through the NFA builder process.
  """
  @spec init_batch(pid(), String.t(), T.options()) :: pid()
  def init_batch(nfa, str, opts) when is_pid(nfa) and is_binary(str) and is_list(opts) do
    # don't pass nfa for teardown
    executor = spawn_link(__MODULE__, :exec, [nil, :mode_match, opts, self()])
    Proc.traverse(nfa, {str, 0, [], %{}, executor})
    executor
  end

  @doc """
  Initialize a one-shot matching operation. 
  The client to receive results is the calling process (self).
  The NFA is owned by this executor process.
  The traversal will be initiated in the new executor process.
  """
  @spec init_oneshot(T.regex(), String.t(), T.options()) :: pid()
  def init_oneshot(re, str, opts) when is_binary(re) and is_binary(str) and is_list(opts) do
    # no graph output for oneshot execution
    nfa = Start.init(fn -> Compiler.compile(re, opts) end, nil)
    # pass the nfa for prompt teardown
    executor = spawn_link(__MODULE__, :exec, [nfa, :mode_match, opts, self()])
    Proc.traverse(nfa, {str, 0, [], %{}, executor})
    executor
  end

  @doc """
  Initialize a batch search matching operation. 
  The client to receive results is the calling process (self).
  The existing NFA is owned by a separate builder process (Start).
  Create a new prefix subgraph to implement zero or more wildcard for any character.
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
    dotall? = Keyword.get(opts, :dotall, @default_dotall)
    prefixed_nfa = Start.init(fn -> nfa |> NFA.search(dotall?) |> Proc.input() end, nil)
    # pass prefix nfa subgraph for teardown, but not the original NFA
    executor = spawn_link(__MODULE__, :exec, [prefixed_nfa, :mode_search, opts, self()])
    Proc.traverse(prefixed_nfa, {str, 0, [], %{}, executor})
    executor
  end

  @spec exec(T.maybe(pid()), T.mode(), T.options(), pid()) :: no_return()
  def exec(nfa, mode, opts, client) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    multiple = Keyword.get(opts, :multiple, @default_multiple)
    execute(1, client, nfa, mode, timeout, multiple, :no_match)
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

  If the `:multiple` flag is `:first`, then
  the first successful match will return a `:match` result
  and the `Executor` will exit normally.

  If the `:multiple` flag is `:all`, then
  the first successful match will return a `:match` result
  and the `Executor` will continue to report further successful matches.
  When all the traversals finish, the `Executor` will exit normally.

  If all traversals finish with no successful match,
  then a `:no_match` result is reported, 
  and the `Executor` exits normally.

  After a result is returned, the `Executor` exits normally.
  If a one-shot NFA process network was built by the `Executor`,
  then all the linked NFA processes will be killed.
  """
  @spec execute(
          T.count(),
          pid(),
          T.maybe(pid()),
          T.mode(),
          timeout(),
          T.multi(),
          :match | :no_match | :search
        ) ::
          no_return()

  def execute(0, client, nfa, _mode, _timeout, _multi, result_type) do
    notify_result(client, result_type)
    Start.teardown(nfa)
    exit(:normal)
  end

  def execute(n, client, nfa, mode, timeout, multi, result_type) when is_count1(n) do
    receive do
      delta when is_count(delta) ->
        # split fan-out increases number of traversals 
        execute(n + delta, client, nfa, mode, timeout, multi, result_type)

      :no_match ->
        IO.inspect({n, mode}, label: "Exec: no match in mode")
        # failure reduces number of traversals
        execute(n - 1, client, nfa, mode, timeout, multi, result_type)

      {:match, _} = success when mode == :mode_match ->
        notify_result(client, success)
        # for a one-shot execution, with all NFA processes linked to this one
        # exiting after the first match will kill the NFA process network
        if multi == :first do
          Start.teardown(nfa)
          exit(:normal)
        end

        # success reduces number of traversals
        # and forces current result to be a match
        execute(n - 1, client, nfa, mode, timeout, multi, :end_matches)

      {:search, _index, _caps} = success when mode == :mode_search ->
        # search success at end of input
        IO.inspect(inspect(success), label: "Exec: match in search mode")
        notify_result(client, success)
        # for a batch search, only the prefix wildcard subgraph is linked
        # so the main compiled nfa will survive the exit
        if multi == :first do
          Start.teardown(nfa)
          exit(:normal)
        end

        # success reduces number of traversals
        # and forces current result to be a search
        execute(n - 1, client, nfa, mode, timeout, multi, :end_searches)

      {:partial_search, index, {str, pos, _, captures, _exec}} = msg when mode == :mode_search ->
        # search success but not at end of input
        IO.inspect(inspect(msg), label: "Exec: partial match in search mode, continue ...")
        notify_result(client, {:search, index, captures})
        # for a batch search, only the prefix wildcard subgraph is linked
        # so the main compiled nfa will survive the exit
        if multi == :first do
          Start.teardown(nfa)
          exit(:normal)
        end

        # in search all mode, partial match injects a new traversal
        Proc.traverse(nfa, {str, pos, [], %{}, self()})
        # the total number of traversals stays the same
        execute(n, client, nfa, mode, timeout, multi, :end_searches)

      msg ->
        raise RuntimeError, message: "Unhandled message #{inspect(msg)}"
    after
      timeout -> raise RuntimeError, message: "Executor timeout"
    end
  end

  @doc "Send a match result to an executor or client."
  @spec notify_result(pid(), :no_match | :end_matches | {:partial_match, T.state()} | T.result()) ::
          any()
  def notify_result(exec, result) when is_pid(exec), do: send(exec, result)
end
