defmodule Myrex do
  @moduledoc """
  A regular expression matcher...
  """

  alias Myrex.Types, as: T

  alias Myrex.AST
  alias Myrex.Compiler
  alias Myrex.Lexer
  alias Myrex.Parser
  alias Myrex.NFA.Executor
  alias Myrex.NFA.Proc

  @default_timeout 1_000

  @doc "Convert a regular expression to an NFA process network."
  @spec compile(String.t(), Keyword.t()) :: pid()
  def compile(re, opts \\ []) do
    IO.inspect(re, label: "RE  ")
    {toks, gmax} = Lexer.lex(re)
    ast = Parser.parse(toks)
    aststr = AST.ast2str(ast)
    IO.puts(aststr)
    Compiler.build(ast, opts, gmax)
  end

  @doc """
  Execute a compiled regular expression against a string argument.
  """
  @spec run(String.t() | pid(), String.t(), Keyword.t()) :: T.result()

  def run(re, str, opts \\ [])

  def run(re, str, opts) when is_binary(re) and is_binary(str) and is_list(opts) do
    re |> compile(opts) |> run(str, opts)
  end

  def run(start, str, opts) when is_pid(start) and is_binary(str) and is_list(opts) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    exec = Executor.init(timeout)
    Proc.connect(exec, self())
    Proc.traverse(start, {str, 0, [], %{}, exec})

    receive do
      :no_match ->
        :no_match

      {:match, caps} ->
        capopt = Keyword.get(opts, :capture, :all)
        return = Keyword.get(opts, :return, :index)

        case {capopt, return} do
          {:none, _} -> {:match, %{}}
          {:all, :index} -> {:match, caps}
          {:all, :binary} -> {:match, groups(Map.keys(caps), str, caps)}
          {names, :index} when is_list(names) -> {:match, Map.take(caps, names)}
          {names, :binary} when is_list(names) -> {:match, groups(names, str, caps)}
        end
    end
  end

  # get group substrings from capture indexes
  @spec groups([T.capture_name()], String.t(), T.captures()) :: T.captures()

  defp groups([name | names], str, caps) do
    # error if requested name is not in the captured map
    substr =
      case Map.fetch!(caps, name) do
        :no_capture -> :no_capture
        {pos, len} -> String.slice(str, pos, len)
      end

    groups(names, str, %{caps | name => substr})
  end

  defp groups([], _, caps), do: caps
end
