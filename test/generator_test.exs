defmodule Myrex.GeneratorTest do
  use ExUnit.Case

  import Myrex.TestUtil

  test "gen char test" do
    set_dump(true)
    do_gen("a", ["a"])
    do_gen("aabb", ["aabb"])
    set_dump(false)
  end

  test "gen char range test" do
    set_dump(true)
    do_gen("[a-h]", ["a", "b", "c", "d", "e", "f", "g", "h"])
    do_gen("[0-9]", ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9"])
    do_gen("[abc0-9]", ["a", "b", "c", "0", "1", "2", "3", "4", "5", "6", "7", "8", "9"])
    set_dump(false)
  end

  test "gen any test" do
    set_dump(true)
    do_gen(".")
    do_gen("a.b")
    do_gen(".?")
    do_gen(".+")
    do_gen(".*")
    do_gen(".{5}")
    do_gen("[.]")
    # TODO - negated char classes
    # assert_raise ArgumentError, fn -> do_gen("[^.]") end
    # TODO - special case for property Any == . 
    # assert_raise ArgumentError, fn -> do_gen("\\P{Any}") end
    set_dump(false)
  end

  test "gen unicode property test" do
    set_dump(true)
    do_gen("\\p{Mathematical Operators}")
    do_gen("\\p{Mathematical Operators}{5}")

    do_gen("\\p{Lu}")
    do_gen("\\p{Lu}{5}")

    do_gen("\\p{Signwriting}")
    do_gen("\\p{Signwriting}{5}")
    set_dump(false)
  end

  test "gen quantifier test" do
    set_dump(true)
    do_gen("a?")
    do_gen("a+")
    do_gen("a*")

    do_gen("ba?c")
    do_gen("ba+c")
    do_gen("ba*c")

    do_gen("ba{2}c", ["baac"])
    do_gen("ba{3}c", ["baaac"])
    do_gen("ba{5}c", ["baaaaac"])
    set_dump(false)
  end

  # test "par class test" do
  #   do_gen("[A-Z]", {:char_class, :pos, [{:char_range, ?A, ?Z}]})
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

  test "gen extension classes" do
    set_dump(true)
    do_gen("\\p{Xwd}")
    do_gen("\\P{Xsp}")
    do_gen("[\\p{Xan}]")
    do_gen("[\\P{Xwd}]")
    set_dump(false)
  end

  test "gen group test" do
    # groups do not affect generation
    do_gen("(a)", ["a"])
    do_gen("(abc)", ["abc"])
    do_gen("(ab*c)")

    do_gen("(a)(bc)", ["abc"])

    do_gen("((a))", ["a"])

    do_gen("(?:(ab))", ["ab"])

    do_gen("(?<foo>ab)", ["ab"])
    do_gen("(?<bar_99>ab)", ["ab"])
  end

  test "gen repeat test" do
    do_gen("a{3}", ["aaa"])
    do_gen("(ab){7}", ["ababababababab"])
  end

  test "gen alt test" do
    do_gen("a|b", ["a", "b"])
    do_gen("ab|cd", ["ab", "cd"])
    do_gen("(b|c)", ["b", "c"])
    do_gen("a|b|c|d", ["a", "b", "c", "d"])
  end

  defp do_gen(re, outputs \\ nil) do
    newline()
    dump(re, label: "RE    ")

    opts = []
    gen = Myrex.generate(re, opts)
    dump(gen, label: "GEN   ")

    # test for finite set of expected outputs
    if outputs, do: assert(gen in outputs)

    # every generated string should be correctly matched by the same NFA
    match = Myrex.match(re, gen)
    dump(match, label: "MATCH ")
    assert {:match, _} = match
  end
end
