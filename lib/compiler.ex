defmodule Myrex.Compiler do
  @moduledoc "Public interface to build an NFA from an AST."

  alias Myrex.Types, as: T

  alias Myrex.AST
  alias Myrex.Lexer
  alias Myrex.NFA
  alias Myrex.NFA.Proc
  alias Myrex.NFA.Success
  alias Myrex.Parser

  @doc """
  Convert a regular expression to an NFA process network.
  All processes are linked from the calling self process.
  Return the address of the input process.
  """
  @spec compile(T.regex(), Keyword.t()) :: pid()
  def compile(re, opts) do
    {toks, gmax} = Lexer.lex(re)
    ast = Parser.parse(toks)
    aststr = AST.ast2str(ast)
    IO.puts(aststr)
    nfa = ast2nfa(ast, opts)
    success = Success.init(gmax)
    Proc.connect(nfa, success)
    Proc.input(nfa)
  end

  # Recursively convert an AST tree of operators
  # to an NFA process network and
  # return the input process address.
  @spec ast2nfa(T.ast(), T.options()) :: pid()

  defp ast2nfa(c, _opts) when is_integer(c) do
    NFA.match_char(c)
  end

  defp ast2nfa({:char_range, c1, c2}, _opts) do
    NFA.match_char_range({c1, c2})
  end

  defp ast2nfa(:any_char, opts) do
    opts
    |> Keyword.get(:dotall, false)
    |> NFA.match_any_char()
  end

  defp ast2nfa({:zero_one, node}, opts) do
    node
    |> ast2nfa(opts)
    |> NFA.zero_one()
  end

  defp ast2nfa({:one_more, node}, opts) do
    node
    |> ast2nfa(opts)
    |> NFA.one_more()
  end

  defp ast2nfa({:zero_more, node}, opts) do
    node
    |> ast2nfa(opts)
    |> NFA.zero_more()
  end

  defp ast2nfa({:sequence, nodes}, opts) do
    nodes
    |> Enum.map(&ast2nfa(&1, opts))
    |> NFA.sequence()
  end

  defp ast2nfa({:group, name, nodes}, opts) do
    name =
      case Keyword.get(opts, :capture, :all) do
        :none -> :nocap
        :all -> name
        :named -> if not is_integer(name), do: name, else: :nocap
        names when is_list(names) -> if name in names, do: name, else: :nocap
      end

    nodes
    |> Enum.map(&ast2nfa(&1, opts))
    |> NFA.group(name)
  end

  defp ast2nfa({:repeat, nrep, node}, opts) do
    # TODO - implement native repeat process in NFA
    # this lazy code makes multiple copies of the subgraph 
    1..nrep
    |> Enum.map(fn _ -> ast2nfa(node, opts) end)
    |> NFA.sequence()
  end

  defp ast2nfa({:alternate, nodes}, opts) do
    nodes
    |> Enum.map(&ast2nfa(&1, opts))
    |> NFA.alternate("|")
  end

  defp ast2nfa({:char_class, ccs}, opts) do
    ccs
    |> Enum.map(&ast2nfa(&1, opts))
    |> NFA.alternate("[]")
  end

  defp ast2nfa(ast, _) do
    raise RuntimeError, message: "Error: no nfa clause for #{ast}"
  end
end
