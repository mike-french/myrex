defmodule Myrex.AST do
  @moduledoc """
  An AST for simple regular expressions.

  Combinator branch nodes

  { :sequence,    [n] }     always list, no name
  { :group, ID,   [n] }     a group is a special named sequence

  { :alternate,   [n] }     two or more nodes

  { :zero_one,     n }
  { :one_more,     n }
  { :zero_more,    n }
  { :repeat, N,    n }      N>0, allow N,M in future

  Matcher leaf nodes

    C                       char is a char literal
    :any_char               any character wilcard
  { :char_class, [C|cr] }   set of characters or character ranges
                            where cr is char range { C1, C2 } and C2>C1

  """

  import Myrex.Types
  alias Myrex.Types, as: T

  @doc "Convert an AST tree of operators to a regular expression string."
  @spec ast2re(T.ast()) :: String.t()
  def ast2re(ast), do: ast |> node2re() |> List.wrap() |> IO.chardata_to_string()

  # Convert an AST node to a regular expression.
  @spec node2re(T.ast() | [T.ast()]) :: IO.chardata()
  defp node2re(nodes) when is_list(nodes), do: Enum.map(nodes, &node2re(&1))
  defp node2re(str) when is_binary(str), do: str |> to_charlist() |> node2re()
  defp node2re(c) when is_char(c), do: esc(c)
  defp node2re(:any_char), do: ?.
  defp node2re({:sequence, nodes}), do: [node2re(nodes)]
  defp node2re({:group, :nocap, nodes}), do: [?(, ??, ?:, node2re(nodes), ?)]
  defp node2re({:group, _, nodes}), do: [?(, node2re(nodes), ?)]

  defp node2re({:alternate, [h | ns]}),
    do: [node2re(h) | Enum.map(ns, fn n -> [?|, node2re(n)] end)]

  defp node2re({:zero_one, node}), do: [node2re(node), ??]
  defp node2re({:one_more, node}), do: [node2re(node), ?+]
  defp node2re({:zero_more, node}), do: [node2re(node), ?*]
  defp node2re({:repeat, r, node}), do: [node2re(node), ?{, Integer.to_string(r), ?}]
  defp node2re({:char_class, ccs}), do: [?[, Enum.map(ccs, &cc2re(&1)), ?]]
  defp node2re({:char_class_neg, ccs}), do: [?[, ?^, Enum.map(ccs, &cc2re(&1)), ?]]

  # Convert a character class element to text format.
  @spec cc2re(char() | T.char_pair()) :: IO.chardata()
  defp cc2re({:char_range, c1, c2}), do: [esc(c1), ?-, esc(c2)]
  defp cc2re(c) when is_char(c), do: esc(c)

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
    esc_char = str |> to_charlist() |> Enum.map(&esc/1)
    ast2str({:sequence, esc_char}, d)
  end

  defp ast2str(c, d) when is_char(c) do
    [indent(d), esc(c), ?\n]
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

  defp ast2str({:char_class, ccs}, d), do: do_cc2str(ccs, d, "[\n")
  defp ast2str({:char_class_neg, ccs}, d), do: do_cc2str(ccs, d, "[^\n")

  defp ast2str(x, _), do: raise(ArgumentError, message: "Illegal AST node '#{inspect(x)}'")

  # convert character class to string using positive or negative opening symbols
  defp do_cc2str(ccs, d, open) do
    [
      [indent(d), open],
      Enum.map(ccs, &cc2str(&1, d + 1)),
      [indent(d), "]"]
    ]
  end

  # Convert a character class element to indented text format.
  # A char class element is a char range or literal char.
  @spec cc2str(char() | T.char_range(), T.count()) :: IO.chardata()
  defp cc2str(cc, d), do: [indent(d), cc2str(cc), ?\n]

  # Convert a character class element to text format.
  @spec cc2str(char() | T.char_range()) :: IO.chardata()
  defp cc2str({:char_range, c1, c2}), do: to_string([esc(c1), ?-, esc(c2)])
  defp cc2str(:any_char), do: "."
  defp cc2str(c) when is_char(c), do: esc(c)

  # escape individual characters 
  @spec esc(char()) :: char() | charlist()
  defp esc(c) when c > 0x0FFF, do: "\\u" <> Integer.to_string(c, 16)
  defp esc(c) when c > 0x00FF, do: "\\u0" <> Integer.to_string(c, 16)
  defp esc(c) when c > 0x007F, do: "\\u00" <> Integer.to_string(c, 16)
  defp esc(?\\), do: "\\\\"
  defp esc(?\0), do: "\\0"
  defp esc(?\e), do: "\\e"
  defp esc(?\f), do: "\\f"
  defp esc(?\n), do: "\\n"
  defp esc(?\r), do: "\\r"
  defp esc(?\t), do: "\\t"
  defp esc(?\v), do: "\\v"
  defp esc(c), do: c

  # Generate an indent of spaces for the nested depth.
  @spec indent(T.count()) :: IO.chardata()
  defp indent(d), do: String.duplicate(" ", d)
end
