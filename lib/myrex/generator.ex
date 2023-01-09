defmodule Myrex.Generator do
  @moduledoc """
  The generator for creating a string from a regular expression.
  The generator manages the execution of the NFA
  and collects the result.
  """

  import Myrex.Types
  alias Myrex.Types, as: T

  alias Myrex.Compiler
  # alias Myrex.NFA
  alias Myrex.NFA.Start
  alias Myrex.Proc.Proc

  # @doc """
  # Initialize a batch matching operation. 
  # The client to receive results is the calling process (self).
  # The NFA is owned by a separate builder process.
  # """

  # @spec init_batch(pid(), String.t(), T.options()) :: pid()
  # def init_batch(start, str, opts) when is_pid(start) and is_binary(str) and is_list(opts) do
  #   # don't pass start nfa for teardown
  #   spawn_link(__MODULE__, :exec, [nil, start, str, opts, self()])
  # end

  @doc """
  Initialize a one-shot generating operation. 
  The client to receive results is the calling process (self).
  The NFA is owned by this executor process.
  """
  @spec init_oneshot(T.regex(), T.options()) :: pid()
  def init_oneshot(re, opts) when is_binary(re) and is_list(opts) do
    start = Start.init({fn -> Compiler.compile(re, opts) end, nil})
    # pass the start nfa for prompt teardown
    spawn_link(__MODULE__, :exec, [start, start, opts, self()])
  end

  # entry point for running the generator to look up configuration options
  @spec exec(nil | pid(), pid(), T.options(), pid()) :: no_return()
  def exec(teardown, start, opts, client) do
    timeout = Keyword.get(opts, :timeout, T.default(:timeout))
    multiple = Keyword.get(opts, :multiple, T.default(:multiple))
    Proc.traverse(start, {:generate, "", nil, self()})
    generate(client, teardown, timeout, multiple)
  end

  @doc """
  # Monitor matching of the input string to the regular expression.
  # The function is a blocking synchronous loop
  # that will wait until a result is determined.

  # The integer argument is the number of traversals
  # currently within the NFA network.
  # The count of traversals is incremented by `Split` processes
  # that implement quantifiers and alternate choices.
  # The count is decremented by failed matches.

  # If the `:multiple` flag is `:one`, then
  # the first successful match to complete execution
  # will return a `:match` result and the `Executor` will exit normally.
  # The `:one` match is not necessarily the first in order in the input string.

  # If the `:multiple` flag is `:all`, 
  # the `Executor` will collect all successful matches.
  # When all the traversals finish, 
  # the `Executor` will return all matches and exit normally.

  # If all traversals finish with no successful match,
  # then a `:no_match` result is reported, 
  # and the `Executor` exits normally.

  # After a result is returned, the `Executor` exits normally.
  # If a one-shot NFA or search prefix subgraph NFA was built by the `Executor`,
  # then all those linked NFA processes will be killed.
  """
  @spec generate(pid(), nil | pid(), timeout(), T.multiple_flag()) :: no_return()

  def generate(client, nfa, timeout, _multi) do
    receive do
      {:generate, _str} = result ->
        notify_result(client, result)

        # for a one-shot execution, with all NFA processes linked to this one
        # exiting after the first match will kill the NFA process network
        Start.teardown(nfa)
        exit(:normal)

      msg ->
        raise RuntimeError, message: "Unhandled message #{inspect(msg)}"
    after
      timeout -> raise RuntimeError, message: "Executor timeout"
    end
  end

  @doc "Send a generated result to a generator or client."
  @spec notify_result(pid(), T.generate_result()) :: any()
  def notify_result(gen, result) when is_pid(gen) and is_gen_result(result), do: send(gen, result)
end
