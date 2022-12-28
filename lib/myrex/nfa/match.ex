defmodule Myrex.NFA.Match do
  @moduledoc "Match a single character of input."

  alias Myrex.Executor
  alias Myrex.Proc.PNode
  alias Myrex.Proc.Proc

  @behaviour PNode

  @impl PNode
  def init({accept?, peek?, genfun} = args, label)
      when is_function(accept?, 1) and is_boolean(peek?) and is_function(genfun) do
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
  def run({accept?, peek?, genfun} = args, next) do
    receive do
      {:parse, <<c::utf8, rest::binary>> = all, pos, groups, captures, executor} ->
        if accept?.(c) do
          # peek lookahead does not advance the input position
          {new_str, new_pos} = if peek?, do: {all, pos}, else: {rest, pos + 1}
          Proc.traverse(next, {:parse, new_str, new_pos, groups, captures, executor})
        else
          Executor.notify_result(executor, :no_match)
        end

      {:parse, "", _, _, _, executor} ->
        # end of input
        Executor.notify_result(executor, :no_match)

      {:generate, str, generator} ->
        char = genfun.()
        new_str = <<str::binary, char::utf8>>
        Proc.traverse(next, {:generate, new_str, generator})

      msg ->
        raise RuntimeError, message: "Unhandled message #{inspect(msg)}"
    end

    run(args, next)
  end
end
