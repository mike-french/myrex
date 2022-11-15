defmodule Myrex.NFA.Start do
  @moduledoc """
  The start process for an NFA process networks.
  The start process is the entry point for traversals to match input strings.
  """

  alias Myrex.Types, as: T

  alias Myrex.NFA.Graph
  alias Myrex.NFA.Proc

  @doc """
  Create the NFA process network as a collection of spawned linked child processes.
  Act as the start node for traversing the network to parse input strings.

  When the start process receives a `:teardown` message, 
  the builder exits normally and the linked NFA processes will exit.
  """
  @spec init(T.builder(), T.maybe(String.t())) :: pid()
  def init(builder, gname \\ nil) when is_function(builder, 0) do
    Process.flag(:trap_exit, true)
    start = spawn_link(__MODULE__, :build, [builder, gname, self()])

    receive do
      :nfa_running ->
        start

      {:EXIT, ^start, reason} ->
        raise RuntimeError, message: "Compilation failed: #{inspect(reason)}"
    end
  end

  @spec build(T.builder(), T.maybe(String.t()), pid()) :: no_return()

  def build(builder, nil, client) do
    # run the builder in the start process so that 
    # all NFA processes are linked to the start process
    Graph.disable()
    nfa = builder.()
    send(client, :nfa_running)
    nfa(nfa)
  end

  def build(builder, gname, client) do
    Graph.enable()
    Graph.add_node(self(), "start")

    nfa = builder.()
    # start-nfa connection does not use Proc.connect
    # so explicitly add the graph edge here
    Graph.add_edge(self(), Proc.input(nfa))

    # graph = Graph.get_graph()
    # IO.inspect(graph, label: "GRAPH")
    {path, _dot} = Graph.write_dot(gname)
    # IO.puts(dot)
    Graph.render_dot(path)
    send(client, :nfa_running)
    nfa(nfa)
  end

  @spec nfa(pid()) :: no_return()
  defp nfa(nfa) do
    receive do
      state when is_tuple(state) ->
        Proc.traverse(nfa, state)

      :teardown ->
        exit(:normal)
    end

    nfa(nfa)
  end

  @doc """
  Destroy an NFA process network. 
  The builder process is stopped
  and all linked NFA processes will exit.
  """

  @spec teardown(any()) :: :ok

  def teardown(nfa) when is_pid(nfa) do
    send(nfa, :teardown)
    :ok
  end

  def teardown(_) do
    # ignore nil from batch executor
    # and string regex from testing
    :ok
  end
end
