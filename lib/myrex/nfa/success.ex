defmodule Myrex.NFA.Success do
  @moduledoc "The final node that handles a successful match."

  alias Myrex.Executor
  alias Myrex.NFA.Proc

  @doc "Initialize final Success NFA process node."
  @spec init() :: pid()
  def init() do
    Proc.init_child(__MODULE__, :match, [], "success")
  end

  # no need for attach, because the executor is carried in the traversal state
  # just included here so we could make an NFA node behaviour in the future
  @spec attach(any()) :: no_return()
  def attach(_) do
    raise UndefinedFunctionError, message: "Success.attach/1"
  end

  @spec match() :: no_return()
  def match() do
    receive do
      {"", _len, [], captures, executor} ->
        # finish state of the NFA and end of input, so a complete match
        # add default ':no_capture` values?
        Executor.notify_result(executor, {:match, captures})

      {"", len, [{:search, begin}], captures, executor} ->
        # finish state of the NFA and end of input, so a complete search match
        # open group contains a special search capture token
        # send a search result including the index of the search capture
        Executor.notify_result(executor, {:search, {begin, len - begin}, captures})

      {str, pos, [{:search, begin}], captures, executor} when byte_size(str) > 0 ->
        # finish state of the NFA, but not end of input
        # so NFA matches a prefix of the original input
        # for a search, this is a successful partial match
        Executor.notify_result(executor, {:search, {begin, pos - begin}, captures})

      {str, _pos, _open_groups, _caps, executor} when byte_size(str) > 0 ->
        # finish state of the NFA, but not end of input
        # so NFA matches a prefix of the original input
        # for a normal match, this is a no_match failure
        Executor.notify_result(executor, :no_match)

      msg ->
        raise RuntimeError, message: "Unhandled message #{inspect(msg)}"
    end

    match()
  end
end
