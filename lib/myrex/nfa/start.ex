defmodule Myrex.NFA.Start do
  @moduledoc """
  The start process for an NFA process network.
  The start process is the entry point for traversals to match input strings.
  """

  import Myrex.Types
  alias Myrex.Types, as: T

  alias Myrex.NFA.Graph
  alias Myrex.NFA.Proc

  @doc """
  Spawn a start process.

  Create the NFA process network as a collection of spawned linked child processes.
  Act as the initial node for traversing the network to parse input strings.

  When the start process receives a `:teardown` message, 
  the builder exits normally and all the linked NFA processes will exit.
  """
  @spec init(T.builder(), nil | String.t()) :: pid()

  def init(builder, nil) when is_function(builder, 0) do
    Process.flag(:trap_exit, true)
    proc_init(builder, nil)
  end

  def init(builder, gname) when is_function(builder, 0) when is_binary(gname) do
    Process.flag(:trap_exit, true)
    # enable graph now to capture the node for the start process
    Graph.enable()
    proc_init(builder, gname)
  end

  @spec build(T.builder(), nil | String.t(), pid()) :: no_return()

  def build(builder, nil, client) when is_function(builder, 0) do
    nfa = builder.()
    send(client, :nfa_running)
    nfa(nfa)
  end

  def build(builder, gname, client) when is_function(builder, 0) and is_binary(gname) do
    nfa = builder.()
    # connect and wait for connection
    # connection will add this start node to the process graph
    Proc.connect_to(nfa)
    send(client, :nfa_running)

    # render the process graph to the 'dot' output directory
    {path, _dot} = Graph.write_dot(gname)
    Graph.render_dot(path)

    nfa(nfa)
  end

  @spec nfa(pid()) :: no_return()
  defp nfa(nfa) do
    receive do
      state when is_state(state) -> Proc.traverse(nfa, state)
      :teardown -> exit(:normal)
      msg -> raise RuntimeError, message: "Unhandled message #{inspect(msg)}"
    end

    nfa(nfa)
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

  # initialize the start process
  # the graph is enabled if there is a string graph name argument
  # add the start node to the graph (if enabled)
  # pass a builder function that creates the NFA in the start process
  # wait for the NFA to be complete
  # return the new start process
  @spec proc_init(T.builder(), nil | String.t()) :: pid()
  defp proc_init(builder, gname) do
    start =
      Proc.init_parent(__MODULE__, :build, [builder, gname, self()], "start", not is_nil(gname))

    receive do
      :nfa_running ->
        start

      {:EXIT, ^start, reason} ->
        raise RuntimeError, message: "Compilation failed: #{inspect(reason)}"
    end
  end
end
