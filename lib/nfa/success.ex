defmodule Myrex.NFA.Success do
  @moduledoc "The final node that processes a successful match."
  import Myrex.Types
  alias Myrex.Types, as: T

  @spec init(T.count()) :: pid()
  def init(ngroup) when is_count(ngroup), do: spawn(__MODULE__, :match, [ngroup])

  # no need for attach, because the executor is carried in the traversal state

  @spec match(T.count()) :: no_return()
  def match(ngroup) when is_count(ngroup) do
    receive do
      {"", len, [], captures, executor} ->
        # 0th capture is the whole string
        # when all input is consumed the final position is the length of input
        captures = captures |> Map.put(0, {0, len}) |> default_captures(ngroup)
        send(executor, {:match, captures})

      {str, len, _, _, executor} ->
        send(executor, :no_match)
    end

    match(ngroup)
  end

  defp default_captures(caps, 0), do: caps

  defp default_captures(caps, igroup) do
    if Map.has_key?(caps, igroup) do
      default_captures(caps, igroup - 1)
    else
      new_caps = Map.put(caps, igroup, :no_capture)
      default_captures(new_caps, igroup - 1)
    end
  end
end
