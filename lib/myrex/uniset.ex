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

  @typedoc """
  A run-length encoding of a character range.

  There is a special flag for the full assigned character set.
  """
  @type charun() :: {start :: char(), size :: T.count1()}
  @type charuns() :: [charun()]
  @type uniset() :: {:uni_set | :uni_all, size :: T.count(), charuns()}

  @type t() :: uniset()

  # list of standard ascii whitespace characters
  @whitespace [?\s, ?\n, ?\r, ?\t, ?\v, ?\f]

  # maximum character value
  @maxchar 0x10FFFF

  # surrogate codes are included in the Unicode library assigned set
  # but are not recognized as valid UTF8 characters by Erlang
  defguard is_surrogate(c) when 0xD800 <= c and c <= 0xDFFF

  # TODO - find a way to cache large or composite unisets as module attributes
  # all, xan, xwd, xsp

  @doc """
  Create a new charset for a single character, list of characters,
  character range tuple, all characters, or none.
  """
  @spec new(:none | :all | char() | [char()] | T.char_pair()) :: uniset()

  def new(:all) do
    ranges = rle(Unicode.assigned())
    {:uni_all, count(ranges), ranges}
  end

  def new(:none) do
    {:uni_set, 0, []}
  end

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

  def new(:char_category, :Any) do
    new(:all)
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
  def pick({_uni_set, 1, [{c, 1}]}), do: c

  def pick({_uni_set, n, ranges} = uni) do
    c = :rand.uniform(n)
    # filter out surrogates
    # will infinite loop if the arg uniset is just surrogate blocks
    if is_surrogate(c), do: pick(uni), else: pick(ranges, c)
  end

  @spec pick(charuns(), T.count1()) :: char()
  defp pick([{c, 1} | _rs], 1), do: c
  defp pick([{c, m} | _rs], n) when n <= m, do: c + n - 1
  defp pick([{_c, m} | rs], n), do: pick(rs, n - m)

  @doc "Pick a random character that is not in a charset."
  @spec pick_neg(uniset()) :: nil | char()

  def pick_neg({:uni_all, _, _}) do
    nil
  end

  def pick_neg(uni) do
    # very slow, especially for large unisets, such as Lo - Other Letter
    # or double negative of a small uniset, such as [^\P{}]
    c = pick(new(:all))
    # check membership and remove surrogates
    if not contains?(uni, c) and not is_surrogate(c), do: c, else: pick_neg(uni)
  end

  @doc "Get the character count for a charset or a list of run-length encoded tuples."
  @spec count(uniset() | charuns()) :: T.count1()
  def count({_uni_set, n, _runs}), do: n
  def count(runs) when is_list(runs), do: sum(runs, 0)

  defp sum([], total), do: total
  defp sum([{_c, n} | rs], total), do: sum(rs, total + n)

  @doc "Union of two disjoint charsets."
  @spec union(uniset(), uniset()) :: uniset()

  def union({:uni_all, _, _} = all, _) do
    all
  end

  def union(_, {:uni_all, _, _} = all) do
    all
  end

  def union({:uni_set, n1, runs1}, {:uni_set, n2, runs2}) do
    # assumes arguments are disjoint
    # final ranges are not sorted
    # no check for constructing all chars
    {:uni_set, n1 + n2, runs1 ++ runs2}
  end

  @doc """
  Complement (negation) of a charset.

  The result will contain unassigned characters
  within the legal integer range of character values.
  """
  @spec complement(uniset()) :: uniset()

  def complement({:uni_all, _, _}), do: new(:none)
  def complement({:uni_set, 0, []}), do: new(:all)

  def complement({:uni_set, _n, runs}) do
    # sorting is usually redundant here
    # but is needed for composite extended properties Xyz
    # because union does not sort its output
    # and it would be inefficient if it did 
    # so localize the inefficiency here
    # only for double negated char class properties (rare)
    runs = gaps(Enum.sort(runs), 0, [])
    {:uni_set, count(runs), runs}
  end

  # calculate the gaps in a run-length encoding
  # hwm is the high water mark
  # meaning the next value above the previous gap

  defp gaps([{hwm, n} | rs], hwm, runs) do
    gaps(rs, hwm + n, runs)
  end

  defp gaps([{i, n} | rs], hwm, runs) when i > hwm do
    gaps(rs, i + n, [{hwm, i - hwm} | runs])
  end

  defp gaps([], hwm, runs) when hwm < @maxchar do
    [{hwm, @maxchar - hwm} | runs]
  end

  @doc """
  Test if a charset contains a character.

  Can test false for legal char integer value in `.` or `\\p{Any}` set, 
  because not all codepoints are assigned.
  """
  @spec contains?(uniset(), char()) :: boolean()
  def contains?({_uni_set, _n, ranges}, c), do: in?(ranges, c)

  # slow linear scan - there are much faster data structures to do this
  @spec in?(uniset(), char()) :: boolean()
  defp in?([{i, n} | _rs], c) when i <= c and c <= i + n - 1, do: true
  defp in?([_ | rs], c), do: in?(rs, c)
  defp in?([], _c), do: false
end
