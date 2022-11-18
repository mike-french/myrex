defmodule Myrex do
  @moduledoc """
  A regular expression matcher...
  """

  alias Myrex.Types, as: T

  alias Myrex.Compiler
  alias Myrex.Executor
  alias Myrex.NFA.Start

  @doc """
  Compile a regular expression to an NFA process network for batch processing.

  Return the builder process, which owns all the NFA processes (links),
  and is also the start input process for initiating traversals.
  """
  @spec compile(T.regex(), T.options()) :: pid()
  def compile(re, opts \\ []) do
    gname =
      case Keyword.get(opts, :graph_name, nil) do
        nil -> nil
        :re -> re
        str when is_binary(str) -> str
      end

    Start.init(fn -> Compiler.compile(re, opts) end, gname)
  end

  @doc """
  Tear down a compiled NFA process network at the end of batch processing.

  The PID argument must be the `Start` process for the NFA,
  as returned from the `Start.init` function.
  """
  @spec teardown(any()) :: :ok
  def teardown(maybe_pid) do
    Start.teardown(maybe_pid)
  end

  @doc """
  Search for a regular expression pattern in an input string.

  Search with an RE for a single result is equivalent to wrapping
  the regex with the wildcard expression `.*`. 
  For example, `"abc" ~> ".*abc.*"`.

  Oneshot search just wraps the regex with the wildcard, 
  compiles the NFA and runs a normal `match`.

  Batch search applies a pair of _zero or more_ process combinators
  to the existing NFA, then runs the wrapped process network.
  """
  @spec search(String.t() | pid(), String.t(), Keyword.t()) :: T.result()

  def search(re, str, opts \\ [])

  def search(re, str, opts) when is_binary(re) and is_binary(str) and is_list(opts) do
    # oneshot execution
    # the executor will compile, run and teardown the NFA process network
    Process.flag(:trap_exit, true)
    Executor.init_oneshot(".*" <> re <> ".*", str, opts)
    do_match(str, opts)
  end

  def search(start, str, opts) when is_pid(start) and is_binary(str) and is_list(opts) do
    # TODO ...
    Process.flag(:trap_exit, true)
    Executor.init_search(start, str, opts)
    do_match(str, opts)
  end

  @doc """
  Apply a regular expression to a string argument. 

  The first argument can be either a regular expression string,
  or the start process address of a compiled NFA process network.

  If a regular expression is passed as a string argument, 
  it is compiled to a one-shot NFA process network, 
  which is torn down after the string match has completed.
  The options passed for one-shot execution
  affect both the compile-time and run-time behaviour.

  If a compiled NFA is passed as a process argument,
  the options passed for batch execution
  only affect the runtime behaviour (`:return` type).
  """
  @spec match(String.t() | pid(), String.t(), Keyword.t()) :: T.result()

  def match(re, str, opts \\ [])

  def match(re, str, opts) when is_binary(re) and is_binary(str) and is_list(opts) do
    # oneshot execution
    # the executor will compile, run and teardown the NFA process network
    Process.flag(:trap_exit, true)
    Executor.init_oneshot(re, str, opts)
    do_match(str, opts)
  end

  def match(start, str, opts) when is_pid(start) and is_binary(str) and is_list(opts) do
    Process.flag(:trap_exit, true)
    Executor.init_batch(start, str, opts)
    do_match(str, opts)
  end

  @spec do_match(String.t(), T.options()) :: no_return()
  defp do_match(str, opts, matches \\ []) do
    # Add the whole string capture to the result, not in traverse call,
    # so it does not need to be copied through every traversal.
    # Ignore options, and add it as a string (binary) 
    # not just an index reference {0,length}
    # so the input is always available in the result.

    # TODO - only handle return type flag here?
    # captures should be compiled into the group and success processes?
    # what is the difference between compile-time and run-time options?

    receive do
      :end_matches ->
        {:matches, matches}

      :no_match ->
        {:no_match, %{0 => str}}

      {:match, caps} ->
        capopt = Keyword.get(opts, :capture, :all)
        return = Keyword.get(opts, :return, :index)
        multi = Keyword.get(opts, :multiple, :first)

        caps =
          case {capopt, return} do
            {:none, _} -> %{}
            {:all, :index} -> caps
            {:all, :binary} -> cap2str(Map.keys(caps), str, caps)
            {names, :index} when is_list(names) -> Map.take(caps, names)
            {names, :binary} when is_list(names) -> cap2str(names, str, Map.take(caps, names))
          end

        caps = Map.put(caps, 0, str)

        case multi do
          :first -> {:match, caps}
          :all -> do_match(str, opts, [caps | matches])
        end

      {:EXIT, _, :normal} ->
        do_match(str, opts, matches)

      {:EXIT, _, reason} ->
        raise RuntimeError, message: "Execution failed: #{inspect(reason)}"

      msg ->
        raise RuntimeError, message: "Unhandled message #{inspect(msg)}"
    end
  end

  # get group substrings from capture indexes
  @spec cap2str([T.capture_name()], String.t(), T.captures()) :: T.captures()

  defp cap2str([name | names], str, caps) do
    substr =
      case Map.get(caps, name, :no_capture) do
        :no_capture -> :no_capture
        {pos, len} -> String.slice(str, pos, len)
        # pass through index 0 which is always whole string
        str when is_binary(str) -> str
      end

    cap2str(names, str, %{caps | name => substr})
  end

  defp cap2str([], _, caps), do: caps
end
