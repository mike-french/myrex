defmodule Myrex.NFA.Graph do
  @moduledoc """
  Utilities for storing a directed graph in the process dictionary.

  All node creation, edge creation and graph access
  must be executed from the same process.

  The graph can be converted to GraphViz DOT format
  and rendered as a PNG image (if GraphVia is installed).
  """

  @type id() :: String.t()
  @type name() :: String.t()
  @type nodes() :: %{id() => name()}
  @type edges() :: [{id(), id()}]

  @nodes :nodes
  @edges :edges
  @enabled :enabled

  @spec enable() :: :ok
  def enable() do
    Process.put(@enabled, true)
    :ok
  end

  @spec disable() :: :ok
  def disable() do
    Process.put(@enabled, true)
    :ok
  end

  @spec enabled?() :: boolean()
  def enabled?() do
    Process.get(@enabled, false)
  end

  @spec reset_graph() :: :ok
  def reset_graph() do
    Process.delete(@nodes)
    Process.delete(@edges)
  end

  @spec get_graph() :: {:proc_graph, nodes(), edges()}
  def get_graph() do
    {:proc_graph, get_nodes(), get_edges()}
  end

  @spec get_nodes() :: nodes()
  def get_nodes() do
    Process.get(@nodes, %{})
  end

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

  @spec get_edges() :: edges()
  def get_edges() do
    Process.get(@edges, [])
  end

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

  @spec write_dot(String.t(), String.t()) ::
          {path :: String.t(), dot :: IO.chardata()} | :disabled
  def write_dot(name, dir \\ "dot") do
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

      path = dir <> "/" <> escape(name) <> ".dot"
      if not File.exists?(dir), do: :ok = File.mkdir_p!(dir)
      file = File.open!(path, [:write, :utf8])
      IO.write(file, dot)
      File.close(file)
      {path, dot}
    else
      :disabled
    end
  end

  @doc "Render a DOT file to PNG, if GraphViz is installed."
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
    |> String.slice(0, 255)
  end

  @spec pid2id(pid()) :: id()
  defp pid2id(pid) do
    inspect(pid)
    |> String.split("\.")
    |> Enum.at(1)
  end
end
