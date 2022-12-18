defmodule Myrex.NFA.BeginGroup do
  @moduledoc "The process at the beginning of a group capture expression."

  import Myrex.Types
  alias Myrex.Types, as: T

  alias Myrex.Proc.PNode
  alias Myrex.Proc.Proc

  @behaviour PNode

  @impl PNode
  def init({name} = args, label \\ "(") when is_name(name) or is_binary(name) do
    Proc.init_child(__MODULE__, :attach, [args], label)
  end

  @impl PNode
  def attach({_} = args) do
    receive do
      {:attach, proc} when is_pid(proc) -> run(args, proc)
      msg -> raise RuntimeError, message: "Unhandled message #{inspect(msg)}"
    end
  end

  @impl PNode
  def run({name} = args, next) do
    receive do
      {:parse, str, pos, groups, caps, executor} ->
        # add default capture entries
        new_caps = Enum.reduce(T.names(name), caps, fn k, m -> Map.put(m, k, :no_capture) end)
        # push a begin group tuple onto the group stack
        Proc.traverse(next, {:parse, str, pos, [{name, pos} | groups], new_caps, executor})

      msg ->
        raise RuntimeError, message: "Unhandled message #{inspect(msg)}"
    end

    run(args, next)
  end
end
