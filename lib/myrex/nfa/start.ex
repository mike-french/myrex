defmodule Myrex.NFA.Start do
  @moduledoc """
  The start process for an NFA process network.

  The start process is the entry point for traversals to match input strings.

  Create the NFA process network as a collection of spawned linked child processes.
  Act as the initial node for traversing the network to parse input strings.

  When the start process receives a `:teardown` message, 
  the builder exits normally and all the linked NFA processes will exit.
  """

  import Myrex.Types
  alias Myrex.Types, as: T

  alias Myrex.Proc.Graph
  alias Myrex.Proc.PNode
  alias Myrex.Proc.Proc

  @behaviour PNode

  @impl PNode

  def init({builder, gname}, label \\ "start")
      when is_function(builder, 0) and (gname == nil or is_binary(gname)) do
    # all for one and one for all
    Process.flag(:trap_exit, true)
    # output graph is enabled if there is a string graph name argument
    graph? = not is_nil(gname)

    if graph? do
      # enable graph now to capture the node for the start process
      Graph.enable()
    end

    # initialize the start process
    # add the start node to the graph (if enabled)
    # pass a builder function that creates the NFA in the start process
    # wait for the NFA to be complete
    # return the new start process
    start = Proc.init_parent(__MODULE__, :attach, [{builder, gname, self()}], label, graph?)

    receive do
      :nfa_running ->
        :ok

      {:EXIT, ^start, reason} ->
        raise RuntimeError, message: "Compilation failed: #{inspect(reason)}"
    end

    start
  end

  @impl PNode

  def attach({builder, nil, client}) when is_function(builder, 0) do
    # special attachment to an NFA built here
    nfa = builder.()
    send(client, :nfa_running)
    run(nil, nfa)
  end

  def attach({builder, gname, client}) when is_function(builder, 0) and is_binary(gname) do
    # special attachment to an NFA built here
    nfa = builder.()
    # connect and wait for connection
    # connection will add this start node to the process graph
    Proc.connect_to(nfa)
    send(client, :nfa_running)

    # render the process graph to the 'dot' output directory
    {path, _dot} = Graph.write_dot(gname)
    Graph.render_dot(path)

    run(nil, nfa)
  end

  # main loop
  @impl PNode
  def run(nil, nfa) do
    receive do
      state when T.is_state(state) -> Proc.traverse(nfa, state)
      :teardown -> exit(:normal)
      msg -> raise RuntimeError, message: "Unhandled message #{inspect(msg)}"
    end

    run(nil, nfa)
  end

  @doc """
  Destroy an NFA process network. 
  The builder process is stopped
  and all linked NFA processes will exit.

  Ignore if the argument is other than an NFA process,
  such as `nil` from batch executor
  and string regex from testing.
  """
  @spec teardown(any()) :: :teardown | :ignore
  def teardown(nfa) when is_pid(nfa), do: send(nfa, :teardown)
  def teardown(_), do: :ignore
end
