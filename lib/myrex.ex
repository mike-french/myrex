defmodule Myrex do
  @moduledoc """
  A regular expression matcher.
  """

  import Myrex.Types
  alias Myrex.Types, as: T

  alias Myrex.Compiler
  alias Myrex.Executor
  alias Myrex.Generator
  alias Myrex.NFA.Start

  @doc """
  Compile a regular expression to an NFA process network for batch processing.

  Return the builder process, which owns all the NFA processes (links),
  and is also the start input process for initiating traversals.
  """
  @spec compile(T.regex(), T.options()) :: pid()
  def compile(re, opts \\ []) do
    validate_options(opts)

    gname =
      case Keyword.get(opts, :graph_name, nil) do
        nil -> nil
        :re -> re
        str when is_binary(str) -> str
      end

    Start.init({fn -> Compiler.compile(re, opts) end, gname})
  end

  @doc """
  Tear down a compiled NFA process network at the end of batch processing.

  The PID argument must be the `Start` process for the NFA,
  as returned from the `compile` function.
  """
  @spec teardown(any()) :: :ignore | :teardown
  def teardown(maybe_pid) do
    Start.teardown(maybe_pid)
  end

  @doc """
  Generate an example string for a regular expression.

  # The first argument can be either a regular expression string,
  # or the start process address of a compiled NFA process network.

  # If the `:multiple` option is `:one`, 
  # then the first match to complete is returned with a `:match` result tuple.
  #   If the `:multiple` option is `:all`, 
  # then all matches are returned with a `:matches` result tuple.

  # If a regular expression is passed as a string argument, 
  # it is compiled to a one-shot NFA process network, 
  # which is torn down after the string match has completed.
  # The options passed affect both the compile-time and run-time behaviour.

  # If a compiled NFA is passed as a process argument,
  # the options passed for batch execution
  # only affect the runtime behaviour.
  """
  @spec generate(String.t() | pid(), Keyword.t()) :: String.t()

  def generate(re, opts \\ [])

  def generate(re, opts) when is_binary(re) and is_list(opts) do
    # oneshot execution
    # the generator will compile, run and teardown the NFA process network
    validate_options(opts)
    Process.flag(:trap_exit, true)
    Generator.init_oneshot(re, opts)
    do_gen(opts)
  end

  @spec do_gen(T.options()) :: no_return()
  defp do_gen(opts) do
    receive do
      {:generate, str} -> str
      {:EXIT, _, :normal} -> do_gen(opts)
      {:EXIT, _, reason} -> raise RuntimeError, message: "Execution failed: #{inspect(reason)}"
      msg -> raise RuntimeError, message: "Unhandled message #{inspect(msg)}"
    end
  end

  @doc """
  Search for a regular expression pattern in an input string.

    The first argument can be either a regular expression string,
  or the start process address of a compiled NFA process network.

  If the `:multiple` option is `:one`, 
  then the first match to complete is returned with a `:search` result tuple.
    If the `:multiple` option is `:all`, 
  then all matches are returned with a `:searches` result tuple.

  Search with a REGEX for one result is equivalent to wrapping
  the regex with the wildcard expression `.*`. 
  For example, `"abc" ~> ".*abc.*"`.

  Oneshot search just wraps the regex with the wildcard, 
  compiles the NFA and runs a normal `match`.

  Batch search applies a process combinator
  to build a `.*` prefix subgraph for the existing NFA.
  If the  `:multiple` option is `:all`, 
  then execution is restarted after the first match,
  and continues to be repeated until the end of the string.
  The prefix subgraph is torn down at the end of the operation,
  but the original NFA is not affected.
  """
  @spec search(T.regex() | pid(), String.t(), Keyword.t()) :: T.search_result()

  def search(re, str, opts \\ [])

  def search(re, str, opts) when is_binary(re) and is_binary(str) and is_list(opts) do
    # oneshot execution
    # executor will compile, run and teardown the NFA process network
    validate_options(str, opts)
    Process.flag(:trap_exit, true)
    # TODO - using a named group would help conversion of results
    # using :search name should make success handling produce search result directly
    Executor.init_oneshot(".*(" <> re <> ").*", str, opts)
    str |> do_match(opts) |> match2search()
  end

  def search(start, str, opts) when is_pid(start) and is_binary(str) and is_list(opts) do
    # batch execution 
    # executor will build transient prefix network for zero or more any character
    validate_options(str, opts)
    Process.flag(:trap_exit, true)
    Executor.init_search(start, str, opts)
    do_match(str, opts)
  end

  @doc """
  Apply a regular expression to a string input.

  The first argument can be either a regular expression string,
  or the start process address of a compiled NFA process network.

  If the `:multiple` option is `:one`, 
  then the first match to complete is returned with a `:match` result tuple.
    If the `:multiple` option is `:all`, 
  then all matches are returned with a `:matches` result tuple.

  If a regular expression is passed as a string argument, 
  it is compiled to a one-shot NFA process network, 
  which is torn down after the string match has completed.
  The options passed affect both the compile-time and run-time behaviour.

  If a compiled NFA is passed as a process argument,
  the options passed for batch execution
  only affect the runtime behaviour.
  """
  @spec match(String.t() | pid(), String.t(), Keyword.t()) :: T.match_result()

  def match(re, str, opts \\ [])

  def match(re, str, opts) when is_binary(re) and is_binary(str) and is_list(opts) do
    # oneshot execution
    # the executor will compile, run and teardown the NFA process network
    validate_options(str, opts)
    Process.flag(:trap_exit, true)
    Executor.init_oneshot(re, str, opts)
    do_match(str, opts)
  end

  def match(start, str, opts) when is_pid(start) and is_binary(str) and is_list(opts) do
    validate_options(str, opts)
    Process.flag(:trap_exit, true)
    Executor.init_batch(start, str, opts)
    do_match(str, opts)
  end

  @spec do_match(String.t(), T.options(), any()) :: no_return()
  defp do_match(str, opts, matches \\ []) do
    # Add the whole string capture to the result, 
    # not in the initial traverse call,
    # so it does not need to be copied through every traversal.
    # Ignore options, and add it as a string (binary) 
    # not just an index reference {0,length}
    # so the input is always available in the result.

    # TODO - only handle return type flag here?
    # captures should be compiled into the group and success processes?
    # define the difference between compile-time and run-time options?

    receive do
      :match ->
        {:matches, matches}

      :search ->
        {:searches, Enum.sort(matches)}

      :no_match ->
        {:no_match, %{0 => str}}

      {:match, caps} ->
        caps = process_captures(str, opts, caps)

        case Keyword.get(opts, :multiple, :one) do
          :one -> {:match, caps}
          :all -> do_match(str, opts, [caps | matches])
        end

      {:search, index, caps} ->
        caps = process_captures(str, opts, caps)

        case Keyword.get(opts, :multiple, :one) do
          :one -> {:search, index, caps}
          :all -> do_match(str, opts, [{index, caps} | matches])
        end

      {:EXIT, _, :normal} ->
        do_match(str, opts, matches)

      {:EXIT, _, reason} ->
        raise RuntimeError, message: "Execution failed: #{inspect(reason)}"

      msg ->
        raise RuntimeError, message: "Unhandled message #{inspect(msg)}"
    end
  end

  # apply 'capture' and 'return' options to capture results
  @spec process_captures(String.t(), T.options(), T.captures()) :: T.captures()
  defp process_captures(str, opts, caps) do
    capopt = Keyword.get(opts, :capture, :all)
    return = Keyword.get(opts, :return, :index)

    caps =
      case {capopt, return} do
        {:none, _} -> %{}
        {:all, :index} -> caps
        {:all, :binary} -> caps |> cap2str(str)
        {:named, :index} -> caps |> Map.reject(&is_count1(&1))
        {:named, :binary} -> caps |> Map.reject(&is_count1(&1)) |> cap2str(str)
        {names, :index} when is_list(names) -> caps |> Map.take(names)
        {names, :binary} when is_list(names) -> caps |> Map.take(names) |> cap2str(str, names)
      end

    Map.put(caps, 0, str)
  end

  # get group substrings for all capture indexes
  @spec cap2str(T.captures(), String.t()) :: T.captures()
  defp cap2str(caps, str), do: cap2str(caps, str, Map.keys(caps))

  # get input substrings from capture indexes
  # for a specific set of keys (capture names)
  @spec cap2str(T.captures(), String.t(), [T.capture_name()]) :: T.captures()

  defp cap2str(caps, str, [name | names]) do
    substr =
      case Map.get(caps, name, :no_capture) do
        :no_capture ->
          :no_capture

        {pos, len} ->
          String.slice(str, pos, len)

        indexes when is_list(indexes) ->
          Enum.map(indexes, fn {pos, len} -> String.slice(str, pos, len) end)
      end

    caps |> Map.put(name, substr) |> cap2str(str, names)
  end

  defp cap2str(caps, _, []), do: caps

  # convert a wrapped match result to a search result

  defp match2search({:no_match, _caps} = result), do: result

  defp match2search({:match, caps}) when is_map(caps) do
    {str, caps} = Map.pop!(caps, 0)
    # fake search capture is index 1
    # remove it from captures and use for search result
    {idx, caps} = Map.pop!(caps, 1)

    search_caps =
      Enum.reduce(caps, %{0 => str}, fn {k, v}, c when is_integer(k) and k > 0 ->
        # move all captures down by 1 to fill space left by fake search
        Map.put(c, k - 1, v)
      end)

    {:search, idx, search_caps}
  end

  defp match2search({:matches, capss}) when is_list(capss) do
    searches =
      capss
      |> Enum.map(fn caps ->
        {:search, idx, search_caps} = match2search({:match, caps})
        {idx, search_caps}
      end)
      |> Enum.sort()

    {:searches, searches}
  end

  # check run-time options, including those that depend on the input string
  defp validate_options(str, opts) do
    offset = Keyword.get(opts, :offset, 0)

    if offset < 0 do
      raise ArgumentError, message: "Option 'offset' must be positive: #{offset}"
    end

    if str != "" and offset >= String.length(str) do
      raise ArgumentError, message: "Option 'offset' exceeds string length: #{offset}"
    end

    validate_options(opts)
  end

  # validate compile-time and run-time options
  defp validate_options(opts) do
    timeout = Keyword.get(opts, :timeout, T.default(:timeout))

    if timeout < 0 do
      raise ArgumentError, message: "Option 'timeout' must be positive: #{timeout}"
    end

    multiple = Keyword.get(opts, :multiple, T.default(:multiple))

    if multiple != :one and multiple != :all do
      raise ArgumentError, message: "Illegal 'multiple' option value: #{multiple}"
    end
  end
end
