defmodule Myrex.AST do
  @moduledoc """
  An AST for simple regular expressions.

  Combinator branch nodes

  { :sequence,    [n] }     always list, no name
  { :group, Id,   [n] }     a group is a special named sequence

  { :alternate,   [n] }     two or more nodes

  { :zero_one,     n }
  { :one_more,     n }
  { :zero_more,    n }
  { :repeat, N,    n }      N>0, allow N,M in future

  Matcher leaf nodes

    C                    char is a char literal
    :any_char             
  { :char_class, [C|cr] }
  where cr is  { C1, C2 }   char range C2>C1

  """
  import Myrex.Types
  alias Myrex.Types, as: T

  @doc "Convert an AST tree of operators to a regular expression."
  @spec ast2re(T.ast()) :: String.t()
  def ast2re(ast), do: ast |> node2re() |> List.wrap() |> IO.chardata_to_string()

  @doc "Convert an AST node to a regular expression."
  @spec node2re(T.ast() | [T.ast()]) :: IO.chardata()
  def node2re(nodes) when is_list(nodes), do: Enum.map(nodes, &node2re(&1))
  def node2re(str) when is_binary(str), do: str |> to_charlist() |> node2re()
  def node2re(c) when is_char(c), do: c
  def node2re(:any_char), do: ?.
  def node2re({:sequence, nodes}), do: [node2re(nodes)]
  def node2re({:group, :nocap, nodes}), do: [?(, ??, ?:, node2re(nodes), ?)]
  def node2re({:group, _, nodes}), do: [?(, node2re(nodes), ?)]

  def node2re({:alternate, [h | ns]}),
    do: [node2re(h) | Enum.map(ns, fn n -> [?|, node2re(n)] end)]

  def node2re({:zero_one, node}), do: [node2re(node), ??]
  def node2re({:one_more, node}), do: [node2re(node), ?+]
  def node2re({:zero_more, node}), do: [node2re(node), ?*]
  def node2re({:repeat, r, node}), do: [node2re(node), ?{, Integer.to_string(r), ?}]
  def node2re({:char_class, ccs}), do: [?[, Enum.map(ccs, &cc2re(&1)), ?]]

  # Convert a character class element to text format.
  @spec cc2re(char() | T.char_pair()) :: IO.chardata()
  defp cc2re({:char_range, c1, c2}), do: [c1, ?-, c2]
  defp cc2re(c) when is_char(c), do: c

  @doc """
  Convert an AST tree of operators
  to a multi-line indented string literal.
  """
  @spec ast2str(T.ast()) :: IO.chardata()
  def ast2str(ast), do: ast |> ast2str(0) |> IO.chardata_to_string()

  # Convert an AST node to a multi-line indented string literal."
  @spec ast2str(T.ast(), T.count()) :: IO.chardata()

  defp ast2str(nodes, d) when is_list(nodes) do
    Enum.map(nodes, &ast2str(&1, d))
  end

  defp ast2str(str, d) when is_binary(str) do
    # top-level string is a sequence of characters
    ast2str({:sequence, to_charlist(str)}, d)
  end

  defp ast2str(c, d) when is_char(c) do
    [indent(d), c, ?\n]
  end

  defp ast2str(:any_char, d) do
    [indent(d), ?., ?\n]
  end

  defp ast2str({:sequence, nodes}, d) do
    [
      [indent(d), "sequence {\n"],
      ast2str(nodes, d + 1),
      [indent(d), "}\n"]
    ]
  end

  defp ast2str({:group, :nocap, nodes}, d) do
    [
      [indent(d), "group nocap {\n"],
      ast2str(nodes, d + 1),
      [indent(d), "}\n"]
    ]
  end

  defp ast2str({:group, name, nodes}, d) do
    [
      [indent(d), "group ", Integer.to_string(name), " {\n"],
      ast2str(nodes, d + 1),
      [indent(d), "}\n"]
    ]
  end

  defp ast2str({:alternate, nodes}, d) do
    [
      [indent(d), "alternate {\n"],
      ast2str(nodes, d + 1),
      [indent(d), "}\n"]
    ]
  end

  defp ast2str({:zero_one, node}, d) do
    [
      [indent(d), "zero_one {\n"],
      ast2str(node, d + 1),
      [indent(d), "}\n"]
    ]
  end

  defp ast2str({:one_more, node}, d) do
    [
      [indent(d), "one_more {\n"],
      ast2str(node, d + 1),
      [indent(d), "}\n"]
    ]
  end

  defp ast2str({:zero_more, node}, d) do
    [
      [indent(d), "zero_more {\n"],
      ast2str(node, d + 1),
      [indent(d), "}\n"]
    ]
  end

  defp ast2str({:repeat, r, node}, d) do
    [
      [indent(d), "repeat ", Integer.to_string(r), " {\n"],
      ast2str(node, d + 1),
      [indent(d), "}\n"]
    ]
  end

  defp ast2str({:char_class, ccs}, d) do
    [
      [indent(d), "[\n"],
      Enum.map(ccs, &cc2str(&1, d + 1)),
      [indent(d), "]"]
    ]
  end

  defp ast2str(x, _), do: raise(ArgumentError, message: "Illegal AST node '#{x}'")

  # Convert a character class element to indented text format.
  # A char class element is a char range or literal char.
  @spec cc2str(char() | T.char_range(), T.count()) :: IO.chardata()
  defp cc2str(cc, d), do: [indent(d), cc2str(cc), ?\n]

  # Convert a character class element to text format.
  @spec cc2str(char() | T.char_range()) :: IO.chardata()
  defp cc2str({:char_range, c1, c2}), do: to_string([c1, ?-, c2])
  defp cc2str(c) when is_char(c), do: c

  # Generate an indent of spaces for the nested depth.
  @spec indent(T.count()) :: IO.chardata()
  defp indent(d), do: String.duplicate(" ", d)
end
