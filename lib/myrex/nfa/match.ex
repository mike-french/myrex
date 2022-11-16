defmodule Myrex.NFA.Match do
  @moduledoc "Match a single character of input."

  alias Myrex.Types, as: T

  alias Myrex.Executor
  alias Myrex.NFA.Proc

  @spec init(T.acceptor(), boolean(), String.t()) :: pid()
  def init(accept?, peek?, label) when is_function(accept?, 1) and is_boolean(peek?) do
    # peek does not advance the input position
    Proc.init(__MODULE__, :attach, [accept?, peek?, label], label)
  end

  @spec attach(T.acceptor(), boolean(), String.t()) :: no_return()
  def attach(accept?, peek?, label) do
    receive do
      {:attach, next} when is_pid(next) -> match(accept?, peek?, next, label)
      msg -> raise RuntimeError, message: "Unhandled message #{inspect(msg)}"
    end
  end

  @spec match(T.acceptor(), boolean(), pid(), String.t()) :: no_return()
  defp match(accept?, peek?, next, label_for_debug) do
    receive do
      {<<c::utf8, rest::binary>> = all, pos, groups, captures, executor} ->
        if accept?.(c) do
          # peek does not advance input
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

    match(accept?, peek?, next, label_for_debug)
  end
end
