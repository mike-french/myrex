defmodule Myrex.NFA.Success do
  @moduledoc "The final node that handles a successful match."

  import Myrex.Types
  alias Myrex.Types, as: T

  alias Myrex.Executor
  alias Myrex.NFA.Proc

  @doc "Initialize with the number of groups in the regex."
  @spec init(T.count()) :: pid()
  def init(ngroup) when is_count(ngroup) do
    Proc.init_child(__MODULE__, :match, [ngroup], "success")
  end

  # no need for attach, because the executor is carried in the traversal state
  # just included here so we could make an NFA node behaviour in the future
  @spec attach(any()) :: no_return()
  def attach(_) do
    raise UndefinedFunctionError, message: "Success.attach/1"
  end

  @spec match(T.count()) :: no_return()
  def match(ngroup) when is_count(ngroup) do
    receive do
      {"", _len, [], captures, executor} ->
        # finish state of the NFA and end of input, so a complete match
        captures = default_captures(captures, ngroup)
        Executor.notify_result(executor, {:match, captures})

      {"", len, [{:search, begin}], captures, executor} ->
        # finish state of the NFA and end of input, so a complete search match
        # open group contains a special search capture token
        captures = default_captures(captures, ngroup)
        # send a search result including the index of the search capture
        Executor.notify_result(executor, {:search, {begin, len - begin}, captures})

      {str, pos, [{:search, begin}], _caps, executor} = state when byte_size(str) > 0 ->
        # finish state of the NFA, but not end of input
        # so NFA matches a prefix of the original input
        # for a search, this is a successful partial match
        Executor.notify_result(executor, {:partial_search, {begin, pos - begin}, state})

      {str, _pos, _open_groups, _caps, executor} when byte_size(str) > 0 ->
        # finish state of the NFA, but not end of input
        # so NFA matches a prefix of the original input
        # for a normal match, this is a no_match failure
        Executor.notify_result(executor, :no_match)

      msg ->
        raise RuntimeError, message: "Unhandled message #{inspect(msg)}"
    end

    match(ngroup)
  end

  # add default captures
  @spec default_captures(T.captures(), T.count()) :: T.captures()

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
