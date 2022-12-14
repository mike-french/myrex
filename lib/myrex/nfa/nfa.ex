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
  { :char_class_neg, [CCs]  -->  { BeginNegCC, EndNegCC }

  Atomic
    c                        MatchChar(c)
    :char_any                MatchAnyChar
  """

  import Myrex.Types
  alias Myrex.Types, as: T

  alias Myrex.NFA.BeginGroup
  alias Myrex.NFA.BeginNegCC
  alias Myrex.NFA.EndGroup
  alias Myrex.NFA.EndNegCC
  alias Myrex.NFA.Match
  alias Myrex.NFA.Split
  alias Myrex.Proc.Proc
  alias Myrex.Uniset

  # list of standard ascii whitespace characters
  @whitespace [?\s, ?\n, ?\r, ?\t, ?\v, ?\f]

  # uniset for all assigned characters
  @all Uniset.new(:all)

  # uniset for alphanumeric characters
  @xan Uniset.new(:char_category, :Xan)

  # uniset for word characters
  @xwd Uniset.new(:char_category, :Xwd)

  # uniset for space and separator characters
  @xsp Uniset.new(:char_category, :Xsp)

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
    split = Split.init({proc}, "?")
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
    split = Split.init({proc}, "+")
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
    split = Split.init({proc}, "*")
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
    begin = BeginGroup.init({:search})
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

  @spec group(T.procs(), :nocap | String.t() | T.capture_name()) :: T.proc()

  def group(procs, :nocap) when is_list(procs) do
    # no-capture group is just an anonymous sequence
    sequence(procs)
  end

  def group(procs, name) when is_list(procs) and (is_name(name) or is_binary(name)) do
    begin = BeginGroup.init({name})
    enddd = EndGroup.init(nil)
    sequence([begin | procs] ++ [enddd])
  end

  @doc """
  Combinator for an AND sequence of peek lookahead Match nodes.
  The peeking Match nodes are created by a negated character class.

  ```
          +-----+    +--+             +--+    +-----+
   in --->|Begin|--->|M1|---> ... --->|Mn|--->|End  |---> out
          |NegCC|    +--+             +--+    |NegCC|
          +-----+                             +-----+
  ```
  """

  @spec negcc_sequence(T.procs()) :: T.proc()

  def negcc_sequence(procs) when is_list(procs) do
    begin = BeginNegCC.init(nil)
    enddd = EndNegCC.init(nil)
    sequence([begin | procs] ++ [enddd])
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

  def alternate([proc], _name) do
    # Hobson's choice 
    proc
  end

  def alternate(procs, name) do
    split = Split.init({procs}, name)
    {split, Proc.outputs(procs)}
  end

  # --------------------------------
  # characters and character classes
  # --------------------------------

  @doc "Match a specific character."
  @spec match_char(char(), T.sign()) :: pid()
  def match_char(char, ccsign \\ :pos) when is_atom(ccsign) do
    inv? = inv_sign(:pos, ccsign)
    accept? = inv(fn c -> c == char end, inv?)
    gen_uni = Uniset.new(char)

    gen_fun_or_uni =
      case ccsign do
        :pos -> gen(gen_uni, inv?)
        # TODO - need to handle or add inv? flag here 
        :neg -> gen_uni
      end

    # negation turns Match into peek look ahead
    Match.init({accept?, peek_sign(ccsign), gen_fun_or_uni}, caret(char, ccsign))
  end

  @doc """
  Match any character.

  The treatment of the newline character depends on the value of the `dotall` argument:
  * `true` - any character will match, including newline.
  * `false` - any character will match, excluding newline. 
  """
  @spec match_any_char(boolean(), T.sign()) :: pid()
  def match_any_char(dotall?, ccsign \\ :pos) when is_atom(ccsign) do
    inv? = inv_sign(:pos, ccsign)
    accept? = inv(fn c -> dotall? or c != ?\n end, inv?)

    gen_fun_or_uni =
      case ccsign do
        :pos -> fn -> Uniset.pick(@all) end
        # TODO - need to handle or add inv? flag here 
        :neg -> @all
      end

    # negation turns Match into peek look ahead
    Match.init({accept?, peek_sign(ccsign), gen_fun_or_uni}, caret(?., ccsign))
  end

  @doc "Match any character in the range between two characters (inclusive)."
  @spec match_char_range(T.char_pair(), T.sign()) :: pid()
  def match_char_range({c1, c2} = cr, ccsign \\ :pos)
      when is_char_range(cr) and is_atom(ccsign) do
    inv? = inv_sign(:pos, ccsign)
    accept? = inv(fn c -> c1 <= c and c <= c2 end, inv?)
    gen_uni = Uniset.new({c1, c2})

    gen_fun_or_uni =
      case ccsign do
        :pos -> gen(gen_uni, inv?)
        # TODO - need to handle or add inv? flag here 
        :neg -> gen_uni
      end

    # negation turns Match into peek look ahead
    Match.init({accept?, peek_sign(ccsign), gen_fun_or_uni}, caret(c1, c2, ccsign))
  end

  @doc "Match a character to a unicode block, category or script."
  @spec match_property({T.property_tag(), T.sign(), atom()}, T.sign()) :: pid()
  def match_property({tag, sign, prop}, ccsign \\ :pos) when is_atom(prop) and is_atom(ccsign) do
    accept_fun =
      case tag do
        :char_block ->
          fn c -> Unicode.block(c) == prop end

        :char_script ->
          fn c -> Unicode.script(c) == prop end

        :char_category ->
          # Xwd could expand '_' to be punctuation connectors \p{Pc}
          case prop do
            :Xan -> fn c -> subcat?(c, :L) or subcat?(c, :N) end
            :Xwd -> fn c -> subcat?(c, :L) or subcat?(c, :N) or c == ?_ end
            :Xsp -> fn c -> c in @whitespace or subcat?(c, :Z) end
            _ -> fn c -> subcat?(c, prop) end
          end
      end

    gen_uni =
      case prop do
        :Any -> @all
        :Xan -> @xan
        :Xwd -> @xwd
        :Xsp -> @xsp
        _ -> Uniset.new(tag, prop)
      end

    # negation turns consuming match into peek look ahead
    inv? = inv_sign(sign, ccsign)
    acceptor = inv(accept_fun, inv?)

    gen_fun_or_uni =
      case ccsign do
        :pos -> gen(gen_uni, inv?)
        # TODO - need to handle or add inv? flag here 
        :neg -> comp(gen_uni, sign)
      end

    Match.init({acceptor, peek_sign(ccsign), gen_fun_or_uni}, prop(p(sign), prop))
  end

  # test atom to be equal or prefix of another atom
  # implements subset relation for categories, e.g. :Lu < :L
  @spec subcat?(char(), atom()) :: boolean()
  defp subcat?(c, cat) do
    sub = Unicode.category(c)
    sub == cat or String.starts_with?(Atom.to_string(sub), Atom.to_string(cat))
  end

  # convert char class sign and operator sign into an operator inversion flag
  @spec inv_sign(T.sign(), T.sign()) :: boolean()
  defp inv_sign(:pos, :pos), do: false
  defp inv_sign(:neg, :pos), do: true
  defp inv_sign(:pos, :neg), do: true
  defp inv_sign(:neg, :neg), do: false

  # convert a char class sign into a peek flag
  @spec peek_sign(T.sign()) :: boolean()
  defp peek_sign(:pos), do: false
  defp peek_sign(:neg), do: true

  # optionally invert the acceptor to be NOT the original result
  @spec inv(T.acceptor(), boolean()) :: T.acceptor()
  defp inv(accept?, false), do: accept?
  defp inv(accept?, true), do: fn c -> not accept?.(c) end

  # optionally invert a character property generator
  @spec gen(U.uniset(), boolean()) :: T.generator()
  defp gen(uni, false), do: fn -> Uniset.pick(uni) end
  defp gen(uni, true), do: fn -> Uniset.pick_neg(uni) end

  # optionally complement a charset
  @spec comp(U.uniset(), T.sign()) :: U.uniset()
  defp comp(uni, :pos), do: uni
  defp comp(uni, :neg), do: Uniset.complement(uni)

  # control character for positive or negative property
  @spec p(atom()) :: String.t()
  defp p(:pos), do: "p"
  defp p(:neg), do: "P"

  # graph label for a property
  @spec prop(String.t(), atom()) :: String.t()
  defp prop(pP, prop), do: "\\\\#{pP}{#{Atom.to_string(prop)}}"

  # optionally prefix the label with '^' for negation

  @spec caret(char(), T.sign()) :: String.t()
  defp caret(c, :pos), do: IO.chardata_to_string(chr(c))
  defp caret(c, :neg), do: IO.chardata_to_string([?^ | chr(c)])

  @spec caret(char(), char(), T.sign()) :: String.t()
  defp caret(c1, c2, :pos), do: IO.chardata_to_string(chrs(c1, c2))
  defp caret(c1, c2, :neg), do: IO.chardata_to_string([?^ | chrs(c1, c2)])

  # range of quoted characters
  defp chrs(c1, c2), do: [chr(c1), ?-, chr(c2)]

  # quote a character
  defp chr(c), do: [?', c, ?']
end
