defmodule Myrex.MyrexTest do
  use ExUnit.Case

  test "comp_char_test" do
    re = "ab"
    start = Myrex.compile(re)

    do_exec(start, "ab", :match)

    do_exec(start, "", :no_match)
    do_exec(start, "bb", :no_match)
    do_exec(start, "abab", :no_match)
  end

  test "comp_escape_test" do
    re = "\\?\\*\\[\\]\\(\\)"
    start = Myrex.compile(re)

    do_exec(start, "?*[]()", :match)

    do_exec(start, "", :no_match)
    do_exec(start, "abc", :no_match)
  end

  test "comp_escesc_test" do
    re = "\\\\"
    start = Myrex.compile(re)

    do_exec(start, "\\", :match)

    do_exec(start, "", :no_match)
    do_exec(start, "abc", :no_match)
  end

  test "comp_char_range_test" do
    re = "[a-d]"
    start = Myrex.compile(re)

    do_exec(start, "a", :match)
    do_exec(start, "c", :match)
    do_exec(start, "d", :match)

    do_exec(start, "", :no_match)
    do_exec(start, "^", :no_match)
    do_exec(start, "e", :no_match)
    do_exec(start, "p", :no_match)
    do_exec(start, "abcd", :no_match)
  end

  test "comp_char_any_test" do
    re = ".z"
    start = Myrex.compile(re)

    do_exec(start, "az", :match)
    do_exec(start, "zz", :match)
    do_exec(start, "\tz", :match)

    do_exec(start, "", :no_match)
    do_exec(start, "aa", :no_match)
    do_exec(start, "qzz", :no_match)
    do_exec(start, "\nz", :no_match)

    start_dotall = Myrex.compile(re, dotall: true)

    do_exec(start_dotall, "az", :match)
    do_exec(start_dotall, "\nz", :match)
  end

  test "comp_zero_one_test" do
    re = "t?"
    start = Myrex.compile(re)

    do_exec(start, "", :match)
    do_exec(start, "t", :match)

    do_exec(start, "s", :no_match)
    do_exec(start, "tt", :no_match)
  end

  test "comp_one_more_test" do
    re = "j+"
    start = Myrex.compile(re)

    do_exec(start, "j", :match)
    do_exec(start, "jj", :match)

    do_exec(start, "", :no_match)
    do_exec(start, "k", :no_match)
    do_exec(start, "jk", :no_match)
  end

  test "comp_zero_more_test" do
    re = "m*"
    start = Myrex.compile(re)

    do_exec(start, "", :match)
    do_exec(start, "m", :match)
    do_exec(start, "mm", :match)

    do_exec(start, "k", :no_match)
    do_exec(start, "jk", :no_match)
    do_exec(start, "mk", :no_match)
  end

  test "comp_group_test" do
    re = "(ab)"
    start = Myrex.compile(re)

    do_exec(start, "ab", {:match, %{1 => "ab"}})

    do_exec(start, "", :no_match)
    do_exec(start, "bb", :no_match)
    do_exec(start, "abab", :no_match)
  end

  test "comp_group_nocap_test" do
    re = "(?:ab)(cd)"
    start = Myrex.compile(re)

    do_exec(start, "abcd", {:match, %{1 => "cd"}})

    do_exec(start, "(?ab)", :no_match)
  end

  test "comp_alt_group_test" do
    re = "(ab)|(cd)"
    start = Myrex.compile(re)

    do_exec(start, "ab", {:match, %{1 => "ab", 2 => :no_capture}})
    do_exec(start, "cd", {:match, %{1 => :no_capture, 2 => "cd"}})

    do_exec(start, "", :no_match)
    do_exec(start, "z", :no_match)
    do_exec(start, "abcd", :no_match)
    do_exec(start, "cdab", :no_match)
  end

  defp do_exec(start, str, :no_match), do: exec(start, str, :no_match)
  defp do_exec(start, str, :match), do: do_exec(start, str, {:match, %{0 => str}})
  defp do_exec(start, str, {:match, caps}), do: exec(start, str, {:match, Map.put(caps, 0, str)})

  defp exec(start, str, expect, opts \\ [capture: :all, return: :binary]) do
    IO.inspect(str, label: "STR   ")
    result = Myrex.run(start, str, opts)
    IO.inspect(result, label: "RESULT")
    assert expect == result
  end
end
