defmodule Myrex.Lexer do
  @moduledoc """
  Convert a regular expression string into
  a list of tokens and raw characters.
  """

  import Myrex.Types
  alias Myrex.Types, as: T

  # future ^ $
  @escape '.*+?|(){}[]-\\'

  @blocks Unicode.Block.known_blocks()
  @categories Unicode.GeneralCategory.known_categories()
  @scripts Unicode.Script.known_scripts()

  # ascii definitions as guards for lexing the REGEX
  # not character categories for runtime matching of inputs
  defguard is_ascii(c) when is_integer(c) and c > 0 and c < 128
  defguard is_alpha(c) when (c >= ?a and c <= ?z) or (c >= ?A and c <= ?Z)
  defguard is_digit(c) when c >= ?0 and c <= ?9
  defguard is_hex(c) when is_digit(c) or (c >= ?a and c <= ?f) or (c >= ?A and c <= ?F)
  defguard is_named(c) when is_alpha(c) or is_digit(c) or c == ?_

  @doc """
  Convert a regular expression string to a list of tokens and characters.
  """
  @spec lex(String.t()) :: {T.tokens(), T.count()}

  def lex("") do
    raise ArgumentError, message: "Empty regular expression argument"
  end

  def lex(re) when is_binary(re) do
    re |> String.to_charlist() |> re2tok([], 1)
  end

  @spec re2tok(charlist(), T.tokens(), T.count()) :: T.tokens()

  defp re2tok([?\\, c | t], toks, g) when not is_alpha(c), do: re2tok(t, [c | toks], g)

  defp re2tok([?\\, ?a | t], toks, g), do: re2tok(t, [?\a | toks], g)
  defp re2tok([?\\, ?b | t], toks, g), do: re2tok(t, [?\b | toks], g)
  defp re2tok([?\\, ?e | t], toks, g), do: re2tok(t, [?\e | toks], g)
  defp re2tok([?\\, ?f | t], toks, g), do: re2tok(t, [?\f | toks], g)
  defp re2tok([?\\, ?n | t], toks, g), do: re2tok(t, [?\n | toks], g)
  defp re2tok([?\\, ?r | t], toks, g), do: re2tok(t, [?\r | toks], g)
  # not a single space, but the char class of whitespace characters
  # defp re2tok([?\\, ?s | t], toks, g), do: re2tok(t, [?\s | toks], g)
  defp re2tok([?\\, ?t | t], toks, g), do: re2tok(t, [?\t | toks], g)
  # not a single vertical space, but the char class of vertical space characters
  # defp re2tok([?\\, ?v | t], toks, g), do: re2tok(t, [?\v | toks], g)

  # map escaped char classes to unicode char classes
  defp re2tok([?\\, ?d | t], toks, g), do: re2tok([?\\, ?p, ?{, ?N, ?d, ?} | t], toks, g)
  defp re2tok([?\\, ?D | t], toks, g), do: re2tok([?\\, ?P, ?{, ?N, ?d, ?} | t], toks, g)
  defp re2tok([?\\, ?w | t], toks, g), do: re2tok([?\\, ?p, ?{, ?X, ?w, ?d, ?} | t], toks, g)
  defp re2tok([?\\, ?W | t], toks, g), do: re2tok([?\\, ?P, ?{, ?X, ?w, ?d, ?} | t], toks, g)

  defp re2tok([?\\, ?p, ?{ | t], toks, g) do
    {cctok, rest} = property(t, '', :pos)
    re2tok(rest, [cctok | toks], g)
  end

  defp re2tok([?\\, ?P, ?{ | t], toks, g) do
    {cctok, rest} = property(t, '', :neg)
    re2tok(rest, [cctok | toks], g)
  end

  defp re2tok([?. | t], toks, g), do: re2tok(t, [:any_char | toks], g)
  defp re2tok([?? | t], toks, g), do: re2tok(t, [:zero_one | toks], g)
  defp re2tok([?+ | t], toks, g), do: re2tok(t, [:one_more | toks], g)
  defp re2tok([?* | t], toks, g), do: re2tok(t, [:zero_more | toks], g)
  defp re2tok([?| | t], toks, g), do: re2tok(t, [:alternate | toks], g)

  defp re2tok([?(, ??, ?: | t], toks, g), do: re2tok(t, [{:begin_group, :nocap} | toks], g)

  defp re2tok([?(, ??, ?< | t], toks, g) do
    {name, rest} = name(t, '')
    re2tok(rest, [{:begin_group, {g, name}} | toks], g + 1)
  end

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

  defp re2tok([], toks, _g), do: Enum.reverse(toks)

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

  # Read the name of a capture
  @spec name(charlist(), charlist()) :: {String.t(), charlist()}

  defp name([?> | _], []),
    do: raise(ArgumentError, message: "Lexer error: empty group name '<>'")

  defp name([?> | t], cs), do: {to_string(Enum.reverse(cs)), t}

  defp name([c | t], cs) when is_named(c), do: name(t, [c | cs])

  defp name([c | _], _cs),
    do: raise(ArgumentError, message: "Lexer error: illegal group name character '#{c}'")

  defp name([], _cs),
    do: raise(ArgumentError, message: "Lexer error: group name must be closed with '>'")

  # Read the property of a unicode character set
  @spec property(charlist(), charlist(), T.sign()) :: {T.char_property(), charlist()}

  defp property([?} | _], [], _sign),
    do: raise(ArgumentError, message: "Lexer error: empty property name '{}'")

  defp property([?} | t], cs, sign) do
    prop_str = cs |> Enum.reverse() |> to_string()
    prop = prop_str |> String.to_atom()

    cond do
      # compound extension classes that can only be interpreted by the parser
      # because it knows the context: inside or outside a char class 
      prop in [:Xan, :Xwd] ->
        {{:char_category, sign, prop}, t}

      # categories are short case-sensitive strings, so take them literally
      prop in @categories ->
        {{:char_category, sign, prop}, t}

      true ->
        # allow uppercase and spaces in blocks and scripts
        prop = prop_str |> String.downcase() |> String.replace(" ", "_") |> String.to_atom()

        # HACK ALERT - there are many blocks that are also scripts
        # match block first to get the broadest definition
        cond do
          prop in @blocks -> {{:char_block, sign, prop}, t}
          prop in @scripts -> {{:char_script, sign, prop}, t}
          true -> raise ArgumentError, message: "Lexer error: invalid unicode property '#{prop}'"
        end
    end
  end

  defp property([c | t], cs, sign) when is_alpha(c) or c == ?_ or c == ?\s,
    do: property(t, [c | cs], sign)

  defp property([c | _], _cs, _sign),
    do: raise(ArgumentError, message: "Lexer error: illegal property name character '#{c}'")

  defp property([], _cs, _sign),
    do: raise(ArgumentError, message: "Lexer error: property name must be closed with '}'")

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

  defp tok2re([{:begin_group, :nocap} | toks], re), do: tok2re(toks, [?(, ??, ?: | re])

  defp tok2re([{:begin_group, {_g, name}} | toks], re),
    do: tok2re(toks, [?(, ??, ?<, name, ?> | re])

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

  defp tok2str([?\a | toks], strs), do: tok2str(toks, [?\\, ?a | strs])
  defp tok2str([?\b | toks], strs), do: tok2str(toks, [?\\, ?b | strs])
  defp tok2str([?\e | toks], strs), do: tok2str(toks, [?\\, ?e | strs])
  defp tok2str([?\f | toks], strs), do: tok2str(toks, [?\\, ?f | strs])
  defp tok2str([?\n | toks], strs), do: tok2str(toks, [?\\, ?n | strs])
  defp tok2str([?\r | toks], strs), do: tok2str(toks, [?\\, ?r | strs])
  # defp tok2str([?\s | toks], strs), do: tok2str(toks, [?\\, ?s | strs])
  defp tok2str([?\t | toks], strs), do: tok2str(toks, [?\\, ?t | strs])
  # defp tok2str([?\v | toks], strs), do: tok2str(toks, [?\\, ?v | strs])

  defp tok2str([c | toks], strs) when is_char(c) and c > 128,
    do: tok2str(toks, [?\s, ?', ?\\, ?u, Integer.to_charlist(c, 16), ?' | strs])

  defp tok2str([c | toks], strs) when is_char(c),
    # TODO - escape unicode chars \uHHHH
    do: tok2str(toks, [?\s, ?', c, ?' | strs])

  defp tok2str([{:begin_group, :nocap} | toks], strs),
    do: tok2str(toks, ["{begin_group, nocap} " | strs])

  defp tok2str([{:begin_group, {_g, name}} | toks], strs) when is_binary(name),
    do: tok2str(toks, [?\s, ?}, ?', name, "{begin_group,'" | strs])

  defp tok2str([{:begin_group, g} | toks], strs) when is_count(g),
    do: tok2str(toks, [?\s, ?}, Integer.to_charlist(g), "{begin_group," | strs])

  defp tok2str([{:alternate, nalt} | toks], strs) when is_integer(nalt),
    do: tok2str(toks, [?\s, ?}, Integer.to_charlist(nalt), "{alternate," | strs])

  defp tok2str([{:repeat, nrep} | toks], strs) when is_integer(nrep),
    do: tok2str(toks, [?\s, ?}, Integer.to_charlist(nrep), "{repeat," | strs])

  defp tok2str([{tag, :pos, prop} | toks], strs)
       when (tag == :char_block or tag == :char_category or tag == :char_script) and is_atom(prop) do
    tok2str(toks, [?}, Atom.to_string(prop), "\\p{" | strs])
  end

  defp tok2str([{tag, :neg, prop} | toks], strs)
       when (tag == :char_block or tag == :char_category or tag == :char_script) and is_atom(prop) do
    tok2str(toks, [?}, Atom.to_string(prop), "\\P{" | strs])
  end

  defp tok2str([], strs), do: strs |> Enum.reverse() |> List.flatten()

  defp tok2str([h | _], _),
    do: raise(ArgumentError, message: "Unexpected lexical element #{inspect(h)}")
end
