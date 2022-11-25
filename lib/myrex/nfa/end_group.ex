defmodule Myrex.NFA.EndGroup do
  @moduledoc "The process at the end of a group capture expression."

  alias Myrex.Types, as: T

  alias Myrex.NFA.Proc

  @spec init() :: pid()
  def init() do
    Proc.init_child(__MODULE__, :attach, [], ")")
  end

  @spec attach() :: no_return()
  def attach() do
    receive do
      {:attach, proc} when is_pid(proc) -> match(proc)
      msg -> raise RuntimeError, message: "Unhandled message #{inspect(msg)}"
    end
  end

  @spec match(pid()) :: no_return()
  defp match(next) do
    receive do
      {str, pos, [{name, begin} = grp | groups], caps, executor} ->
        # pop the open group off the stack, update the capture results
        # capture is a start-length pair of positions in the input
        # includes zero length captures "" for `?` and `*` operators
        index = {begin, pos - begin}
        new_caps = Enum.reduce(T.names(name), caps, fn k, m -> Map.put(m, k, index) end)
        Proc.traverse(next, {str, pos, groups, new_caps, executor})

      msg ->
        raise RuntimeError, message: "Unhandled message #{inspect(msg)}"
    end

    match(next)
  end
end
