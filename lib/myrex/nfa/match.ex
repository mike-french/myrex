defmodule Myrex.NFA.Match do
  @moduledoc "Match a single character of input."

  alias Myrex.Executor
  alias Myrex.Proc.PNode
  alias Myrex.Proc.Proc
  alias Myrex.Uniset

  @behaviour PNode

  @impl PNode
  def init({accept?, peek?, gen_fun_or_uni} = args, label)
      when is_function(accept?, 1) and is_boolean(peek?) and
             (is_function(gen_fun_or_uni) or is_tuple(gen_fun_or_uni)) do
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
  def run({accept?, peek?, gen_fun_or_uni} = args, next) do
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

      {:generate, str, nil, gen} = msg when is_function(gen_fun_or_uni, 0) ->
        # nil Uniset means not in NegCC
        # constructor arg is character generator function
        case gen_fun_or_uni.() do
          # negated anychar will return empty result
          # issue warning message?
          nil -> Proc.traverse(next, msg)
          char -> Proc.traverse(next, {:generate, <<str::binary, char::utf8>>, nil, gen})
        end

      {:generate, str, uni, gen} when is_tuple(gen_fun_or_uni) ->
        # valid Uniset means in NegCC
        # constructor arg is uniset for accumulation
        Proc.traverse(next, {:generate, str, Uniset.union(uni, gen_fun_or_uni), gen})

      msg ->
        raise RuntimeError, message: "Unhandled message #{inspect(msg)}"
    end

    run(args, next)
  end
end
