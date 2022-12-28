defmodule Myrex.GeneratorTest do
  use ExUnit.Case

  import Myrex.TestUtil

  test "gen char test" do
    set_dump(true)
    do_gen("a")
    do_gen("aabb")
    set_dump(false)
  end

  test "gen char range test" do
    set_dump(true)
    do_gen("[a-z]")
    do_gen("[0-9]")
    do_gen("[abc0-9]")
    set_dump(false)
  end

  # test "par any test" do
  #   do_par(".", :any_char)
  #   do_par("a.b", {:sequence, [?a, :any_char, ?b]})
  # end

  # test "par unicode property test" do
  #   do_par("\\p{Mathematical Operators}", {:char_block, :pos, :mathematical_operators})
  #   do_par("\\p{Lu}", [{:char_category, :pos, :Lu}])
  #   do_par("\\p{Signwriting}", [{:char_script, :pos, :signwriting}])
  # end

  # test "par quantifier test" do
  #   do_par("a?", {:zero_one, ?a})
  #   do_par("a+", {:one_more, ?a})
  #   do_par("a*", {:zero_more, ?a})

  #   do_par("ba?c", {:sequence, [?b, {:zero_one, ?a}, ?c]})
  #   do_par("b.+c", {:sequence, [?b, {:one_more, :any_char}, ?c]})
  #   do_par("ba*c", {:sequence, [?b, {:zero_more, ?a}, ?c]})

  #   do_par("a?+", {:one_more, {:zero_one, ?a}})
  #   do_par("a+*", {:zero_more, {:one_more, ?a}})
  #   do_par("a*?", {:zero_one, {:zero_more, ?a}})

  #   bad_par("*a")
  #   bad_par("?b")
  #   bad_par("+c")
  # end

  # test "par class test" do
  #   do_par("[A-Z]", {:char_class, :pos, [{:char_range, ?A, ?Z}]})
  #   do_par("[_A-Z!]", {:char_class, :pos, [?_, {:char_range, ?A, ?Z}, ?!]})

  #   # anychar allowed in character class? always passes
  #   do_par("[.]", {:char_class, :pos, [:any_char]})

  #   do_par(
  #     "[\\p{Mathematical Operators}]",
  #     {:char_class, :pos, [{:char_block, :pos, :mathematical_operators}]}
  #   )

  #   do_par("[\\p{Lu}]", {:char_class, :pos, [{:char_category, :pos, :Lu}]})
  #   do_par("[\\p{Cyrillic}]", {:char_class, :pos, [{:char_script, :pos, :cyrillic}]})

  #   do_par("[^#0-9~]", {:char_class, :neg, [?#, {:char_range, ?0, ?9}, ?~]})

  #   # anychar allowed in negated character class? never passes
  #   do_par("[^.]", {:char_class, :neg, [:any_char]})

  #   # escape '[' in char class
  #   do_par("[\\[\\^\\-\\]]", {:char_class, :pos, [?[, ?^, ?-, ?]]})

  #   # no need to escape '[' '^' in char class??
  #   do_par("[a^]", {:char_class, :pos, [?a, ?^]})
  #   do_par("[^^]", {:char_class, :neg, [?^]})
  #   do_par("[^a^]", {:char_class, :neg, [?a, ?^]})

  #   bad_par("[")
  #   bad_par("]")
  #   bad_par("[]")
  #   bad_par("[]]")
  #   bad_par("[-z]")
  #   bad_par("[a-]")
  #   bad_par("[a*]")
  #   bad_par("[z-a]")

  #   bad_par("[^]")
  # end

  # test "par extension classes" do
  #   do_par("[\\p{Xan}]", {:char_class, :pos, [{:char_category, :pos, :Xan}]}, false)
  #   do_par("[\\P{Xwd}]", {:char_class, :pos, [{:char_category, :neg, :Xwd}]}, false)
  #   do_par("\\p{Xwd}", {:char_category, :pos, :Xwd}, false)
  #   do_par("\\P{Xsp}", {:char_category, :neg, :Xsp}, false)
  # end

  # test "par group test" do
  #   do_par("(a)", {:group, 1, [?a]})
  #   do_par("(abc)", {:group, 1, [?a, ?b, ?c]})
  #   do_par("(ab*c)", {:group, 1, [?a, {:zero_more, ?b}, ?c]})

  #   do_par(
  #     "(a)(bc)",
  #     {:sequence,
  #      [
  #        {:group, 1, [?a]},
  #        {:group, 2, [?b, ?c]}
  #      ]}
  #   )

  #   do_par("((a))", {:group, 1, [{:group, 2, [?a]}]})

  #   do_par("(?:(ab))", {:group, :nocap, [{:group, 1, [?a, ?b]}]})

  #   do_par("(?<foo>ab)", {:group, {1, "foo"}, [?a, ?b]})
  #   do_par("(?<bar_99>ab)", {:group, {1, "bar_99"}, [?a, ?b]})

  #   bad_par(")")
  #   bad_par("(")
  #   bad_par("()")
  #   bad_par("((a)")
  #   bad_par("(a))")
  # end

  # test "par repeat test" do
  #   do_par("a{3}", {:repeat, 3, ?a})
  #   do_par("(ab){43}", {:repeat, 43, {:group, 1, [?a, ?b]}})

  #   bad_par("{2}")
  # end

  # test "par alt test" do
  #   do_par("a|b", {:alternate, [?a, ?b]})
  #   do_par("ab|cd", {:alternate, [{:sequence, [?a, ?b]}, {:sequence, [?c, ?d]}]})
  #   do_par("(b|c)", {:group, 1, [{:alternate, [?b, ?c]}]})
  #   do_par("a|b|c|d", {:alternate, [?a, ?b, ?c, ?d]})

  #   bad_par("|")
  #   bad_par("a|")
  #   bad_par("|b")
  #   bad_par("(|)")
  #   bad_par("a||b")
  # end

  defp do_gen(re) do
    newline()
    dump(re, label: "RE   ")

    opts = []
    gen = Myrex.generate(re, opts)

    dump(gen, label: "GEN  ")
  end
end
