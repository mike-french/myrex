defmodule Myrex.NFA.Match do
  @moduledoc "Match a single character of input."

  alias Myrex.Executor
  alias Myrex.Proc.PNode
  alias Myrex.Proc.Proc

  @behaviour PNode

  @impl PNode
  def init({accept?, peek?} = args, label) when is_function(accept?, 1) and is_boolean(peek?) do
    Proc.init_child(__MODULE__, :attach, [args], label)
  end

  @impl PNode
  def attach(args) do
    receive do
      {:attach, next} when is_pid(next) -> run(args, next)
      msg -> raise RuntimeError, message: "Unhandled message #{inspect(msg)}"
    end
  end

  @impl PNode
  def run({accept?, peek?} = args, next) do
    receive do
      {<<c::utf8, rest::binary>> = all, pos, groups, captures, executor} ->
        if accept?.(c) do
          # peek lookahead does not advance the input position
          {new_str, new_pos} = if peek?, do: {all, pos}, else: {rest, pos + 1}
          Proc.traverse(next, {new_str, new_pos, groups, captures, executor})
        else
          Executor.notify_result(executor, :no_match)
        end

      {"", _, _, _, executor} ->
        # end of input
        Executor.notify_result(executor, :no_match)

      msg ->
        raise RuntimeError, message: "Unhandled message #{inspect(msg)}"
    end

    run(args, next)
  end
end
