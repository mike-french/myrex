defmodule Myrex.NFA.Graph do
  @moduledoc """
  Utilities for storing a directed graph in the process dictionary.

  All node creation, edge creation and graph access
  must be executed from the same process.

  The graph can be converted to GraphViz DOT format
  and rendered as a PNG image (if GraphViz is installed).
  """

  @typedoc "Unique ID for a node."
  @type id() :: String.t()

  @typedoc "The name label for a node."
  @type name() :: String.t()

  @typedoc "The map of all nodes indexed by ID."
  @type nodes() :: %{id() => name()}

  @typedoc "The list of all edges defined by source and destination node IDs."
  @type edges() :: [{id(), id()}]

  # keys for graph data in the process dictionary

  @nodes :nodes
  @edges :edges
  @enabled :enabled

  @doc "Enable graph data storage."
  @spec enable() :: :ok
  def enable() do
    Process.put(@enabled, true)
    :ok
  end

  @doc "Disable graph data storage."
  @spec disable() :: :ok
  def disable() do
    Process.put(@enabled, true)
    :ok
  end

  @doc "Get the enabled flag from the process dictionary."
  @spec enabled?() :: boolean()
  def enabled?() do
    Process.get(@enabled, false)
  end

  @doc "Clear all graph data."
  @spec reset_graph() :: :ok
  def reset_graph() do
    Process.delete(@nodes)
    Process.delete(@edges)
  end

  @doc "Get the complete set of nodes and edges for the graph."
  @spec get_graph() :: {:proc_graph, nodes(), edges()}
  def get_graph() do
    {:proc_graph, get_nodes(), get_edges()}
  end

  @doc "Get the node data."
  @spec get_nodes() :: nodes()
  def get_nodes() do
    Process.get(@nodes, %{})
  end

  @doc """
  Add a node to the graph, if the graph is enabled.

  Return the PID argument.
  """
  @spec add_node(pid(), name()) :: pid()
  def add_node(pid, name) when is_pid(pid) do
    if enabled?() do
      # could add PID to the name here
      # so that diagram has PID labels
      id = pid2id(pid)
      nodes = Map.put(get_nodes(), id, name)
      Process.put(@nodes, nodes)
    end

    pid
  end

  @doc "Get the edge data."
  @spec get_edges() :: edges()
  def get_edges() do
    Process.get(@edges, [])
  end

  @doc """
  Add an edge to the graph, if the graph is enabled.

  Return a flag to show if the edge was added.
  """
  @spec add_edge(pid(), pid()) :: :ok | :disabled
  def add_edge(src_pid, dst_pid) when is_pid(src_pid) and is_pid(dst_pid) do
    if enabled?() do
      src = pid2id(src_pid)
      dst = pid2id(dst_pid)
      edges = get_edges() |> List.insert_at(0, {src, dst})
      Process.put(@edges, edges)
      :ok
    else
      :disabled
    end
  end

  @doc """
  Write the graph data to file in DOT format, if the graph is enabled.

  The filename will have special characters escaped to short text names,
  and the whole filename will be truncated to 255 characters.

  Return the path to the file and the DOT text data,
  or a flag to say the graph is disabled.
  """
  @spec write_dot(String.t(), String.t()) ::
          {path :: String.t(), dot :: IO.chardata()} | :disabled
  def write_dot(filename, dir \\ "dot") do
    if enabled?() do
      dot = [
        "digraph G {\n",
        "  size =\"8,4\";\n",
        "  rankdir=LR;\n",
        Enum.map(get_nodes(), fn {i, label} ->
          ["  ", i, " [label=\"", label, "\"];\n"]
        end),
        Enum.map(get_edges(), fn {i, j} ->
          ["  ", i, " -> ", j, ";\n"]
        end),
        "}"
      ]

      path = dir <> "/" <> escape(filename) <> ".dot"
      if not File.exists?(dir), do: :ok = File.mkdir_p!(dir)
      file = File.open!(path, [:write, :utf8])
      IO.write(file, dot)
      File.close(file)
      {path, dot}
    else
      :disabled
    end
  end

  @doc "Render a DOT file to a PNG image, if GraphViz is installed."
  @spec render_dot(String.t()) :: :ok | {:error, String.t()}
  def render_dot(path) do
    opts = [stderr_to_stdout: true]

    # get the file path up to the '.' filetype suffix
    f = path |> String.split(".", trim: true) |> hd()

    # assume linux 'which' is available 
    ret =
      case System.cmd("which", ["dot"], opts) do
        {_, 0} -> System.cmd("dot", ["-Tpng", f <> ".dot", "-o", f <> ".png"], opts)
        {_, status} = err when status > 0 -> err
      end

    case ret do
      {_, 0} -> :ok
      {msg, status} when status > 0 -> {:error, msg}
    end
  end

  # convert characters not allowed in Windows or Unix filenames
  # truncate to the maximum filename length
  @spec escape(String.t()) :: String.t()
  defp escape(name) do
    name
    |> to_charlist()
    |> Enum.map(fn
      ?\\ -> "_bslash_"
      ?/ -> "_fslash_"
      ?: -> "_colon_"
      ?. -> "_dot_"
      ?* -> "_star_"
      ?? -> "_qmark_"
      ?" -> "_dquote_"
      ?< -> "_langle_"
      ?> -> "_rangle_"
      ?| -> "_vbar_"
      ?\0 -> "_nul_"
      c -> c
    end)
    |> IO.chardata_to_string()
    |> String.slice(0, 250)
  end

  # convert a PID to a unique ID
  # just extract the middle integer value from the PID
  @spec pid2id(pid()) :: id()
  defp pid2id(pid) do
    inspect(pid)
    |> String.split("\.")
    |> Enum.at(1)
  end
end
