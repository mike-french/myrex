defmodule Myrex.NFA.Success do
  @moduledoc "The final node that handles a successful match."

  alias Myrex.Executor
  alias Myrex.Proc.PNode
  alias Myrex.Proc.Proc

  @behaviour PNode

  @impl PNode
  def init(nil, label \\ "success") do
    Proc.init_child(__MODULE__, :run, [nil, nil], label)
  end

  # no need for attach, because the executor is carried in the traversal state
  @impl PNode
  def attach(_) do
    raise UndefinedFunctionError, message: "Success.attach/1"
  end

  @impl PNode
  def run(nil, nil) do
    receive do
      {:parse, "", _len, [], captures, executor} ->
        # finish state of the NFA and end of input, so a complete match
        # add default ':no_capture` values?
        Executor.notify_result(executor, {:match, captures})

      {:parse, "", len, [{:search, begin}], captures, executor} ->
        # finish state of the NFA and end of input, so a complete search match
        # open group contains a special search capture token
        # send a search result including the index of the search capture
        Executor.notify_result(executor, {:search, {begin, len - begin}, captures})

      {:parse, str, pos, [{:search, begin}], captures, executor} when byte_size(str) > 0 ->
        # finish state of the NFA, but not end of input
        # so NFA matches a prefix of the original input
        # for a search, this is a successful partial match
        Executor.notify_result(executor, {:search, {begin, pos - begin}, captures})

      {:parse, str, _pos, _open_groups, _caps, executor} when byte_size(str) > 0 ->
        # finish state of the NFA, but not end of input
        # so NFA matches a prefix of the original input
        # for a normal match, this is a no_match failure
        Executor.notify_result(executor, :no_match)

      msg ->
        raise RuntimeError, message: "Unhandled message #{inspect(msg)}"
    end

    run(nil, nil)
  end
end
