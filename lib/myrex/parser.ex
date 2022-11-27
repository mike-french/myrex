defmodule Myrex.Parser do
  @moduledoc """
  Parse the tokenized regular expression to get an AST.

  The parser has two passes:

  The first pass reorders the linear infix token list into postfix format,
  where the operator node comes before its arguments.
  The implementation is a variation of Dijkstra's _Shunting Yard_ algorithm
  \[[Wikipedia](https://en.wikipedia.org/wiki/Shunting_yard_algorithm)\],
  which pushes tokens onto a stack, then pops postfix operator sequences.

  The second pass scans the postfix token list into a tree
  and returns the root node. The root is either the top-level group 
  from the regular expression, or an implied anonymous sequence.
  For example, a series of characters "abcd" will be enclosed
  in a sequence root container.
  """

  import Myrex.Types
  alias Myrex.Types, as: T

  @spec parse(T.tokens()) :: T.root()
  def parse(toks) do
    postf = postf(toks, [:begin_sequence], 0, [])
    parse(postf, [])
  end

  @spec postfix(T.tokens()) :: T.tokens()
  def postfix(ast), do: postf(ast, [:begin_sequence], 0, [])

  # Pass 1 - convert to postfix operator form
  # Convert alternate `|` from binary infix to n-ary postfix.
  # Wrap the whole expression in an implied sequence, if necessary.
  # Add implied group boundaries for alternate arguments.

  @spec postf(T.tokens(), T.tokens(), T.count(), [T.count()]) :: T.tokens()

  defp postf([:alternate | toks], post, d, alts) do
    postf(toks, [:begin_sequence, :end_sequence | post], d, [d | alts])
  end

  defp postf([bg = {:begin_group, _} | toks], post, d, alts) do
    postf(toks, seek_alt(toks) ++ [bg | post], d + 1, alts)
  end

  defp postf([:end_group | toks], post, d, [d | alts]) do
    {n, rest} = heads(d, alts, 2)
    postf(toks, [:end_group, {:alternate, n}, :end_sequence | post], d - 1, rest)
  end

  defp postf([:end_group | toks], post, d, alts) do
    postf(toks, [:end_group | post], d - 1, alts)
  end

  defp postf([tok | toks], post, d, alts) do
    postf(toks, [tok | post], d, alts)
  end

  defp postf([], post, 0, []) do
    Enum.reverse([:end_sequence | post])
  end

  defp postf([], post, 0, zeroes) do
    Enum.reverse([{:alternate, 1 + length(zeroes)}, :end_sequence | post])
  end

  defp postf([], _, _, _) do
    raise ArgumentError, message: "Unbalanced groups"
  end

  # From begin_group scan ahead to find the end of the run:
  # either an end group; or an alternation sub-sequence.
  # The group will have a group node,
  # but the alternate needs an enclosing sequence.
  @spec seek_alt(T.tokens()) :: [] | [:begin_sequence]
  defp seek_alt([:end_group | _]), do: []
  defp seek_alt([:alternate | _]), do: [:begin_sequence]
  defp seek_alt([_ | toks]), do: seek_alt(toks)
  defp seek_alt([]), do: raise(ArgumentError, message: "Unmatched begin group")

  # scan from the start of the depth list counting repeated values
  @spec heads(T.count(), [T.count()], T.count()) :: {T.count(), [T.count()]}
  defp heads(d, [d | alts], n), do: heads(d, alts, n + 1)
  defp heads(_, alts, n), do: {n, alts}

  # Pass 2 - build the AST tree and return the root node
  # Root can be explicit branch node (e.g. group) or implied sequence

  @spec parse(T.tokens(), T.tokens()) :: T.root()

  defp parse([c | toks], stack) when is_char(c), do: parse(toks, [c | stack])
  defp parse([:any_char | toks], stack), do: parse(toks, [:any_char | stack])
  defp parse([:zero_one | toks], [node | stack]), do: parse(toks, [{:zero_one, node} | stack])
  defp parse([:one_more | toks], [node | stack]), do: parse(toks, [{:one_more, node} | stack])
  defp parse([:zero_more | toks], [node | stack]), do: parse(toks, [{:zero_more, node} | stack])

  defp parse([{:repeat, nrep} | toks], [node | stack]),
    do: parse(toks, [{:repeat, nrep, node} | stack])

  defp parse([:begin_class, :neg_class | toks], stack) do
    {rest, cc} = parse_cc(toks, [], :neg)
    parse(rest, [cc | stack])
  end

  defp parse([:begin_class | toks], stack) do
    {rest, cc} = parse_cc(toks, [], :pos)
    parse(rest, [cc | stack])
  end

  defp parse([{:begin_group, g} | toks], stack), do: parse(toks, [{:begin_group, g} | stack])

  defp parse([:end_group | toks], stack) do
    {pre, post, g} = pop_group([], stack)
    parse(toks, [{:group, g, pre} | post])
  end

  defp parse([:begin_sequence | toks], stack), do: parse(toks, [:begin_sequence | stack])

  defp parse([:end_sequence | toks], stack) do
    {pre, post} = pop_seq([], stack)
    # remove sequence for singleton
    if length(pre) == 1 do
      parse(toks, [hd(pre) | post])
    else
      parse(toks, [{:sequence, pre} | post])
    end
  end

  defp parse([{:alternate, n} | toks], stack) do
    {pre, post} = pop_n(n, [], stack)
    parse(toks, [{:alternate, pre} | post])
  end

  defp parse([{tag, _sign, _prop} = tok | toks], stack)
       when tag == :char_block or tag == :char_category or tag == :char_script do
    parse(toks, [tok | stack])
  end

  # any single node
  defp parse([], [node]), do: node

  # implied sequence
  defp parse([], nodes) when is_list(nodes), do: {:sequence, Enum.reverse(nodes)}

  # e.g. postf quantifier without target, like "+?*"
  defp parse([_ | _], _), do: raise(ArgumentError, message: "Parse error: illegal expression")

  # special restricted parser within character class
  @spec parse_cc(T.tokens(), [char() | T.char_pair() | T.char_property()], T.sign()) ::
          {T.tokens(), T.char_class()}

  defp parse_cc([c1, :range_to, c2 | toks], ccs, sign) when is_char(c1) and is_char(c2) do
    if c1 >= c2, do: raise(ArgumentError, message: "Parse error: illegal char range")
    parse_cc(toks, [{:char_range, c1, c2} | ccs], sign)
  end

  defp parse_cc([c | toks], ccs, sign) when is_char(c), do: parse_cc(toks, [c | ccs], sign)

  defp parse_cc([:any_char | toks], ccs, sign) do
    # error???
    IO.puts("Warning: any char wildcard '.' in character class - always passes or ^fails.")
    parse_cc(toks, [:any_char | ccs], sign)
  end

  defp parse_cc([{tag, _sign, _prop} = tok | toks], ccs, sign)
       when tag == :char_block or tag == :char_category or tag == :char_script do
    parse_cc(toks, [tok | ccs], sign)
  end

  defp parse_cc([:begin_class | _], _, _sign),
    do: raise(ArgumentError, message: "Parse error: unescaped '[' in character class")

  defp parse_cc([:neg_class | _], _, _sign),
    do: raise(ArgumentError, message: "Parse error: unescaped '^' in character class")

  defp parse_cc([:end_class | _], [], _sign),
    do: raise(ArgumentError, message: "Parse error: '[]' empty character class")

  defp parse_cc([:end_class | toks], ccs, sign),
    do: {toks, {:char_class, sign, Enum.reverse(ccs)}}

  defp parse_cc([_ | _], _, _),
    do: raise(ArgumentError, message: "Parse error: illegal char class")

  defp parse_cc([], _, _),
    do: raise(ArgumentError, message: "Parse error: missing end of char class ']'")

  # read a fixed number of nodes back from the stack
  # similar to lists:sublist
  @spec pop_n(T.count(), T.tokens(), T.tokens()) :: {T.tokens(), T.tokens()}
  defp pop_n(0, pre, post), do: {pre, post}
  defp pop_n(n, pre, [h | post]), do: pop_n(n - 1, [h | pre], post)
  defp pop_n(_, _, []), do: raise(ArgumentError, message: "Parse error: empty stack")

  # read a sequence back from the stack
  @spec pop_seq(T.tokens(), T.tokens()) :: {T.tokens(), T.tokens()}

  defp pop_seq([], [:begin_sequence | _]),
    do: raise(ArgumentError, message: "Parse error: empty sequence")

  defp pop_seq(pre, [:begin_sequence | post]), do: {pre, post}
  defp pop_seq(pre, [h | post]), do: pop_seq([h | pre], post)
  defp pop_seq(_, []), do: raise(ArgumentError, message: "Parse error: missing begin sequence")

  # read a group back from the stack
  @spec pop_group(T.tokens(), T.tokens()) :: {T.tokens(), T.tokens(), T.count1()}

  defp pop_group([], [{:begin_group, _} | _]),
    do: raise(ArgumentError, message: "Parse error: empty group '()'")

  defp pop_group(pre, [{:begin_group, g} | post]), do: {pre, post, g}
  defp pop_group(pre, [h | post]), do: pop_group([h | pre], post)
  defp pop_group(_, []), do: raise(ArgumentError, message: "Parse error: missing begin group '('")
end
