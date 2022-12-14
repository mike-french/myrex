defmodule Myrex.LexerTest do
  use ExUnit.Case

  import Myrex.TestUtil

  alias Myrex.Lexer

  test "empty test" do
    bad_lex("")
  end

  test "lex char test" do
    equal("a", 'a')
    equal("aabb", 'aabb')
  end

  test "lex any test" do
    equal(".", [:any_char])
    equal("a.b", [?a, :any_char, ?b])
  end

  test "lex quantifier test" do
    equal("a?", [?a, :zero_one])
    equal("a+", [?a, :one_more])
    equal("a*", [?a, :zero_more])
  end

  test "lex seq test" do
    equal("ab", [?a, ?b])
    equal("abcd", [?a, ?b, ?c, ?d])
  end

  test "lex repeat test" do
    equal("{3}", [{:repeat, 3}])
    equal("{34}", [{:repeat, 34}])

    bad_lex("{")
    bad_lex("}")
    bad_lex("{}")
    bad_lex("{a}")
    bad_lex("{-1}")
  end

  test "lex class test" do
    equal("[", [:begin_class])
    equal("[^", [:begin_class, :neg_class])
    equal("]", [:end_class])
    equal("-", [:range_to])
    equal("[a-z]", [:begin_class, ?a, :range_to, ?z, :end_class])

    equal("[_a-zA-Z]", [:begin_class, ?_, ?a, :range_to, ?z, ?A, :range_to, ?Z, :end_class])

    equal("[^0-9]", [:begin_class, :neg_class, ?0, :range_to, ?9, :end_class])

    # no need to escape '^' in char class - accepted as char after 1st position??
    equal("[a^]]", [:begin_class, ?a, ?^, :end_class, :end_class])

    # illegal, but the parser's job to find it
    equal("[-]", [:begin_class, :range_to, :end_class])
  end

  test "lex esc test" do
    equal("\\*", [?*])
    equal("\\-", [?-])
    equal("\\.", [?.])
    equal("\\\\", [?\\])
    equal("a\\#", [?a, ?#])
    equal("\nb", [?\n, ?b])
    equal("\\nb", [?\n, ?b])
    equal("\t\r", [?\t, ?\r])
    equal("\\t\\r", [?\t, ?\r])

    equal("[\\[\\^\\-\\]]", [:begin_class, ?[, ?^, ?-, ?], :end_class])

    bad_lex("\\q")
    bad_lex("\\")
  end

  test "lex hex test" do
    # raw literal hex characters
    equal("\x61", [?a])
    equal("\x7A", [?z])
    equal("\x5a", [?Z])
    equal("\x5F", [?_])
    equal("\x2f", [?/])

    # explicitly escaped unicode characters using only ascii 
    equal("\\x61", [?a])
    equal("\\x7A", [?z])
    equal("\\x5a", [?Z])
    equal("\\x5F", [?_])
    equal("\\x2f", [?/])

    bad_lex("\\xGG")
    bad_lex("\\x+-")
  end

  test "lex uni test" do
    # raw literal unicode characters
    equal("\u0061", [?a])
    equal("\u007A", [?z])
    equal("\u005a", [?Z])
    equal("\u005F", [?_])
    equal("\u002f", [?/])

    equal("\u208a", [8330])
    equal("\u208B", [8331])
    equal("\u208C", [8332])

    # explicitly escaped unicode characters using only ascii 
    equal("\\u0061", [?a])
    equal("\\u007A", [?z])
    equal("\\u005a", [?Z])
    equal("\\u005F", [?_])
    equal("\\u002f", [?/])

    equal("\\u208a", [8330])
    equal("\\u208B", [8331])
    equal("\\u208C", [8332])

    bad_lex("\\u12")
    bad_lex("\\uEFGH")
    bad_lex("\\u123+")
  end

  test "unicode properties" do
    equal("\\p{Mathematical Operators}", [{:char_block, :pos, :mathematical_operators}])
    equal("\\p{Lu}", [{:char_category, :pos, :Lu}])
    equal("\\p{Signwriting}", [{:char_script, :pos, :signwriting}])

    # extension classes 
    equal("\\p{Xan}", [{:char_category, :pos, :Xan}])
    equal("\\p{Xsp}", [{:char_category, :pos, :Xsp}])
    equal("\\p{Xwd}", [{:char_category, :pos, :Xwd}])
    equal("\\w", [{:char_category, :pos, :Xwd}])
    equal("\\W", [{:char_category, :neg, :Xwd}])
    equal("\\s", [{:char_category, :pos, :Xsp}])
    equal("\\S", [{:char_category, :neg, :Xsp}])
    equal("\\d", [{:char_category, :pos, :Nd}])
    equal("\\D", [{:char_category, :neg, :Nd}])

    bad_lex("\\p{Xps}")
    bad_lex("\\p{Foo}")
  end

  test "lex group test" do
    equal("()", [{:begin_group, 1}, :end_group])
    equal("(ab)", [{:begin_group, 1}, ?a, ?b, :end_group])

    equal("(?:ab)", [{:begin_group, :nocap}, ?a, ?b, :end_group])
  end

  test "lex named group test" do
    equal("(?<foo>ab)", [{:begin_group, {1, "foo"}}, ?a, ?b, :end_group])
    equal("(?<bar_99>ab)", [{:begin_group, {1, "bar_99"}}, ?a, ?b, :end_group])

    bad_lex("(?<")
    bad_lex("(?<>ab)")
    bad_lex("(?<~!@#$%^>ab)")
  end

  test "lex nest test" do
    equal(
      "((a)((b)(c)))",
      [
        {:begin_group, 1},
        {:begin_group, 2},
        ?a,
        :end_group,
        {:begin_group, 3},
        {:begin_group, 4},
        ?b,
        :end_group,
        {:begin_group, 5},
        ?c,
        :end_group,
        :end_group,
        :end_group
      ]
    )

    equal(
      "a(b)?((cd)+ef)*",
      [
        ?a,
        {:begin_group, 1},
        ?b,
        :end_group,
        :zero_one,
        {:begin_group, 2},
        {:begin_group, 3},
        ?c,
        ?d,
        :end_group,
        :one_more,
        ?e,
        ?f,
        :end_group,
        :zero_more
      ]
    )
  end

  test "lex alt test" do
    equal("a|b", [?a, :alternate, ?b])
    equal("a|bcd", [?a, :alternate, ?b, ?c, ?d])
    equal("ab|cd", [?a, ?b, :alternate, ?c, ?d])

    equal(
      "(a|b)",
      [{:begin_group, 1}, ?a, :alternate, ?b, :end_group]
    )

    equal(
      "(a)|bcd",
      [{:begin_group, 1}, ?a, :end_group, :alternate, ?b, ?c, ?d]
    )

    equal(
      "a|(bcd)",
      [?a, :alternate, {:begin_group, 1}, ?b, ?c, ?d, :end_group]
    )
  end

  defp equal(re, toks), do: assert(toks == lex(re))

  defp lex(re) do
    toks = Lexer.lex(re)
    dump(toks, label: "TOKS")
    mystr = Lexer.tok2str(toks)
    dump("#{re} -> #{mystr}")
    toks
  end

  defp bad_lex(re), do: assert_raise(ArgumentError, fn -> lex(re) end)
end
