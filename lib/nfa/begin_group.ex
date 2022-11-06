defmodule Myrex.NFA.BeginGroup do
  @moduledoc "The process at the beginning of a group capture expression."
  import Myrex.Types
  alias Myrex.Types, as: T

  alias Myrex.NFA.Proc

  @spec init(T.capture_name()) :: pid()
  def init(name) when is_name(name), do: spawn(__MODULE__, :attach, [name])

  @spec attach(T.capture_name()) :: no_return()
  def attach(name) do
    receive do
      proc when is_proc(proc) -> match(name, Proc.input(proc))
    end
  end

  @spec match(T.capture_name(), pid()) :: no_return()
  defp match(name, next) do
    receive do
      {str, pos, groups, captures, executor} ->
        send(next, {str, pos, [{name, pos} | groups], captures, executor})
    end

    match(name, next)
  end
end
