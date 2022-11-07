defmodule Myrex.NFA.Success do
  @moduledoc "The final node that processes a successful match."
  import Myrex.Types
  alias Myrex.Types, as: T

  alias Myrex.NFA.Executor

  @spec init(T.count()) :: pid()
  def init(ngroup) when is_count(ngroup), do: spawn_link(__MODULE__, :match, [ngroup])

  # no need for attach, because the executor is carried in the traversal state
  @spec attach(any()) :: no_return()
  def attach(_) do
    raise UndefinedFunctionError, message: "Success.attach/1"
  end

  @spec match(T.count()) :: no_return()
  def match(ngroup) when is_count(ngroup) do
    receive do
      {"", len, [], captures, executor} when is_pid(executor) ->
        # finish state of the NFA and end of input, so a complete match
        # 0th capture is the whole string
        # when all input is consumed the final position is the length of input
        captures = captures |> Map.put(0, {0, len}) |> default_captures(ngroup)
        Executor.notify_result(executor, {:match, captures})

      {_, _, _, _, executor} when is_pid(executor) ->
        # finish state of the NFA, but not end of input
        # so NFA matches a prefix of the original input
        Executor.notify_result(executor, :no_match)

      msg ->
        raise RuntimeError, message: "Unhandled message #{inspect(msg)}"
    end

    match(ngroup)
  end

  defp default_captures(caps, 0), do: caps

  defp default_captures(caps, igroup) do
    if Map.has_key?(caps, igroup) do
      default_captures(caps, igroup - 1)
    else
      new_caps = Map.put(caps, igroup, :no_capture)
      default_captures(new_caps, igroup - 1)
    end
  end
end
