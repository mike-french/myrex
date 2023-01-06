defmodule Myrex.Uniset do
  @moduledoc """
  Utilities for sets of Unicode characters, blocks, scripts and categories.

  Converts data from the `Unicode` library into a format 
  that is convenient for picking a random character.
  """

  import Myrex.Types
  alias Myrex.Types, as: T

  alias Unicode.Block
  alias Unicode.GeneralCategory, as: Category
  alias Unicode.Script

  @typedoc "A run-length encoding of a character range."
  @type charun() :: {start :: char(), size :: T.count1()}
  @type charuns() :: [charun()]
  @type uniset() :: {:uni_set, size :: T.count1(), charuns()}

  # list of standard ascii whitespace characters
  @whitespace [?\s, ?\n, ?\r, ?\t, ?\v, ?\f]

  # TODO - find a way to cache large or composite unisets as module attributes
  # all, xan, xwd, xsp

  @doc """
  Create a new charset for all assigned Unicode characters.
  """
  @spec new() :: uniset()
  def new() do
    ranges = rle(Unicode.assigned())
    {:uni_set, count(ranges), ranges}
  end

  @doc """
  Create a new charset for a single character, list of characters 
  or character range tuple.
  """
  @spec new(char() | [char()] | T.char_pair()) :: uniset()

  def new(c) when is_char(c) do
    {:uni_set, 1, [{c, 1}]}
  end

  def new(cs) when is_list(cs) do
    # does not sort characters
    # does not attempt to merge contiguous character ranges
    {:uni_set, length(cs), Enum.map(cs, &{&1, 1})}
  end

  def new({c1, c2}) when is_char(c1) and is_char(c2) do
    n = c2 - c1 + 1
    {:uni_set, n, [{c1, n}]}
  end

  @doc """
  Create a new charset for a Unicode property defined by a tag and a name.
  """
  @spec new(T.property_tag(), atom()) :: uniset()

  def new(:char_block, block) when is_atom(block) do
    n = Block.count(block)
    ranges = block |> Block.get() |> rle()
    {:uni_set, n, ranges}
  end

  def new(:char_script, script) when is_atom(script) do
    n = Script.count(script)
    ranges = script |> Script.get() |> rle()
    {:uni_set, n, ranges}
  end

  def new(:char_category, :Xan) do
    union(new(:char_category, :L), new(:char_category, :N))
  end

  def new(:char_category, :Xwd) do
    union(new(:char_category, :Xan), new(?_))
  end

  def new(:char_category, :Xsp) do
    union(new(:char_category, :Z), new(@whitespace))
  end

  def new(:char_category, cat) when is_atom(cat) do
    n = Category.count(cat)
    ranges = cat |> Category.get() |> rle()
    {:uni_set, n, ranges}
  end

  # Convert range pairs to charun tuples containing a start character and a count.
  @spec rle([{char(), char()}], charuns()) :: charuns()
  defp rle(raw, out \\ [])
  defp rle([], rs), do: Enum.reverse(rs)
  defp rle([{i, i} | t], rs), do: rle(t, [{i, 1} | rs])
  defp rle([{i, j} | t], rs), do: rle(t, [{i, j - i + 1} | rs])

  @doc "Pick a random character from a charset."
  @spec pick(uniset()) :: char()
  def pick({:uni_set, 1, [{c, 1}]}), do: c
  def pick({:uni_set, n, ranges}), do: pick(ranges, :rand.uniform(n))

  @spec pick(charuns(), T.count1()) :: char()
  defp pick([{c, 1} | _rs], 1), do: c
  defp pick([{c, m} | _rs], n) when n <= m, do: c + n - 1
  defp pick([{_c, m} | rs], n), do: pick(rs, n - m)

  @doc "Pick a random character that is not in a charset."
  @spec pick_neg(uniset()) :: char()
  def pick_neg(uni) do
    # very slow, especially for large unisets, such as Lo - Other Letter
    c = pick(new())
    if not contains?(uni, c), do: c, else: pick_neg(uni)
  end

  @doc "Get the character count for a charset or a list of run-length encoded tuples."
  @spec count(uniset() | charuns()) :: T.count1()
  def count({:uni_set, n, _runs}), do: n
  def count(runs) when is_list(runs), do: sum(runs, 0)

  defp sum([], total), do: total
  defp sum([{_c, n} | rs], total), do: sum(rs, total + n)

  @doc "Union of two disjoint charsets."
  @spec union(uniset(), uniset()) :: uniset()
  def union({:uni_set, n1, rs1}, {:uni_set, n2, rs2}) do
    # assumes arguments are disjoint
    # final ranges are not sorted
    {:uni_set, n1 + n2, rs1 ++ rs2}
  end

  @doc "Test if a charset contains a character."
  @spec contains?(uniset(), char()) :: boolean()
  def contains?({:uni_set, _n, ranges}, c), do: in?(ranges, c)

  # slow linear scan - there are much faster data structures to do this
  @spec in?(uniset(), char()) :: boolean()
  defp in?([{i, n} | _rs], c) when i <= c and c <= i + n - 1, do: true
  defp in?([_ | rs], c), do: in?(rs, c)
  defp in?([], _c), do: false
end
