defmodule Myrex.ParserTest do
  use ExUnit.Case

  alias Myrex.AST
  alias Myrex.Lexer
  alias Myrex.Parser

  test "postfix" do
    postfix(
      "a|b",
      [:begin_sequence, ?a, :end_sequence, :begin_sequence, ?b, :end_sequence, {:alternate, 2}]
    )

    postfix(
      "a|bcd",
      [
        :begin_sequence,
        ?a,
        :end_sequence,
        :begin_sequence,
        ?b,
        ?c,
        ?d,
        :end_sequence,
        {:alternate, 2}
      ]
    )

    postfix(
      "ab|cd",
      [
        :begin_sequence,
        ?a,
        ?b,
        :end_sequence,
        :begin_sequence,
        ?c,
        ?d,
        :end_sequence,
        {:alternate, 2}
      ]
    )

    postfix(
      "a|b|c",
      [
        :begin_sequence,
        ?a,
        :end_sequence,
        :begin_sequence,
        ?b,
        :end_sequence,
        :begin_sequence,
        ?c,
        :end_sequence,
        {:alternate, 3}
      ]
    )

    postfix(
      "a|b|c|d",
      [
        :begin_sequence,
        ?a,
        :end_sequence,
        :begin_sequence,
        ?b,
        :end_sequence,
        :begin_sequence,
        ?c,
        :end_sequence,
        :begin_sequence,
        ?d,
        :end_sequence,
        {:alternate, 4}
      ]
    )

    postfix(
      "(a|b)",
      [
        :begin_sequence,
        {:begin_group, 1},
        :begin_sequence,
        ?a,
        :end_sequence,
        :begin_sequence,
        ?b,
        :end_sequence,
        {:alternate, 2},
        :end_group,
        :end_sequence
      ]
    )

    postfix(
      "(?:a|b)",
      [
        :begin_sequence,
        {:begin_group, :nocap},
        :begin_sequence,
        ?a,
        :end_sequence,
        :begin_sequence,
        ?b,
        :end_sequence,
        {:alternate, 2},
        :end_group,
        :end_sequence
      ]
    )

    postfix(
      "(a|b)|(c|d)",
      [
        :begin_sequence,
        {:begin_group, 1},
        :begin_sequence,
        ?a,
        :end_sequence,
        :begin_sequence,
        ?b,
        :end_sequence,
        {:alternate, 2},
        :end_group,
        :end_sequence,
        :begin_sequence,
        {:begin_group, 2},
        :begin_sequence,
        ?c,
        :end_sequence,
        :begin_sequence,
        ?d,
        :end_sequence,
        {:alternate, 2},
        :end_group,
        :end_sequence,
        {:alternate, 2}
      ]
    )
  end

  describe "parser" do
    test "par_char_test" do
      do_par("a", [?a])
      do_par("aabb", {:sequence, 'aabb'})
    end

    test "par_any_test" do
      do_par(".", :any_char)
      do_par("a.b", {:sequence, [?a, :any_char, ?b]})
    end

    test "par_quantifier_test" do
      do_par("a?", {:zero_one, ?a})
      do_par("a+", {:one_more, ?a})
      do_par("a*", {:zero_more, ?a})

      do_par("ba?c", {:sequence, [?b, {:zero_one, ?a}, ?c]})
      do_par("b.+c", {:sequence, [?b, {:one_more, :any_char}, ?c]})
      do_par("ba*c", {:sequence, [?b, {:zero_more, ?a}, ?c]})

      do_par("a?+", {:one_more, {:zero_one, ?a}})
      do_par("a+*", {:zero_more, {:one_more, ?a}})
      do_par("a*?", {:zero_one, {:zero_more, ?a}})

      bad_par("*a")
      bad_par("?b")
      bad_par("+c")
    end

    test "par_class_test" do
      do_par("[A-Z]", {:char_class, [{:char_range, ?A, ?Z}]})
      do_par("[_A-Z!]", {:char_class, [?_, {:char_range, ?A, ?Z}, ?!]})

      bad_par("[")
      bad_par("]")
      bad_par("[]")
      bad_par("[a*]")
      bad_par("[z-a]")
    end

    test "par_group_test" do
      do_par("(a)", {:group, 1, [?a]})
      do_par("(abc)", {:group, 1, [?a, ?b, ?c]})
      do_par("(ab*c)", {:group, 1, [?a, {:zero_more, ?b}, ?c]})

      do_par(
        "(a)(bc)",
        {:sequence,
         [
           {:group, 1, [?a]},
           {:group, 2, [?b, ?c]}
         ]}
      )

      do_par("((a))", {:group, 1, [{:group, 2, [?a]}]})
      do_par("(?:(ab))", {:group, :nocap, [{:group, 1, [?a, ?b]}]})

      bad_par(")")
      bad_par("(")
      bad_par("()")
      bad_par("((a)")
      bad_par("(a))")
    end

    test "par_repeat_test" do
      do_par("a{3}", {:repeat, 3, ?a})
      do_par("(ab){43}", {:repeat, 43, {:group, 1, [?a, ?b]}})

      bad_par("{2}")
    end

    test "par_alt_test" do
      do_par("a|b", {:alternate, [?a, ?b]})
      do_par("ab|cd", {:alternate, [{:sequence, [?a, ?b]}, {:sequence, [?c, ?d]}]})
      do_par("(b|c)", {:group, 1, [{:alternate, [?b, ?c]}]})
      do_par("a|b|c|d", {:alternate, [?a, ?b, ?c, ?d]})

      bad_par("|")
      bad_par("a|")
      bad_par("|b")
      bad_par("(|)")
      bad_par("a||b")
    end
  end

  defp do_par(re, ast) do
    IO.puts("")
    IO.inspect(re, label: "RE   ")
    IO.inspect(ast, label: "AST  ")
    expect = AST.ast2str(ast)
    IO.puts(expect)
    {toks, _} = Lexer.lex(re)
    IO.inspect(toks, label: "TOK  ")
    myast = Parser.parse(toks)
    IO.inspect(ast, label: "MYAST")
    mystr = AST.ast2str(myast)
    IO.puts(mystr)
    assert expect == mystr
  end

  defp bad_par(re) do
    {toks, _} = Lexer.lex(re)
    assert_raise ArgumentError, fn -> Parser.parse(toks) end
  end

  defp postfix(re, expect) do
    {toks, _} = Lexer.lex(re)
    IO.inspect(toks, label: "TOKS")
    tokstr = Lexer.tok2str(toks)
    IO.inspect("#{re} -> #{tokstr}")
    postfix = Parser.postfix(toks)
    poststr = Lexer.tok2str(postfix)
    IO.inspect("      -> #{poststr}")
    assert expect == postfix
  end
end
