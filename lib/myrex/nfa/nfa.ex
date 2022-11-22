defmodule Myrex.NFA do
  @moduledoc """
  An NFA process network for matching a regular expression.
  The NFA is built using a variation of Thompson's Construction
  \[[wikipedia](https://en.wikipedia.org/wiki/Thompson%27s_construction)\]
  \[[Cox](https://swtch.com/~rsc/regexp/regexp1.html)\]

  Actual networks for elements of a regular expression 
  are described as follows:

  Linear
  { :sequence,   [P] }   -->  { P1, Pn }
  { :group,    p|[P] }   -->  { BeginGroup, EndGroup }    
  { :repeat,   N, P  }   -->  { P1, Pn }

  Parallel fan-out
  { :alternate,  [P] }   -->  { Split, [P] }
  { :zero_one,    p  }   -->  { Split, [P,Split] }

  Loops
  { :one_more,  P }      -->  { P,  Split }
  { :zero_more, P }      -->  { Split, Split }

  Character classes: alternate or sequence
  { :char_class, [CCs]      -->  { Split, [CCs] }
  { :char_class_neg, [CCs]  -->  { hd(CCs), EndAnd }

  Atomic
    c                        MatchChar(c)
    :char_any                MatchAnyChar
  """

  import Myrex.Types
  alias Myrex.Types, as: T

  alias Myrex.NFA.BeginGroup
  alias Myrex.NFA.EndAnd
  alias Myrex.NFA.EndGroup
  alias Myrex.NFA.Match
  alias Myrex.NFA.Proc
  alias Myrex.NFA.Split

  # ----------------------------
  # quantifier combinators
  # ----------------------------

  @doc """
  Combinator for zero or one repetition.

  Split node _S_ can bypass the process node _P_ (zero).

  ```
          +---+
          | P |---> outputs
          +---+
            ^ 
            | 
          +---+
   in --->| S |---> out
          +---+
  ```
  """
  @spec zero_one(T.proc()) :: T.proc()
  def zero_one(proc) do
    split = Split.init(proc, "?")
    {split, [split | Proc.outputs(proc)]}
  end

  @doc """
  Combinator for one or more repetitions.

  Split node _S_ can cycle back to the process node _P_ (more).
  The new network only has one output from the split node.

  ```
          +---+
   in --->| P |
          +---+
           ^ |
           | V
          +---+
          | S |---> output
          +---+
  ```
  """
  @spec one_more(T.proc()) :: T.proc()
  def one_more(proc) do
    split = Split.init(proc, "+")
    Proc.connect(proc, split)
    {Proc.input(proc), split}
  end

  @doc """
  Combinator for zero or more repetitions.

  Split node _S_ can cycle to the process node _P_ (more).
  The new network only has one output from the split node.

  ```
          +---+
          | P |
          +---+
           ^ |
           | V
          +---+
   in --->| S |---> output
          +---+
  ```
  """
  @spec zero_more(T.proc()) :: T.proc()
  def zero_more(proc) do
    split = Split.init(proc, "*")
    Proc.connect(proc, split)
    split
  end

  @doc """
  Search combinator for zero or more repetitions of any character.

  Split node _S_ can cycle to the process node _P_ (more).
  The new network only has one output from the split node.

    A standalone `BeginGroup` node is used to mark the 
  beginning of the search as if it was a special case of a capture.
  An `EndGroup` cannot be uased, because it would attach after 
  the `Success` node at the end of the nested process subgraph,
  so handling the end of the search must be handled in the `Executor`.

  ```
          +---+
          | . |
          +---+
           ^ |
           | V
          +---+    +-----+    +---+
   in --->| S |--->|Begin|--->| P |---> outputs
          +---+    |Group|    +---+
                   +-----+
  ```
  """
  @spec search(T.proc(), boolean()) :: T.proc()
  def search(proc, dotall?) do
    split = dotall? |> match_any_char() |> zero_more()
    begin = BeginGroup.init(:search)
    sequence([split, begin, proc])
  end

  # ----------------------------
  # sequential combinators
  # ----------------------------

  @doc """
  Combinator for capture group around a sequence.

  ```
          +-----+    +--+             +--+    +-----+
   in --->|Begin|--->|P1|---> ... --->|Pn|--->| End |---> out
          |Group|    +--+             +--+    |Group|
          +-----+                             +-----+
  ```
  """

  @spec group(T.procs(), :nocap | T.capture_name()) :: T.proc()

  def group(procs, :nocap) when is_list(procs) do
    # no-capture group is just an anonymous sequence
    sequence(procs)
  end

  def group(procs, name) when is_list(procs) and is_name(name) do
    begin = BeginGroup.init(name)
    endgrp = EndGroup.init()
    sequence([begin | procs] ++ [endgrp])
  end

  @doc """
  Combinator for an AND sequence of peek lookahead Match nodes.
  The peeking Match nodes are created by a negated character class.

  ```
          +--+             +--+    +-----+
   in --->|M1|---> ... --->|Mn|--->| End |---> out
          +--+             +--+    | AND |
                                   +-----+
  ```
  """

  @spec and_sequence(T.procs()) :: T.proc()

  def and_sequence(procs) when is_list(procs) do
    sequence(procs ++ [EndAnd.init()])
  end

  @doc """
  Combinator for sequence of process networks _P1..Pn_ :

  ```
          +----+             +----+
   in --->| P1 |---> ... --->| Pn | ---> outputs
          +----+             +----+
  ```
  """
  @spec sequence(T.procs()) :: T.proc()
  def sequence([first | rest]) do
    last = Enum.reduce(rest, first, fn next, prev -> Proc.connect(prev, next) end)
    {Proc.input(first), Proc.output(last)}
  end

  # ----------------------------
  # parallel combinators
  # ----------------------------

  @doc """
  Combinator for fan-out of alternate choices.

  For Split process _S_ and processes _P1..Pn_ :

  ```
                   +----+
                  _| P1 |---> outputs
                 / +----+
                /
          +---+/   +----+
   in --->| S |--->| P2 |---> outputs
          +---+\   +----+
                \    :   ---> outputs
                 \ +----+
                  -| Pn |---> outputs
                   +----+
  ```
  """
  @spec alternate(T.procs(), String.t()) :: T.proc()
  def alternate(procs, name) do
    split = Split.init(procs, name)
    {split, Proc.outputs(procs)}
  end

  # --------------------------------
  # characters and character classes
  # --------------------------------

  @doc "Match a specific character."
  @spec match_char(char(), boolean()) :: pid()
  def match_char(char, neg? \\ false) do
    accept? = inv(fn c -> c == char end, neg?)
    # negation turns Match into peek look ahead
    Match.init(accept?, neg?, caret([?', char, ?'], neg?))
  end

  @doc """
  Match any character.

  The treatment of the newline character depends on the value of the `dotall` argument:
  * `true` - any character will match, including newline.
  * `false` - any character will match, excluding newline. 
  """

  @spec match_any_char(boolean(), boolean()) :: pid()
  def match_any_char(dotall?, neg? \\ false) do
    # anychar wildcard '.' not allowed in negated character class?
    accept? = inv(fn c -> dotall? or c != ?\n end, neg?)
    # negation turns Match into peek look ahead
    Match.init(accept?, neg?, caret('.', neg?))
  end

  @doc "Match any character in the range between two characters (inclusive)."
  @spec match_char_range(T.char_pair(), boolean()) :: pid()
  def match_char_range({c1, c2} = cr, neg? \\ false) when is_char_range(cr) do
    accept? = inv(fn c -> c1 <= c and c <= c2 end, neg?)
    # negation turns Match into peek look ahead
    Match.init(accept?, neg?, caret([c1, ?-, c2], neg?))
  end

  # optionally invert the acceptor to be NOT the original result
  @spec inv(T.acceptor(), boolean()) :: T.acceptor()
  defp inv(accept?, false), do: accept?
  defp inv(accept?, true), do: fn c -> not accept?.(c) end

  # optionally prefix the label with '^' for negation
  @spec caret(charlist(), boolean()) :: String.t()
  defp caret(chars, false), do: IO.chardata_to_string(chars)
  defp caret(chars, true), do: IO.chardata_to_string([?^ | chars])
end
