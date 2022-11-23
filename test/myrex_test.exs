defmodule Myrex.MyrexTest do
  use ExUnit.Case, async: false

  alias Myrex.Types, as: T

  @type expect() :: :no_match | :match | :matches | T.result()

  @default_opts [capture: :all, return: :binary, graph_name: :re]

  # NOTE - the first argument to 'exec' is the Myrex function name
  # the later argument is the expected result
  # but these may be the same in the case of ':match'

  # :oneshot,
  for mode <- [:oneshot, :batch] do
    test "char test #{mode}" do
      re = "ab"
      re_nfa = build(re, unquote(mode))

      exec(:match, re_nfa, "ab", :match)

      exec(:match, re_nfa, "", :no_match)
      exec(:match, re_nfa, "bb", :no_match)
      exec(:match, re_nfa, "abab", :no_match)

      Myrex.teardown(re_nfa)
    end

    test "escape test #{mode}" do
      re = "\\?\\*\\[\\]\\(\\)"
      re_nfa = build(re, unquote(mode))

      exec(:match, re_nfa, "?*[]()", :match)

      exec(:match, re_nfa, "", :no_match)
      exec(:match, re_nfa, "abc", :no_match)

      Myrex.teardown(re_nfa)
    end

    test "escesc test #{mode}" do
      re = "\\\\"
      re_nfa = build(re, unquote(mode))

      exec(:match, re_nfa, "\\", :match)

      exec(:match, re_nfa, "", :no_match)
      exec(:match, re_nfa, "abc", :no_match)

      Myrex.teardown(re_nfa)
    end

    test "char range test #{mode}" do
      re = "[a-dZ]"
      re_nfa = build(re, unquote(mode))

      exec(:match, re_nfa, "a", :match)
      exec(:match, re_nfa, "c", :match)
      exec(:match, re_nfa, "d", :match)
      exec(:match, re_nfa, "Z", :match)

      exec(:match, re_nfa, "", :no_match)
      exec(:match, re_nfa, "^", :no_match)
      exec(:match, re_nfa, "e", :no_match)
      exec(:match, re_nfa, "p", :no_match)
      exec(:match, re_nfa, "abcd", :no_match)

      Myrex.teardown(re_nfa)
    end

    test "neg char range test #{mode}" do
      re = "[^0-9p]"
      re_nfa = build(re, unquote(mode))

      exec(:match, re_nfa, "a", :match)
      exec(:match, re_nfa, "c", :match)
      exec(:match, re_nfa, "d", :match)
      exec(:match, re_nfa, "z", :match)

      exec(:match, re_nfa, "0", :no_match)
      exec(:match, re_nfa, "2", :no_match)
      exec(:match, re_nfa, "9", :no_match)
      exec(:match, re_nfa, "p", :no_match)
      exec(:match, re_nfa, "01", :no_match)

      Myrex.teardown(re_nfa)
    end

    test "char any test #{mode}" do
      re = ".Z"
      re_nfa = build(re, unquote(mode))

      exec(:match, re_nfa, "aZ", :match)
      exec(:match, re_nfa, "ZZ", :match)
      exec(:match, re_nfa, "\tZ", :match)

      exec(:match, re_nfa, "", :no_match)
      exec(:match, re_nfa, "aa", :no_match)
      exec(:match, re_nfa, "qZZ", :no_match)
      exec(:match, re_nfa, "\nZ", :no_match)

      nfa_dotall = Myrex.compile(re, dotall: true)

      exec(:match, nfa_dotall, "aZ", :match)
      # execute(nfa_dotall, "\nZ", :match)

      Myrex.teardown(re_nfa)
    end

    test "char any quantifiers test #{mode}" do
      re = ".?Z"
      re_nfa = build(re, unquote(mode))
      exec(:match, re_nfa, "aZ", :match)
      exec(:match, re_nfa, "Z", :match)
      exec(:match, re_nfa, "aaZ", :no_match)
      Myrex.teardown(re_nfa)

      re = ".+Z"
      re_nfa = build(re, unquote(mode))
      exec(:match, re_nfa, "aZ", :match)
      exec(:match, re_nfa, "abcdefgZ", :match)
      exec(:match, re_nfa, "Z", :no_match)
      Myrex.teardown(re_nfa)

      re = ".*Z"
      re_nfa = build(re, unquote(mode))
      exec(:match, re_nfa, "Z", :match)
      exec(:match, re_nfa, "aZ", :match)
      exec(:match, re_nfa, "abcdefgZ", :match)
      exec(:match, re_nfa, "a", :no_match)
      Myrex.teardown(re_nfa)

      re = ".*Z.*"
      re_nfa = build(re, unquote(mode))
      exec(:match, re_nfa, "Z", :match)
      exec(:match, re_nfa, "aZ", :match)
      exec(:match, re_nfa, "Za", :match)
      exec(:match, re_nfa, "abcdefgZhjijklm", :match)
      exec(:match, re_nfa, "a", :no_match)
      exec(:match, re_nfa, "abc", :no_match)
      Myrex.teardown(re_nfa)
    end

    test "zero one test #{mode}" do
      re = "t?"
      re_nfa = build(re, unquote(mode))

      exec(:match, re_nfa, "", :match)
      exec(:match, re_nfa, "t", :match)

      exec(:match, re_nfa, "s", :no_match)
      exec(:match, re_nfa, "tt", :no_match)

      Myrex.teardown(re_nfa)
    end

    test "one more test #{mode}" do
      re = "j+"
      re_nfa = build(re, unquote(mode))

      exec(:match, re_nfa, "j", :match)
      exec(:match, re_nfa, "jj", :match)

      exec(:match, re_nfa, "", :no_match)
      exec(:match, re_nfa, "k", :no_match)
      exec(:match, re_nfa, "jk", :no_match)

      Myrex.teardown(re_nfa)
    end

    test "zero more test #{mode}" do
      re = "m*"
      re_nfa = build(re, unquote(mode))

      exec(:match, re_nfa, "", :match)
      exec(:match, re_nfa, "m", :match)
      exec(:match, re_nfa, "mm", :match)

      exec(:match, re_nfa, "k", :no_match)
      exec(:match, re_nfa, "jk", :no_match)
      exec(:match, re_nfa, "mk", :no_match)

      Myrex.teardown(re_nfa)
    end

    test "group test #{mode}" do
      re = "(ab)"
      re_nfa = build(re, unquote(mode))

      exec(:match, re_nfa, "ab", {:match, %{1 => "ab"}})

      exec(:match, re_nfa, "", :no_match)
      exec(:match, re_nfa, "bb", :no_match)
      exec(:match, re_nfa, "abab", :no_match)

      Myrex.teardown(re_nfa)
    end

    test "group_nocap test #{mode}" do
      re = "(?:ab)(cd)"
      re_nfa = build(re, unquote(mode))

      exec(:match, re_nfa, "abcd", {:match, %{1 => "cd"}})

      exec(:match, re_nfa, "abxy", :no_match)

      Myrex.teardown(re_nfa)
    end

    test "group named capture test #{mode}" do
      re = "(ab)(cd)"
      re_nfa = build(re, unquote(mode))

      opts = [return: :binary, graph_name: :re]
      exec(:match, re_nfa, "abcd", {:match, %{1 => "ab"}}, [{:capture, [1]} | opts])
      exec(:match, re_nfa, "abcd", {:match, %{2 => "cd"}}, [{:capture, [2]} | opts])

      opts = [return: :index, graph_name: :re]
      exec(:match, re_nfa, "abcd", {:match, %{1 => {0, 2}}}, [{:capture, [1]} | opts])
      exec(:match, re_nfa, "abcd", {:match, %{2 => {2, 2}}}, [{:capture, [2]} | opts])

      Myrex.teardown(re_nfa)
    end

    test "alt test #{mode}" do
      re = "a|b|c|d"
      re_nfa = build(re, unquote(mode))

      exec(:match, re_nfa, "a", :match)
      exec(:match, re_nfa, "c", :match)

      exec(:match, re_nfa, "", :no_match)
      exec(:match, re_nfa, "z", :no_match)
      exec(:match, re_nfa, "abcd", :no_match)
      exec(:match, re_nfa, "cdab", :no_match)

      Myrex.teardown(re_nfa)
    end

    test "search test #{mode}" do
      def_opts = [capture: :all, return: :index, graph_name: :re]

      re = "Z"
      IO.inspect(unquote(mode), label: "MODE")
      re_nfa = build(re, unquote(mode))

      opts = def_opts ++ [multiple: :first]
      exec(:search, re_nfa, "Z", {:search, {0, 1}}, opts)
      exec(:search, re_nfa, "Zn", {:search, {0, 1}}, opts)
      exec(:search, re_nfa, "aZn", {:search, {1, 1}}, opts)
      exec(:search, re_nfa, "ZZ", [{:search, {0, 1}}, {:search, {1, 1}}], opts)
      exec(:search, re_nfa, "aZnZs", [{:search, {1, 1}}, {:search, {3, 1}}], opts)

      opts = def_opts ++ [multiple: :all]
      exec(:search, re_nfa, "Z", {:searches, [{0, 1}]}, opts)
      exec(:search, re_nfa, "Zn", {:searches, [{0, 1}]}, opts)
      exec(:search, re_nfa, "aZn", {:searches, [{1, 1}]}, opts)
      exec(:search, re_nfa, "ZZ", {:searches, [{0, 1}, {1, 1}]}, opts)
      exec(:search, re_nfa, "aZaZn", {:searches, [{1, 1}, {3, 1}]}, opts)
      exec(:search, re_nfa, "aaZZ", {:searches, [{2, 1}, {3, 1}]}, opts)
      exec(:search, re_nfa, "aaZnZstZuZ", {:searches, [{2, 1}, {4, 1}, {7, 1}, {9, 1}]}, opts)

      Myrex.teardown(re_nfa)
    end

    test "overlapping search test #{mode}" do
      def_opts = [capture: :all, return: :index, graph_name: :re]

      re = "ana"
      IO.inspect(unquote(mode), label: "MODE")
      re_nfa = build(re, unquote(mode))

      opts = def_opts ++ [multiple: :first]
      exec(:search, re_nfa, "z", :no_match, opts)
      exec(:search, re_nfa, "ana", {:search, {0, 3}}, opts)
      exec(:search, re_nfa, "banana", [{:search, {1, 3}}, {:search, {3, 3}}], opts)

      opts = def_opts ++ [multiple: :all]
      exec(:search, re_nfa, "z", :no_match, opts)
      exec(:search, re_nfa, "ana", {:searches, [{0, 3}]}, opts)
      exec(:search, re_nfa, "banana", {:searches, [{1, 3}, {3, 3}]}, opts)

      Myrex.teardown(re_nfa)
    end

    test "multiple matches #{mode}" do
      opts = @default_opts
      re = "(a?)(a*)"
      re_nfa = build(re, unquote(mode))

      expect = {:matches, [%{1 => "", 2 => "a"}, %{1 => "a", 2 => ""}]}
      exec(:match, re_nfa, "a", expect, opts ++ [multiple: :first])
      exec(:match, re_nfa, "a", expect, opts ++ [multiple: :all])

      expect = {:matches, [%{1 => "", 2 => "aa"}, %{1 => "a", 2 => "a"}]}
      exec(:match, re_nfa, "aa", expect, opts ++ [multiple: :first])
      exec(:match, re_nfa, "aa", expect, opts ++ [multiple: :all])

      Myrex.teardown(re_nfa)
    end

    test "exponential matches #{mode}" do
      # match a^n against (a?)^n (a*)^n
      # Enum.each(1..10, fn n -> IO.inspect(mdot(n), label: "mdot #{n}") end)
      n = 4
      opts = @default_opts
      {re, str} = dup(n)
      re_nfa = build(re, unquote(mode))

      # TODO - iterate over n and get performance of first/all
      do_apply(:match, re_nfa, str, opts ++ [multiple: :first])

      if n < 10 do
        {:matches, all} = do_apply(:match, re_nfa, str, opts ++ [multiple: :all, timeout: 10_000])
        IO.inspect(length(all), label: "LENGTH")
        assert length(all) == mdot(n)
      end

      Myrex.teardown(re_nfa)
    end
  end

  # total count of matches for (a?)^n (a*)^n against a^n
  # using the dot product of two vectors from Pascal's Triangle
  @spec mdot(pos_integer()) :: pos_integer()
  defp mdot(n) when n > 0 do
    Enum.reduce(0..n, 0, fn m, sum ->
      sum + binom(n, m) * binom(n + m - 1, m)
    end)
  end

  # binomial coefficient using Pascal's Triangle recurrence formula
  @spec binom(non_neg_integer(), non_neg_integer()) :: pos_integer()
  defp binom(_n, 0), do: 1
  defp binom(n, n), do: 1
  defp binom(n, k), do: binom(n - 1, k) + binom(n - 1, k - 1)

  # duplicate 'a' to make '(a?)^n (a*)^n' regex and 'a^n' input string 
  @spec dup(pos_integer()) :: {T.regex(), String.t()}
  defp dup(n), do: {"(#{dup('a?', n)})(#{dup('a*', n)})", dup(?a, n)}

  # duplicate charlist 'a' to make a '(a?)^n (a*)^n' regex and 'a^n' input string 
  @spec dup(charlist(), pos_integer()) :: String.t()
  defp dup(chars, n), do: chars |> List.duplicate(n) |> List.flatten() |> to_string()

  # optionally compile the regular expression to an NFA process network
  @spec build(T.regex(), :batch | :oneshot, T.options()) :: T.regex() | pid()
  defp build(re, mode, opts \\ @default_opts) do
    IO.inspect(re, label: "RE    ")

    case mode do
      :batch -> Myrex.compile(re, opts)
      :oneshot -> re
    end
  end

  # execute a test on an RE or compiled NFA
  @spec exec(atom(), T.regex() | pid(), String.t(), expect(), T.options()) :: any()
  defp exec(f, re_nfa, str, expect, opts \\ @default_opts)

  defp exec(:match, re_nfa, str, {:matches, _} = expect, opts) do
    {:matches, expect_caps} = success = add_def_cap(str, expect)

    case do_apply(:match, re_nfa, str, opts) do
      {:matches, actual_caps} -> assert Enum.sort(expect_caps) == Enum.sort(actual_caps)
      # these will fail, but we want the detailed error message for the comparison
      {:match, actual} -> assert actual in expect_caps
      nomatch -> assert nomatch == success
    end
  end

  defp exec(:search, re_nfa, str, {:searches, _} = expects, opts) do
    {:searches, expect_srchs} = success = add_def_cap(str, expects)

    case do_apply(:search, re_nfa, str, opts) do
      {:searches, actual_srchs} -> assert Enum.sort(expect_srchs) == Enum.sort(actual_srchs)
      # these will fail, but we want the detailed error message for the comparison
      fail -> assert fail == success
    end
  end

  defp exec(f, re_nfa, str, expects, opts) when is_list(expects) do
    results = Enum.map(expects, &add_def_cap(str, &1))
    assert do_apply(f, re_nfa, str, opts) in results
  end

  defp exec(f, re_nfa, str, expect, opts) do
    assert add_def_cap(str, expect) == do_apply(f, re_nfa, str, opts)
  end

  @spec do_apply(atom(), T.regex() | pid(), String.t(), T.options()) :: any()
  defp do_apply(f, re_nfa, str, opts) do
    IO.inspect(str, label: "STR   ")
    {time, value} = :timer.tc(fn -> apply(Myrex, f, [re_nfa, str, opts]) end)
    IO.inspect(value, label: "RESULT")
    IO.inspect(time, label: "TIME (us)")
    value
  end

  # add the default whole string capture to expected results
  @spec add_def_cap(String.t(), expect()) :: T.result()
  defp add_def_cap(str, :no_match), do: {:no_match, add0(str)}
  defp add_def_cap(str, :match), do: {:match, add0(str)}
  defp add_def_cap(str, :matches), do: {:matches, [add0(str)]}
  defp add_def_cap(str, {:match, caps}), do: {:match, add0(caps, str)}
  defp add_def_cap(str, {:matches, capss}), do: {:matches, Enum.map(capss, &add0(&1, str))}
  defp add_def_cap(str, {:search, index}) when is_tuple(index), do: {:search, index, add0(str)}
  defp add_def_cap(str, {:search, {index, caps}}), do: {:search, index, add0(caps, str)}

  defp add_def_cap(str, {:searches, ixs}) when is_list(ixs) do
    {:searches, Enum.map(ixs, fn ix -> {ix, add0(str)} end)}
  end

  defp add0(caps \\ %{}, str), do: Map.put(caps, 0, str)
end
