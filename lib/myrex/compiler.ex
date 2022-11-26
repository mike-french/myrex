defmodule Myrex.Compiler do
  @moduledoc "Build an NFA process network from a regular expression."

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
    #  IO.puts(AST.ast2str(ast))
    nfa = re |> Lexer.lex() |> Parser.parse() |> ast2nfa(opts)
    Proc.connect(nfa, Success.init())
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

  defp ast2nfa({:group, :nocap, nodes}, opts) do
    nodes
    |> Enum.map(&ast2nfa(&1, opts))
    |> NFA.sequence()
  end

  defp ast2nfa({:group, {g, name} = both, nodes}, opts) do
    tags =
      case Keyword.get(opts, :capture, :all) do
        :none ->
          :nocap

        :all ->
          both

        :named ->
          name

        names when is_list(names) ->
          case {g in names, name in names} do
            {true, true} -> both
            {true, false} -> g
            {false, true} -> name
            {false, false} -> :nocap
          end
      end

    nodes
    |> Enum.map(&ast2nfa(&1, opts))
    |> NFA.group(tags)
  end

  defp ast2nfa({:group, g, nodes}, opts) when is_integer(g) do
    g =
      case Keyword.get(opts, :capture, :all) do
        :none -> :nocap
        :all -> g
        :named -> :nocap
        names when is_list(names) -> if g in names, do: g, else: :nocap
      end

    nodes
    |> Enum.map(&ast2nfa(&1, opts))
    |> NFA.group(g)
  end

  defp ast2nfa({:repeat, nrep, node}, opts) do
    # TODO - implement native repeat process in NFA
    # this naive hack code makes multiple copies of the subgraph 
    # TODO - implement range repeats to handle all quantifiers:
    # bounded {N,M} and unbounded {N,} 
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
    # regular char class is alternate OR choice of elements
    ccs |> Enum.map(&cc2nfa(&1, opts, false)) |> NFA.alternate("[]")
  end

  defp ast2nfa({:char_class_neg, ccs}, opts) do
    # negated char class is AND sequence of negated (peek lookahead) elements
    ccs |> Enum.map(&cc2nfa(&1, opts, true)) |> NFA.and_sequence()
  end

  defp ast2nfa(ast, _) do
    raise RuntimeError, message: "Error: no nfa clause for #{ast}"
  end

  # convert character class leaf nodes to Match nodes
  @spec cc2nfa(T.ast(), T.options(), boolean()) :: pid()

  defp cc2nfa(c, _opts, neg?) when is_integer(c) do
    NFA.match_char(c, neg?)
  end

  defp cc2nfa({:char_range, c1, c2}, _opts, neg?) do
    NFA.match_char_range({c1, c2}, neg?)
  end

  defp cc2nfa(:any_char, opts, neg?) do
    # is any_char allowed in char class???
    # always passes or ^fails 
    opts
    |> Keyword.get(:dotall, false)
    |> NFA.match_any_char(neg?)
  end

  defp cc2nfa(ast, _, _) do
    raise RuntimeError, message: "Error: no nfa clause for character class #{ast}"
  end
end
