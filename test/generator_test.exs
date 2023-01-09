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
    do_gen("[.]")
    do_gen("a.b")
    do_gen(".?")
    do_gen(".+")
    do_gen(".*")
    do_gen(".{5}")
    set_dump(false)
  end

  test "gen neg any test" do
    set_dump(true)
    do_gen("\\P{Any}", [""])
    do_gen("[\\P{Any}]", [""])
    do_gen("[^.]", [""])
    do_gen("[^\\p{Any}]", [""])
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

  test "gen char class test" do
    set_dump(true)
    # do_gen("[A-Z]")
    # do_gen("[#0-9~]")

    # do_gen("[\\p{Mathematical Operators}]")
    # do_gen("[\\P{Mathematical Operators}]")

    # do_gen("[\\p{Lu}]")
    # do_gen("[\\P{Cyrillic}]")

    # do_gen("[^_A-Z!]")
    do_gen("[^#0-9~]")
    set_dump(false)
  end

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
    if gen != "" do
      match = Myrex.match(re, gen)
      assert {:match, _} = match
    end
  end
end
