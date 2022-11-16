defmodule Myrex.MyrexTest do
  use ExUnit.Case, async: false

  @default_opts [capture: :all, return: :binary, graph_name: :re]

  for mode <- [:batch] do
    test "char test #{mode}" do
      re = "ab"
      re_nfa = build(re, unquote(mode))

      execute(re_nfa, "ab", :match)

      execute(re_nfa, "", :no_match)
      execute(re_nfa, "bb", :no_match)
      execute(re_nfa, "abab", :no_match)

      Myrex.teardown(re_nfa)
    end

    test "escape test #{mode}" do
      re = "\\?\\*\\[\\]\\(\\)"
      re_nfa = build(re, unquote(mode))

      execute(re_nfa, "?*[]()", :match)

      execute(re_nfa, "", :no_match)
      execute(re_nfa, "abc", :no_match)

      Myrex.teardown(re_nfa)
    end

    test "escesc test #{mode}" do
      re = "\\\\"
      re_nfa = build(re, unquote(mode))

      execute(re_nfa, "\\", :match)

      execute(re_nfa, "", :no_match)
      execute(re_nfa, "abc", :no_match)

      Myrex.teardown(re_nfa)
    end

    test "char range test #{mode}" do
      re = "[a-dz]"
      re_nfa = build(re, unquote(mode))

      execute(re_nfa, "a", :match)
      execute(re_nfa, "c", :match)
      execute(re_nfa, "d", :match)
      execute(re_nfa, "z", :match)

      execute(re_nfa, "", :no_match)
      execute(re_nfa, "^", :no_match)
      execute(re_nfa, "e", :no_match)
      execute(re_nfa, "p", :no_match)
      execute(re_nfa, "abcd", :no_match)

      Myrex.teardown(re_nfa)
    end

    test "neg char range test #{mode}" do
      re = "[^0-9p]"
      re_nfa = build(re, unquote(mode))

      execute(re_nfa, "a", :match)
      execute(re_nfa, "c", :match)
      execute(re_nfa, "d", :match)
      execute(re_nfa, "z", :match)

      execute(re_nfa, "0", :no_match)
      execute(re_nfa, "2", :no_match)
      execute(re_nfa, "9", :no_match)
      execute(re_nfa, "p", :no_match)
      execute(re_nfa, "01", :no_match)

      Myrex.teardown(re_nfa)
    end

    test "char any test #{mode}" do
      re = ".z"
      re_nfa = build(re, unquote(mode))

      execute(re_nfa, "az", :match)
      execute(re_nfa, "zz", :match)
      execute(re_nfa, "\tz", :match)

      execute(re_nfa, "", :no_match)
      execute(re_nfa, "aa", :no_match)
      execute(re_nfa, "qzz", :no_match)
      execute(re_nfa, "\nz", :no_match)

      nfa_dotall = Myrex.compile(re, dotall: true)

      execute(nfa_dotall, "az", :match)
      # execute(nfa_dotall, "\nz", :match)

      Myrex.teardown(re_nfa)
    end

    test "zero one test #{mode}" do
      re = "t?"
      re_nfa = build(re, unquote(mode))

      execute(re_nfa, "", :match)
      execute(re_nfa, "t", :match)

      execute(re_nfa, "s", :no_match)
      execute(re_nfa, "tt", :no_match)

      Myrex.teardown(re_nfa)
    end

    test "one more test #{mode}" do
      re = "j+"
      re_nfa = build(re, unquote(mode))

      execute(re_nfa, "j", :match)
      execute(re_nfa, "jj", :match)

      execute(re_nfa, "", :no_match)
      execute(re_nfa, "k", :no_match)
      execute(re_nfa, "jk", :no_match)

      Myrex.teardown(re_nfa)
    end

    test "zero more test #{mode}" do
      re = "m*"
      re_nfa = build(re, unquote(mode))

      execute(re_nfa, "", :match)
      execute(re_nfa, "m", :match)
      execute(re_nfa, "mm", :match)

      execute(re_nfa, "k", :no_match)
      execute(re_nfa, "jk", :no_match)
      execute(re_nfa, "mk", :no_match)

      Myrex.teardown(re_nfa)
    end

    test "group test #{mode}" do
      re = "(ab)"
      re_nfa = build(re, unquote(mode))

      execute(re_nfa, "ab", {:match, %{1 => "ab"}})

      execute(re_nfa, "", :no_match)
      execute(re_nfa, "bb", :no_match)
      execute(re_nfa, "abab", :no_match)

      Myrex.teardown(re_nfa)
    end

    test "group_nocap test #{mode}" do
      re = "(?:ab)(cd)"
      re_nfa = build(re, unquote(mode))

      execute(re_nfa, "abcd", {:match, %{1 => "cd"}})

      execute(re_nfa, "abxy", :no_match)

      Myrex.teardown(re_nfa)
    end

    test "group named capture test #{mode}" do
      re = "(ab)(cd)"
      re_nfa = build(re, unquote(mode))

      opts = [return: :binary, graph_name: :re]
      execute(re_nfa, "abcd", {:match, %{1 => "ab"}}, [{:capture, [1]} | opts])
      execute(re_nfa, "abcd", {:match, %{2 => "cd"}}, [{:capture, [2]} | opts])

      opts = [return: :index, graph_name: :re]
      execute(re_nfa, "abcd", {:match, %{1 => {0, 2}}}, [{:capture, [1]} | opts])
      execute(re_nfa, "abcd", {:match, %{2 => {2, 2}}}, [{:capture, [2]} | opts])

      Myrex.teardown(re_nfa)
    end

    test "alt_group test #{mode}" do
      re = "(ab)|(cd)"
      re_nfa = build(re, unquote(mode))

      execute(re_nfa, "ab", {:match, %{1 => "ab", 2 => :no_capture}})
      execute(re_nfa, "cd", {:match, %{1 => :no_capture, 2 => "cd"}})

      execute(re_nfa, "", :no_match)
      execute(re_nfa, "z", :no_match)
      execute(re_nfa, "abcd", :no_match)
      execute(re_nfa, "cdab", :no_match)

      Myrex.teardown(re_nfa)
    end

    test "multiple matches #{mode}" do
      opts = @default_opts
      re = "(a?)(a*)"
      re_nfa = build(re, unquote(mode))

      expect = {:matches, [%{1 => "", 2 => "a"}, %{1 => "a", 2 => ""}]}
      execute(re_nfa, "a", expect, opts ++ [multiple: :first])
      execute(re_nfa, "a", expect, opts ++ [multiple: :all])

      # TODO - should be multiple results here
      expect = {:matches, [%{1 => "", 2 => "aa"}, %{1 => "a", 2 => "a"}]}
      execute(re_nfa, "aa", expect, opts ++ [multiple: :first])
      execute(re_nfa, "aa", expect, opts ++ [multiple: :all])

      Myrex.teardown(re_nfa)
    end

    test "exponential matches #{mode}" do
      # match a^n against (a?)^n (a*)^n
      n = 4
      opts = @default_opts
      {re, str} = dup(n)
      re_nfa = build(re, unquote(mode))

      # TODO - iterate over n and get performance of first/all
      run(re_nfa, str, opts ++ [multiple: :first])

      if n < 10 do
        {:matches, all} = run(re_nfa, str, opts ++ [multiple: :all, timeout: 10_000])
        IO.inspect(length(all), label: "LENGTH")
      end

      Myrex.teardown(re_nfa)
    end
  end

  defp dup(n), do: {"(#{dup('a?', n)})(#{dup('a*', n)})", dup(?a, n)}

  defp dup(chars, n), do: chars |> List.duplicate(n) |> List.flatten() |> to_string()

  # optionally compile the regular expression to an NFA process network
  defp build(re, mode, opts \\ @default_opts) do
    IO.inspect(re, label: "RE    ")

    case mode do
      :batch -> Myrex.compile(re, opts)
      :oneshot -> re
    end
  end

  # execute a test on an RE or compiled NFA
  defp execute(re_nfa, str, result, opts \\ @default_opts)

  defp execute(re_nfa, str, :no_match, opts),
    do: exec(re_nfa, str, {:no_match, add0(str)}, opts)

  defp execute(re_nfa, str, :match, opts),
    do: exec(re_nfa, str, {:match, add0(str)}, opts)

  defp execute(re_nfa, str, {:match, caps}, opts),
    do: exec(re_nfa, str, {:match, add0(caps, str)}, opts)

  defp execute(re_nfa, str, {:matches, capss}, opts) do
    capss0 = Enum.map(capss, &add0(&1, str))
    exec(re_nfa, str, {:matches, capss0}, opts)
  end

  defp exec(nfa, str, {:matches, expects} = success, opts) do
    case run(nfa, str, opts) do
      {:match, actual} -> assert actual in expects
      {:matches, actuals} -> assert Enum.sort(expects) == Enum.sort(actuals)
      nomatch -> assert nomatch == success
    end
  end

  defp exec(nfa, str, expect, opts) do
    assert expect == run(nfa, str, opts)
  end

  defp run(nfa, str, opts) do
    IO.inspect(str, label: "STR   ")

    {time, value} = :timer.tc(fn -> Myrex.run(nfa, str, opts) end)
    IO.inspect(value, label: "RESULT")
    IO.inspect(time, label: "TIME (us)")
    value
  end

  defp add0(caps \\ %{}, str), do: Map.put(caps, 0, str)
end
