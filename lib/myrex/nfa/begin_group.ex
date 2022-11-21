defmodule Myrex.NFA.BeginGroup do
  @moduledoc "The process at the beginning of a group capture expression."
  import Myrex.Types
  alias Myrex.Types, as: T

  alias Myrex.NFA.Proc

  @spec init(T.capture_name()) :: pid()
  def init(name) when is_name(name) or is_binary(name) do
    Proc.init_child(__MODULE__, :attach, [name], "(")
  end

  @spec attach(T.capture_name()) :: no_return()
  def attach(name) do
    receive do
      {:attach, proc} when is_pid(proc) -> match(name, proc)
      msg -> raise RuntimeError, message: "Unhandled message #{inspect(msg)}"
    end
  end

  @spec match(T.capture_name(), pid()) :: no_return()
  defp match(name, next) do
    receive do
      {str, pos, groups, captures, executor} ->
        # push a begin group tuple onto the group stack in the traversal state
        Proc.traverse(next, {str, pos, [{name, pos} | groups], captures, executor})

      msg ->
        raise RuntimeError, message: "Unhandled message #{inspect(msg)}"
    end

    match(name, next)
  end
end
