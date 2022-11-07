defmodule Myrex.NFA.EndGroup do
  @moduledoc "The process at the end of a group capture expression."
  import Myrex.Types

  alias Myrex.NFA.Proc

  @spec init() :: pid()
  def init(), do: spawn_link(__MODULE__, :attach, [nil])

  @spec attach(any()) :: no_return()
  def attach(_) do
    receive do
      {:attach, proc} when is_proc(proc) -> match(Proc.input(proc))
      msg -> raise RuntimeError, message: "Unhandled message #{inspect(msg)}"
    end
  end

  @spec match(pid()) :: no_return()
  defp match(next) do
    receive do
      {str, pos, [{name, begin} | groups], captures, executor} ->
        # capture is a start-length pair of positions in the input
        new_captures = Map.put(captures, name, {begin, pos - begin})
        # pop the group off the stack, update the capture results
        Proc.traverse(next, {str, pos, groups, new_captures, executor})

      msg ->
        raise RuntimeError, message: "Unhandled message #{inspect(msg)}"
    end

    match(next)
  end
end
