defmodule Myrex.Types do
  @moduledoc "Types and guards for Myrex."

  alias Myrex.Uniset

  # -----------------------------
  # cardinal and ordinal integers
  # -----------------------------

  @typedoc "A non-negative cardinal count or length."
  @type count() :: non_neg_integer()
  defguard is_count(n) when is_integer(n) and n >= 0

  @typedoc "A positive cardinal count or length."
  @type count1() :: pos_integer()
  defguard is_count1(n) when is_integer(n) and n >= 1

  @typedoc "A positive cardinal count of at least 2."
  @type count2() :: pos_integer()
  defguard is_count2(n) when is_integer(n) and n >= 2

  @typedoc "Ordinal position in the input string (0-based)."
  @type position() :: pos_integer()
  defguard is_pos(i) when is_integer(i) and i >= 0

  # -----------------
  # public interfaces
  # -----------------

  @typedoc "A regular expression is a string."
  @type regex() :: String.t()

  @typedoc """
  Command options to compile and run Myrex.

  Option keys:

  `:dotall` (boolean) - force the any character wildcard `.` to include newline (default `false`).

  `:return` the type for group capture results:
  * `:index` (default) - the raw `{ position, length }` reference into the input string
  * `:binary` - the actual substring of the capture

  `:capture` the capture values to return in match results 
  (in addition to the `0` capture of the whole input string):
  * `:all` (default) - all captures are returned, except those explicitly excluded using `(?:...)`
  * `:named` - all explicitly named groups, but no unnamed or anonymous groups
  * _names_ - a list of names (1-based integer ordinals) to return a capture value
  * `:none` - no captures returned

  `:timeout` (default 1000ms) - the timeout (ms) for executing a string match

  `:multiple` how to handle multiple successful matches:
  * `:one` (default) - return the first match and truncate the traversals
  * `:all` - complete all the actual substring of the capture

  `:graph_name` - (string) the filename for DOT and PNG graph diagram output
  """
  @type options() :: Keyword.t()

  @type option_key() :: :dotall | :return | :capture | :timeout | :multiple

  @type multiple_flag() :: :one | :all
  @type capture_flag() :: :none | :named | :all
  @type return_flag() :: :index | :binary

  def default(:timeout), do: 1_000
  def default(:multiple), do: :one
  def default(:dotall), do: false

  @typedoc """
  The name for a capture group. 

  Groups are automatically assigned a 1-based index,
  and index 0 is reserved for the whole input string.
  Groups explicitly named with a string are also allowed. 
  """
  @type capture_name() :: count() | {count1(), String.t()} | :search
  defguard is_name(n)
           when (is_integer(n) and n >= 0) or
                  (is_tuple(n) and tuple_size(n) == 2) or
                  n == :search

  @doc "Get the list of capture keys from a capture name."
  @spec names(capture_name()) :: [count1() | String.t()]
  def names({g, name}), do: [g, name]
  def names(g) when is_integer(g) or is_binary(g), do: [g]
  def names(:search), do: []

  @typedoc "A reference into the input string for a capture."
  @type capture_index() :: {position(), count1()}

  @typedoc "A capture value as an index or a string."
  @type capture_value() :: :no_capture | capture_index() | String.t()

  @typedoc "The set of completed captures from a partial or total match."
  @type captures() :: %{capture_name() => capture_value()}

  @typedoc "Search result containing substring reference and set of captures."
  @type search_captures() :: {capture_index(), captures()}

  @typedoc """
  The result of trying to match the regular expression.

  When the result is `:no_match`, the capture just contains 
  key '0' with the value of the whole input string.

  If the `:multiple` option is `:one`, then a successful result is a single `:match`.
  If the `:multiple` option is `:all`, then a successful result is `:matches`
  with a list of captures, even if the list just has one member.
  """
  @type match_result() ::
          {:no_match, captures()}
          | {:match, captures()}
          | {:matches, [captures()]}

  defguard is_match_result(r)
           when is_tuple(r) and
                  tuple_size(r) == 2 and
                  (elem(r, 0) == :no_match or
                     elem(r, 0) == :match or
                     elem(r, 0) == :matches)

  @typedoc """
  The result of trying to search for the regular expression.

  When the result is `:no_match`, the capture just contains 
  key '0' with the value of the whole input string.

  If the `:multiple` option is `:one`, then a successful result is a single `:search`.
  If the `:multiple` option is `:all`, then a successful result is `:searches`
  with a list of indexed captures, even if the list just has one member.
  """
  @type search_result() ::
          {:no_match, captures()}
          | {:search, capture_index(), captures()}
          | {:searches, [search_captures()]}

  defguard is_search_result(r)
           when is_tuple(r) and
                  ((tuple_size(r) == 2 and
                      (elem(r, 0) == :no_match or elem(r, 0) == :searches)) or
                     (tuple_size(r) == 3 and elem(r, 0) == :search))

  @typedoc """
  The result of generating a string for the regular expression.

  # If the `:multiple` option is `:one`, then a successful result is a single `:search`.
  # If the `:multiple` option is `:all`, then a successful result is `:searches`
  # with a list of indexed captures, even if the list just has one member.
  """
  @type generate_result() :: {:generate, String.t()}

  defguard is_gen_result(r) when is_tuple(r) and tuple_size(r) == 2 and elem(r, 0) == :generate

  # ------------
  # lexer tokens
  # ------------

  # guard for the built-in `char()` type
  defguard is_char(c) when 0 <= c and c <= 0x10FFFF

  @typedoc """
  Token types generated by the lexer
  and the first pass of the parser.
  """
  @type token() ::
          :any_char
          | :zero_one
          | :one_more
          | :zero_more
          | :alternate
          | :begin_sequence
          | :end_sequence
          | :end_group
          | :begin_class
          | :neg_class
          | :end_class
          | :range_to
          # compound lexical tokens
          | {:begin_group, :nocap | count1() | String.t()}
          | {:repeat, count2()}
          | {:char_block, sign(), atom()}
          | {:char_category, sign(), atom()}
          | {:char_script, sign(), atom()}
          # postfix parser token
          # to support the parser stack
          | {:alternate, count2()}

  @typedoc "Tokens emitted by the lexer and first pass of the parser."
  @type tokens() :: [token() | char()]

  # ----------
  # parser AST 
  # ----------

  @typedoc "Sense for character classes and properties."
  @type sign() :: :neg | :pos

  @typedoc """
  A character range token within a character class, 
  for example `a-z` or `0-9`.
  """
  @type char_pair() :: {char(), char()}
  defguard is_char_range(cr)
           when is_char(elem(cr, 0)) and
                  is_char(elem(cr, 1)) and
                  elem(cr, 0) < elem(cr, 1)

  @typedoc """
  A character range AST node within a character class AST node.
  Character range is not a standalone leaf node.
  """
  @type char_range() :: {:char_range, char(), char()}

  @typedoc "The kinds of character property."
  @type property_tag() :: :char_block | :char_category | :char_script

  @typedoc """
  A character property AST node that can be standalone leaf node,
  or within a character class AST node.
  """
  @type char_property() :: {property_tag(), sign(), atom()}

  @typedoc """
  A character class AST node that can be positive or negated.
  """
  @type char_class() :: {:char_class, sign(), [char() | char_range() | char_property()]}

  # note the reuse of token names as AST node names
  @typep branch_node() ::
           {:sequence, [ast()]}
           | {:group, :nocap | capture_name(), [ast()]}
           | {:alternate, [ast()]}
           | {:zero_one, ast()}
           | {:one_more, ast()}
           | {:zero_more, ast()}
           | {:repeat, count2(), ast()}
           | char_class()

  @typep leaf_node() :: char() | :any_char | char_property()

  @typedoc "All nodes of the Abstract Syntax Tree (AST)."
  @type ast() :: branch_node() | leaf_node()

  @typedoc "The root of the AST returned from the parser."
  @type root() :: branch_node()

  # --------------
  # Internal types
  # --------------

  @typedoc "A function that matches a single character."
  @type acceptor() :: (char() -> boolean())

  @typedoc "A function that generates zero or one characters."
  @type generator() :: (() -> nil | char())

  @typedoc """
  A stack of open groups.
  Each group is represented by the name and start position.
  """
  @type groups() :: [{capture_name(), position()}]

  @typedoc """
  Parser traversal state passed as a message between NFA nodes.
  The input state is the remaining string to be processed,
  and its start position within the original input.
  The group capture state is the stack of current open groups,
  and a map of completed captures.
  The executor is the process for reporting changes in the 
  message count and the final result of match or no match.
  """
  @type par_state() :: {:parse, String.t(), position(), groups(), captures(), executor :: pid()}
  defguard is_par_state(s) when is_tuple(s) and tuple_size(s) == 6 and elem(s, 0) == :parse

  @typedoc """
  Generator traversal state passed as a message between NFA nodes.

  The `Uniset` is for use inside of negated character classes.

  The generator is the process address for reporting results.
  """
  @type gen_state() :: {:generate, String.t(), nil | Uniset.t(), generator :: pid()}
  defguard is_gen_state(s) when is_tuple(s) and tuple_size(s) == 3 and elem(s, 0) == :generate
end
