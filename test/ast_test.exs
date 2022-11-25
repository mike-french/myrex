defmodule Myrex.ASTTest do
  use ExUnit.Case

  alias Myrex.AST

  test "chars" do
    do_ast("a", 'a')
    do_ast("\\n", '\n')
    # do_ast("\\u00A3", "\\u00A3")
    # do_ast("\\u02DF", "\u02DF")
    # do_ast("\\u540D", "\u540D")
    do_ast(".", :any_char)
    do_ast("aabb", {:sequence, 'aabb'})
  end

  test "any char" do
    do_ast(".", [:any_char])
    do_ast("a.b", [?a, :any_char, ?b])
  end

  test "quantifiers" do
    do_ast("a?", {:zero_one, ?a})
    do_ast("a+", {:one_more, ?a})
    do_ast("a*", {:zero_more, ?a})
  end

  test "group" do
    do_ast("(a)", {:group, 1, 'a'})
    do_ast("(abc)", {:group, 1, 'abc'})
    do_ast("(ab*c)", {:group, 1, [?a, {:zero_more, ?b}, ?c]})
    do_ast("(abc)*", {:zero_more, {:group, 1, 'abc'}})

    do_ast("(?:abc)", {:group, :nocap, 'abc'})
    do_ast("(?<foo>abc)", {:group, {1, "foo"}, 'abc'})
    do_ast("(?<bar_99>abc)", {:group, {1, "bar_99"}, 'abc'})
  end

  test "repeat" do
    do_ast("a{3}", {:repeat, 3, ?a})
    do_ast("(ab){3}", {:repeat, 3, {:group, 1, [?a, ?b]}})
  end

  test "char classes" do
    do_ast("[_A-Z]", {:char_class, [?_, {:char_range, ?A, ?Z}]})
    do_ast("[\\0-\\n]", {:char_class, [{:char_range, ?\0, ?\n}]})

    do_ast("[^0-9]", {:char_class_neg, [{:char_range, ?0, ?9}]})
  end

  test "choice" do
    do_ast("a|b", {:alternate, [?a, ?b]})
    do_ast("a|b|c|d", {:alternate, [?a, ?b, ?c, ?d]})

    do_ast(
      "(a|b)|(c|d)",
      {:alternate,
       [
         {:group, 1, [{:alternate, [?a, ?b]}]},
         {:group, 2, [{:alternate, [?c, ?d]}]}
       ]}
    )
  end

  defp do_ast(re, ast) do
    IO.inspect(re, label: "RE")
    IO.inspect(ast, label: "AST")

    myre = AST.ast2re(ast)
    assert re == myre

    mystr = AST.ast2str(ast)
    IO.puts(mystr)
  end
end
