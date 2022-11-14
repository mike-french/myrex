defmodule Myrex.Types do
  @moduledoc "Types and guards for Myrex."

  # -----------------
  # type constructors
  # -----------------

  @type maybe(t) :: t | nil

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
  * `:first` (default) - return the first match and truncate the traversals
  * `:all` - complete all the actual substring of the capture
  """
  @type options() :: Keyword.t()

  @type option_key() :: :dotall | :return | :capture | :timeout | :multiple

  @type multiple_flag() :: :first | :all
  @type capture_flag() :: :none | :named | :all
  @type return_flag() :: :index | :binary

  @typedoc """
  A capture is a substring of the input 
  specified by a start position and length.
  """
  @type capture() :: {position(), count()}
  defguard is_capture(cap)
           when is_pos(elem(cap, 0)) and is_count1(elem(cap, 1))

  @typedoc """
  The index for a capture group. 
  Groups are assigned a 1-based index,
  and index 0 is reserved for the whole input string.
  """
  @type capture_name() :: non_neg_integer()
  defguard is_name(n) when is_integer(n) and n >= 0

  @typedoc "The set of completed captures from a partial or total match."
  @type captures() :: %{capture_name() => :no_capture | capture() | String.t()}

  @typedoc """
  The result of trying to match the regular expression.

  When the result is `:no_match`, the capture just contains 
  key '0' with the value of the whole input string.

  If the `:multiple` option is `:first`, then a successful result is a single `:match`.
  If the `:multiple` option is `:all`, then a successful result is `:matches`
  with a list of captures, even if the list just has one member.
  """
  @type result() :: {:no_match | :match, captures()} | {:matches, [captures()]}
  defguard is_result(r)
           when is_tuple(r) and
                  tuple_size(r) == 2 and
                  (elem(r, 0) == :no_match or elem(r, 0) == :match or elem(r, 0) == :matches)

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
          | :end_class
          | :range_to
          # compound lexical tokens
          | {:begin_group, :nocap | count1()}
          | {:repeat, count2()}
          # postfix parser token
          # to include the parser stack
          | {:alternate, count2()}

  @typedoc "Tokens emitted by the lexer and first pass of the parser."
  @type tokens() :: [token() | char()]

  # ----------
  # parser AST 
  # ----------

  @typedoc """
  A character range token within a character class, 
  for example `a-z` or `0-9`.
  """
  @type char_pair() :: {char(), char()}
  defguard is_cr(cr)
           when is_char(elem(cr, 0)) and
                  is_char(elem(cr, 1)) and
                  elem(cr, 0) < elem(cr, 1)

  @typedoc """
  A character range AST node within a character class AST node.
  """
  @type char_range() :: {:char_range, char(), char()}

  # TODO - is char_class allowed as a root node? add test

  # note the reuse of token names as AST nodes

  @typep branch_node() ::
           {:char_class, [char() | char_range()]}
           | {:sequence, [ast()]}
           | {:group, :nocap | capture_name(), [ast()]}
           | {:alternate, [ast()]}
           | {:zero_one, ast()}
           | {:one_more, ast()}
           | {:zero_more, ast()}
           | {:repeat, count2(), ast()}

  @typep leaf_node() :: char() | :any_char

  @typedoc "All nodes of the Abstract Syntax Tree (AST)."
  @type ast() :: branch_node() | leaf_node()

  @typedoc "The root of the AST returned from the parser."
  @type root() :: branch_node()

  # ----------------
  # Process networks 
  # ----------------

  @typedoc """
  A summary of the interface for a process network.

  The options are:
  * `InOut` a single process pipeline stage, shorthand for `{ InOut, InOut }` 
  * `{ Input, Output }` a single input and single output
  * `{ Input, [Output] }` fan-out from single input to multiple outputs
  """
  @type proc() :: pid() | {pid(), pid()} | {pid(), [pid()]}
  defguard is_proc(proc)
           when is_pid(proc) or
                  (is_tuple(proc) and
                     is_pid(elem(proc, 0)) and
                     (is_pid(elem(proc, 1)) or is_list(elem(proc, 1))))

  @typedoc "A list of process networks."
  @type procs() :: [proc()]

  @typedoc "A function that builds an NFA process network and returns the input process."
  @type builder() :: (() -> pid())

  # --------------
  # Internal types
  # --------------

  @typedoc "A function that matches a single character."
  @type acceptor() :: (char() -> boolean())

  @typedoc """
  A stack of open groups.
  Each group is represented by the name and start position.
  """
  @type groups() :: [{capture_name(), position()}]

  @typedoc """
  Traversal state passed as a message between NFZ nodes.
  The input state is the remaining string to be processed,
  and its start position within the original input.
  The group capture state is the stack of current open groups,
  and a map of completed captures.
  The executor is the process for reporting changes in the 
  message count and the final result of match or no match.
  """
  @type state() :: {String.t(), position(), groups(), captures(), executor :: pid()}
end
