defmodule Myrex.Lexer do
  @moduledoc """
  Convert a regular expression string into
  a list of tokens and raw characters.
  """

  import Myrex.Types
  alias Myrex.Types, as: T

  # future ^ $
  @escape '.*+?|(){}[]-\\'

  defguard is_ascii(c) when is_integer(c) and c > 0 and c < 128
  defguard is_alpha(c) when (c >= ?a and c <= ?z) or (c >= ?A and c <= ?Z)
  defguard is_digit(c) when c >= ?0 and c <= ?9
  defguard is_hex(c) when is_digit(c) or (c >= ?a and c <= ?f) or (c >= ?A and c <= ?F)

  @doc """
  Convert a regular expression string to a list of tokens and characters.

  Also return a count of the number of explicit groups in the regular expression.
  """
  @spec lex(String.t()) :: {T.tokens(), T.count()}

  def lex("") do
    raise ArgumentError, message: "Empty regular expression argument"
  end

  def lex(re) when is_binary(re) do
    re |> String.to_charlist() |> re2tok([], 1)
  end

  @spec re2tok(charlist(), T.tokens(), T.count()) :: {T.tokens(), T.count()}

  defp re2tok([?\\, c | t], toks, g) when not is_alpha(c), do: re2tok(t, [c | toks], g)

  defp re2tok([?\\, ?e | t], toks, g), do: re2tok(t, [?\e | toks], g)
  defp re2tok([?\\, ?f | t], toks, g), do: re2tok(t, [?\f | toks], g)
  defp re2tok([?\\, ?n | t], toks, g), do: re2tok(t, [?\n | toks], g)
  defp re2tok([?\\, ?r | t], toks, g), do: re2tok(t, [?\r | toks], g)
  defp re2tok([?\\, ?t | t], toks, g), do: re2tok(t, [?\t | toks], g)
  defp re2tok([?\\, ?v | t], toks, g), do: re2tok(t, [?\v | toks], g)

  defp re2tok([?. | t], toks, g), do: re2tok(t, [:any_char | toks], g)
  defp re2tok([?? | t], toks, g), do: re2tok(t, [:zero_one | toks], g)
  defp re2tok([?+ | t], toks, g), do: re2tok(t, [:one_more | toks], g)
  defp re2tok([?* | t], toks, g), do: re2tok(t, [:zero_more | toks], g)
  defp re2tok([?| | t], toks, g), do: re2tok(t, [:alternate | toks], g)

  defp re2tok([?(, ??, ?: | t], toks, g), do: re2tok(t, [{:begin_group, :nocap} | toks], g)
  defp re2tok([?( | t], toks, g), do: re2tok(t, [{:begin_group, g} | toks], g + 1)
  defp re2tok([?) | t], toks, g), do: re2tok(t, [:end_group | toks], g)

  defp re2tok([?[, ?^ | t], toks, g), do: re2tok(t, [:neg_class, :begin_class | toks], g)
  defp re2tok([?[ | t], toks, g), do: re2tok(t, [:begin_class | toks], g)
  defp re2tok([?] | t], toks, g), do: re2tok(t, [:end_class | toks], g)
  defp re2tok([?- | t], toks, g), do: re2tok(t, [:range_to | toks], g)

  defp re2tok([?{ | t], toks, g) do
    {rest, repeat} = repeat(t, [])
    re2tok(rest, [repeat | toks], g)
  end

  defp re2tok([?} | _], _, _), do: raise(ArgumentError, message: "Unmatched end repeat '}'")
  defp re2tok([c | t], toks, g) when c != ?\\, do: re2tok(t, [c | toks], g)

  # defp re2tok([?\\, ?x, ?{ | t], toks, g) do
  #   {rest, hex} = hex(t, [])
  #   re2tok(rest, [hex | toks], g)
  # end

  defp re2tok([?\\, ?x, h1, h2 | t], toks, g) when is_hex(h1) and is_hex(h2) do
    hex = List.to_integer([h1, h2], 16)
    re2tok(t, [hex | toks], g)
  end

  defp re2tok([?\\, ?u, h1, h2, h3, h4 | t], toks, g)
       when is_hex(h1) and is_hex(h2) and is_hex(h3) and is_hex(h4) do
    hex = List.to_integer([h1, h2, h3, h4], 16)
    re2tok(t, [hex | toks], g)
  end

  defp re2tok([?\\, c | _], _, _),
    do: raise(ArgumentError, message: "Illegal escape character '#{c}'")

  defp re2tok([?\\], _, _),
    do: raise(ArgumentError, message: "Expecting escaped character after '\\'")

  defp re2tok([], toks, g), do: {Enum.reverse(toks), g - 1}

  # Read a hex value.
  # @spec hex(charlist(), charlist()) :: {charlist(), char()}
  # defp hex([h | t], hex) when is_hex(h), do: hex(t, [h | hex])
  # defp hex([?} | t], hex), do: {t, hex |> Enum.reverse() |> List.to_integer(16)}
  # defp hex([c | _], _), do: raise(ArgumentError, message: "Illegal hex character '#{c}'")
  # defp hex([], _), do: raise(ArgumentError, message: "Unfinished hex value, expecting '}'")

  # Read a repeat quantifier.
  @spec repeat(charlist(), charlist()) :: {charlist(), {:repeat, pos_integer()}}

  defp repeat([c | t], digits) when is_digit(c), do: repeat(t, [c | digits])

  defp repeat([?} | _], []), do: raise(ArgumentError, message: "Lexer error: empty repeat '{}'")

  defp repeat([?} | t], digits) do
    nrep = List.to_integer(Enum.reverse(digits))

    if nrep < 2, do: raise(ArgumentError, message: "Illegal repeat count #{nrep}")
    {t, {:repeat, nrep}}
  end

  defp repeat([c | _], _),
    do: raise(ArgumentError, message: "Lexer error: illegal repeat character '#{c}'")

  defp repeat([], _), do: raise(ArgumentError, message: "Lexer error: missing end repeat '}'")

  @doc """
  Convert a list of lexical tokens
  back to a regular expression string.
  """
  @spec tok2re(T.tokens()) :: String.t()
  def tok2re(toks), do: tok2re(toks, [])

  # Convert a list of lexical tokens to a regular expression string.
  @spec tok2re(T.tokens(), charlist()) :: String.t()

  defp tok2re([c | toks], re) when is_char(c) and c in @escape, do: tok2re(toks, [c, ?\\ | re])
  defp tok2re([c | toks], re) when is_char(c), do: tok2re(toks, [c | re])

  defp tok2re([:begin_sequence | toks], re), do: tok2re(toks, re)
  defp tok2re([:end_sequence | toks], re), do: tok2re(toks, re)

  defp tok2re([a | toks], re) when is_atom(a), do: tok2re(toks, [chr(a) | re])

  defp tok2re([{:begin_group, :nocap} | toks], re),
    do: tok2re(toks, [?(, ??, ?: | re])

  defp tok2re([{:begin_group, _} | toks], re), do: tok2re(toks, [?( | re])

  defp tok2re([{:repeat, nrep} | toks], re) do
    repeat = [?}] ++ Enum.reverse(Integer.to_charlist(nrep)) ++ [?{]
    tok2re(toks, repeat ++ re)
  end

  defp tok2re([], re), do: re |> Enum.reverse() |> to_string()
  defp tok2re([_ | _], _), do: raise(ArgumentError, message: "Unexpected lexical element")

  # Convert a token atom to a character.
  @spec chr(T.token() | :begin_group) :: char() | String.t()

  defp chr(:any_char), do: ?.
  defp chr(:zero_more), do: ?*
  defp chr(:one_more), do: ?+
  defp chr(:zero_one), do: ??
  defp chr(:alternate), do: ?|
  defp chr(:begin_group), do: ?(
  defp chr(:end_group), do: ?)
  defp chr(:begin_class), do: ?[
  defp chr(:neg_class), do: ?^
  defp chr(:end_class), do: ?]
  defp chr(:range_to), do: ?-
  defp chr(:begin_repeat), do: ?{
  defp chr(:end_repeat), do: ?}

  @doc """
  Convert a list of lexical tokens
  to a printable string.
  """
  @spec tok2str(T.tokens()) :: String.t()
  def tok2str(toks), do: toks |> tok2str([]) |> to_string()

  @spec tok2str(T.tokens(), charlist()) :: charlist()
  # include the parsed {repeat,N} and {begin_group,G}
  # also allow the special 'postfix' {alternate,N} form
  # so it will work with output from the first parser pass

  defp tok2str([a | toks], strs) when is_atom(a),
    do: tok2str(toks, [?\s, Atom.to_charlist(a) | strs])

  defp tok2str([?\e | toks], strs), do: tok2str(toks, [?\\, ?e | strs])
  defp tok2str([?\f | toks], strs), do: tok2str(toks, [?\\, ?f | strs])
  defp tok2str([?\n | toks], strs), do: tok2str(toks, [?\\, ?n | strs])
  defp tok2str([?\r | toks], strs), do: tok2str(toks, [?\\, ?r | strs])
  defp tok2str([?\t | toks], strs), do: tok2str(toks, [?\\, ?t | strs])
  defp tok2str([?\v | toks], strs), do: tok2str(toks, [?\\, ?v | strs])

  defp tok2str([c | toks], strs) when is_char(c),
    # TODO - escape unicode chars \uHHHH
    do: tok2str(toks, [?\s, ?', c, ?' | strs])

  defp tok2str([{:begin_group, g} | toks], strs) when is_count(g),
    do: tok2str(toks, [?\s, ?}, Integer.to_charlist(g), "{begin_group," | strs])

  defp tok2str([{:begin_group, :nocap} | toks], strs),
    do: tok2str(toks, ["{begin_group, nocap} " | strs])

  defp tok2str([{:alternate, nalt} | toks], strs) when is_integer(nalt),
    do: tok2str(toks, [?\s, ?}, Integer.to_charlist(nalt), "{alternate," | strs])

  defp tok2str([{:repeat, nrep} | toks], strs) when is_integer(nrep),
    do: tok2str(toks, [?\s, ?}, Integer.to_charlist(nrep), "{repeat," | strs])

  defp tok2str([], strs), do: strs |> Enum.reverse() |> List.flatten()

  defp tok2str([h | _], _), do: raise(ArgumentError, message: "Unexpected lexical element #{h}")
end
