defmodule Myrex.NFA.EndGroup do
  @moduledoc "The process at the end of a group capture expression."
  import Myrex.Types

  alias Myrex.NFA.Proc

  @spec init() :: pid()
  def init(), do: spawn(__MODULE__, :attach, [])

  @spec attach() :: no_return()
  def attach() do
    receive do
      proc when is_proc(proc) -> match(Proc.input(proc))
    end
  end

  @spec match(pid()) :: no_return()
  defp match(next) do
    receive do
      {str, pos, [{name, begin} | groups], captures, executor} ->
        # capture is a start-length pair of positions in the input
        new_captures = Map.put(captures, name, {begin, pos - begin})
        # pop the group off the stack, update the capture results
        send(next, {str, pos, groups, new_captures, executor})
    end

    match(next)
  end
end
