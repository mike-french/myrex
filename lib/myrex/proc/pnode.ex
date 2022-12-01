defmodule Myrex.Proc.PNode do
  @moduledoc "Behaviour for a process node in a process network."

  alias Myrex.Proc.Graph.Types, as: G

  @callback init(tuple(), G.label()) :: pid()

  @callback attach(tuple()) :: no_return()

  @callback run(nil | tuple(), nil | pid() | [pid()]) :: no_return()
end
