defmodule Myrex.Executor do
  @moduledoc """
  The executor for matching a regular expression.
  The executor manages the execution of the NFA
  and collects the result.
  """
  import Myrex.Types
  alias Myrex.Types, as: T

  alias Myrex.Compiler
  alias Myrex.NFA.Proc
  alias Myrex.NFA.Start

  @default_timeout 1_000
  @default_multiple :first

  @doc """
  Initialize a batch matching operation. 
  The client to receive results is the calling process (self).
  The NFA is owned by a separate builder process.
  The client should initiate traversal through the NFA builder process.
  """
  @spec init_batch(pid(), String.t(), T.options()) :: pid()
  def init_batch(nfa, str, opts) when is_pid(nfa) and is_binary(str) and is_list(opts) do
    # don't pass nfa for teardown
    executor = spawn_link(__MODULE__, :exec, [nil, opts, self()])
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
    executor = spawn_link(__MODULE__, :exec, [nfa, opts, self()])
    Proc.traverse(nfa, {str, 0, [], %{}, executor})
    executor
  end

  @doc """
  Initialize a batch search matching operation. 
  The client to receive results is the calling process (self).
  The NFA is owned by a separate builder process.
  The client should initiate traversal through the NFA builder process.
  """
  @spec init_search(pid(), String.t(), T.options()) :: pid()
  def init_search(nfa, str, opts) when is_pid(nfa) and is_binary(str) and is_list(opts) do
    # TODO *******************************************************
    # don't pass nfa for teardown
    executor = spawn_link(__MODULE__, :exec, [nil, opts, self()])
    Proc.traverse(nfa, {str, 0, [], %{}, executor})
    executor
  end

  @spec exec(T.maybe(pid()), T.options(), pid()) :: no_return()
  def exec(nfa, opts, client) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    multiple = Keyword.get(opts, :multiple, @default_multiple)
    execute(1, client, nfa, timeout, multiple, :no_match)
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
          timeout(),
          T.multiple_flag(),
          :match | :no_match
        ) ::
          no_return()

  def execute(0, client, nfa, _timeout, _multiple_flag, :no_match) do
    notify_result(client, :no_match)
    Start.teardown(nfa)
    exit(:normal)
  end

  def execute(0, client, nfa, _timeout, _multiple_flag, :match) do
    # previous successful matches have been sent
    notify_result(client, :end_matches)
    Start.teardown(nfa)
    exit(:normal)
  end

  def execute(n, client, nfa, timeout, multiple_flag, result_type) when is_count1(n) do
    receive do
      delta when is_count(delta) ->
        # split fan-out increases number of traversals 
        execute(n + delta, client, nfa, timeout, multiple_flag, result_type)

      :no_match ->
        # failure reduces number of traversals
        execute(n - 1, client, nfa, timeout, multiple_flag, result_type)

      {:match, _} = success ->
        notify_result(client, success)
        # for a one-shot execution, with all NFA processes linked to this one
        # exiting after the first match will kill the NFA process network
        if multiple_flag == :first do
          Start.teardown(nfa)
          exit(:normal)
        end

        # success reduces number of traversals
        # and forces current result to be a match
        execute(n - 1, client, nfa, timeout, multiple_flag, :match)

      msg ->
        raise RuntimeError, message: "Unhandled message #{inspect(msg)}"
    after
      timeout -> raise RuntimeError, message: "Executor timeout"
    end
  end

  @doc "Send a match result to an executor or client."
  @spec notify_result(pid(), :no_match | :end_matches | T.result()) :: any()
  def notify_result(exec, result) when is_pid(exec), do: send(exec, result)
end
