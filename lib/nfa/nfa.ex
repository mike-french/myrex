defmodule Myrex.NFA do
  @moduledoc """
  An NFA process network for matching a regular expression
  are built using a variation of Thompson's Construction
  \[[wikipedia](https://en.wikipedia.org/wiki/Thompson%27s_construction)\]
  \[[Cox](https://swtch.com/~rsc/regexp/regexp1.html)\]

  Actual networks for elements of a regular expression 
  are described as follows:

  Linear
  { :sequence,   [P] }   -->  { P1, Pn }
  { :group,    p|[P] }   -->  { BeginGroup, EndGroup }    
  { :repeat,   N, P  }   -->  { P1, Pn }

  Parallel
  { :alternate,  [P] }   -->  { Split, [P] }
  { :zero_one,    p  }   -->  { Split, [P,Split] }
  { :char_class, [CCs]   -->  { Split, [AllCCs] }

  Loops
  { :one_more,  P }      -->  { P,  Split }
  { :zero_more, P }      -->  { Split, Split }

  Atomic
    c                        MatchChar(c)
    :char_any                MatchAnyChar
  """

  import Myrex.Types
  alias Myrex.Types, as: T

  alias Myrex.NFA.BeginGroup
  alias Myrex.NFA.EndGroup
  alias Myrex.NFA.Graph
  alias Myrex.NFA.Match
  alias Myrex.NFA.Proc
  alias Myrex.NFA.Split

  # ----------------------------
  # quantifier combinators
  # ----------------------------

  @doc """
  Combinator for zero or one repetitions.

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
    {split, [proc, split]}
  end

  @doc """
  Combinator for one or more repetitions.

  Split node _S_ can cycle to the process node _P_ (more).
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
    {split, split}
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
    # nocap group is just an anonymous sequence
    sequence(procs)
  end

  def group(procs, name) when is_list(procs) and is_name(name) do
    begin = BeginGroup.init(name)
    enndd = EndGroup.init()
    sequence([begin | procs] ++ [enndd])
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
  def sequence([first | _] = procs) do
    last = Enum.reduce(procs, fn next, prev -> Proc.connect(prev, next) end)
    {Proc.input(first), Proc.output(last)}
  end

  # ----------------------------
  # parallel combinators
  # ----------------------------

  @doc """
  Combinator for fan-out of alternate matches.

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
  @spec match_char(char()) :: pid()
  def match_char(c) do
    Match.init(&(&1 == c), IO.chardata_to_string([?', c, ?']))
  end

  @doc """
  Match any character.

  The treatment of the newline character depends on the value of the `dotall` argument:
  * `true` - any character will match, including newline.
  * `false` - any character will match, excluding newline. 
  """

  @spec match_any_char(boolean()) :: pid()
  def match_any_char(dotall?) do
    Match.init(fn c -> dotall? or c != ?\n end, ".")
  end

  @doc "Match any character in the range between two characters (inclusive)."
  @spec match_char_range(T.char_pair()) :: pid()
  def match_char_range({c1, c2} = cr) when is_cr(cr) do
    Match.init(
      fn c -> c1 <= c and c <= c2 end,
      IO.chardata_to_string([c1, ?-, c2])
    )
  end
end
