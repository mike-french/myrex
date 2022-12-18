defmodule Myrex.NFA.EndGroup do
  @moduledoc "The process at the end of a group capture expression."

  alias Myrex.Types, as: T

  alias Myrex.Proc.PNode
  alias Myrex.Proc.Proc

  @behaviour PNode

  @impl PNode
  def init(nil, label \\ ")") do
    Proc.init_child(__MODULE__, :attach, [nil], label)
  end

  @impl PNode
  def attach(nil) do
    receive do
      {:attach, proc} when is_pid(proc) -> run(nil, proc)
      msg -> raise RuntimeError, message: "Unhandled message #{inspect(msg)}"
    end
  end

  @impl PNode
  def run(nil, next) do
    receive do
      {:parse, str, pos, [{name, begin} | groups], caps, executor} ->
        # pop the open group off the stack, update the capture results
        # capture is a start-length pair of positions in the input
        # includes zero length captures "" for `?` and `*` operators
        index = {begin, pos - begin}
        new_caps = Enum.reduce(T.names(name), caps, fn k, m -> Map.put(m, k, index) end)
        Proc.traverse(next, {:parse, str, pos, groups, new_caps, executor})

      msg ->
        raise RuntimeError, message: "Unhandled message #{inspect(msg)}"
    end

    run(nil, next)
  end
end
