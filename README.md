
# myrex - MY Regular Expression in eliXir

An Elixir library for matching strings against regular expressions (REGEX).

The implementation is based on the idea of _Process Oriented Programming:_ 
* Algorithms are implemented using a fine-grain directed graph of 
  independent shared-nothing processes.
* Processes communicate asynchronously by passing messages. 
* Process networks naturally run in parallel.

The REGEX is converted to an Abstract Syntax Tree (AST)
using a variation of the _Shunting Yard_ 
\[[Wikipedia](https://en.wikipedia.org/wiki/Shunting_yard_algorithm)\]
parsing algorithm.

The AST is used to build a Non-deterministic Finite Automaton (NFA)
using a variation of _Thomson's Algorithm_
\[[Wikipedia](https://en.wikipedia.org/wiki/Thompson%27s_construction)\].

The NFA is executed directly by propagating messages through the network.

The process network is a directed graph that will contain cycles
to implement quantified repetition.
Quantifiers and alternate choices are implemented
by individual processes of the NFA having 2 or more output edges.
Traversals are duplicated by sending messages 
along _all_ these outgoing edges at once.

All possible traversals are explored in parallel.
Processes implementing rules that do not match the input 
cause the traversal to terminate. A traversal that reaches the 
final process returns a successful match of the input.
A successful match result contains substrings of the input 
captured for groups in the REGEX.

The runtime execution of the process network depends on
the Erlang BEAM scheduler being _fair,_
which means that all active traversals will make some
incremental progress until a successful match is found.
The scheduler will ensure that a single exponentially long
failed match does not starve other traversals.
However, this also means it cannot guarantee the efficient 
dedicated execution of an exponentially long successful match.

Each message contains the traversal state for the match:
* A copy or reference to the input string.
* The current position in the string.
* The current state for groups:
  * Previous capture results.
  * Stack of currently open groups.
* A client process return address for the result.


## Features

A simple regular expression processor.

Standard syntax:
* literal char _c_
* `.` any char
* `|` alternate choice
* `?` zero or one 
* `+` one or  more
* `*` zero or more
* `{` _n_ `}` exactly _n_ repeats
* `(` begin group
* `(?:` begin group without capture
* `)` end  group
* `[`  begin character class
* `]`  end character class
* `-`  character range
* `\` escape character

Escapes:
* `\C` escape special character _C_
* `\xHH` escape for character value _HH_ with 2 hex digits
* `\uHHHH` escape for Unicode codepoint _HHHH_ with 4 hex digits

Binary Data:
* Strings are processed as binaries
  \{[Erlang](https://www.erlang.org/doc/efficiency_guide/binaryhandling.html)\]
  not converted to character lists.
* Short input strings (< 64B) are copied between processes.
* Large input strings (>=64B) are kept as a single copy,
  with all processes using references into shared heap memory.

Stages of processing:
* Compiling a REGEX into an NFA:
  * Lexical processing of the REGEX to a token sequence.
  * Parsing the tokens into an AST.
  * Traversing the AST to build an NFA process network.
* Matching an input string against an NFA process network.

Two execution patterns:
* Batch - single network that process multiple input strings simultaneously.
* Oneshot - dedicated independent network is built and torn down for each input. 

Two traversal strategies:
* First - return the first match and halt execution.
* All - wait for all traversals to complete,
  return all captures for ambiguous matches.

### Captures

A _group_ in the REGEX is delimited by brackets: `(...)`. 
When an input string is successfully matched, 
the fragment matching the group is stored as a _capture._
The set of all captures is returned as a map of name keys
to capture valules. 

Names are the 1-based integer order 
of the opening `(` in the REGEX. 
The 0-index capture always refers to the whole input string.
In future, explicitly named captures will be supported.

Capture values can be represented in two ways:
* The `{position, length}` reference into the input string.
* The actual substring (binary) matched by the group.

## NFA Design

A process network is a directed graph that has processes for nodes
and message pathways as edges.
A process subgraph has a single input edge and one or more output edges.
The subgraph may be a single process that has both an input and 
one or more outputs.

The NFA is built using a variation of Thomson's Algorithm 
based on process _combinators._
A combinator is a function that takes one or more process subgraphs
and combines them into a single larger graph.
Process combinators correspond to AST branch nodes.
Combinators recursively build larger networks
from smaller operator subgraphs, 
grounded in atomic character matchers
\[[Cox](https://swtch.com/~rsc/regexp/regexp1.html)\].

### Combinators

There are four processes used by combinators
to implement parts of the AST as process subgraphs:
* Branch nodes (quantifiers and alternate choice) 
  use `Split` to clone (fan out) traversals 
  across 2 or more downstream subgraphs.
* Groups use `BeginGroup` and `EndGroup` to record captures.
* Leaf nodes use `Match` with an _acceptor_ function
  to do the actual matching of individual characters, 
  character ranges and character classes.
  
#### Sequence and Group

Combinator for a sequence of process networks `P1 P2 .. Pn`:

```
       +----+             +----+
in --->| P1 |---> ... --->| Pn | ---> outputs
       +----+             +----+
```
Combinator for a group capture around a sequence `(P1 P2 .. Pn)`:

```
       +-----+    +----+           +----+    +-----+
in --->|Begin|--->| P1 |--->...--->| Pn |--->| End |---> out
       |Group|    +----+           +----+    |Group|
       +-----+                               +-----+
```

  
#### Alternate Choice

Combinator for fan-out of alternate matches `P1 | P2 | .. | Pn`
with Split process _S_ :

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

#### Quantifiers

Combinator for zero or one repetitions `P?`.

Split node _S_ can bypass the process subgraph _P_ (zero).

```
        +---+
        | P |---> outputs
        +---+
          ^ 
          | 
        +---+
 in --->| S |---> output
        +---+
```

Combinator for one or more repetitions `P+`. 

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
Combinator for zero or more repetitions `P*`.

Split node _S_ can cycle through the process node _P_ (more).
Split node _S_ can bypass the process subgraph _P_ (zero).
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

### Interface Processes
  
There are two process used for the 
overall input and output of the NFA process network:
* `Start` - the initial process where strings are injected for matching.
* `Success` - the final process where successful matches are emitted.

The `Start` process also implements construction of the NFA
by spawning and connecting child processes. 
The child processes are _linked_ to the `Start` process,
so the whole network can be torn down after use, or on error.

The process network has a lifecycle based on _batch_ or _oneshot_ patterns.

### Execution Processes

The matching of individual input strings is managed by an 
`Executor` process instance.
An `Executor` is created for each input string, 
and exits when the matching process completes.  

The `Executor` passes the input string to the `Start` process,
monitors the number of active traversals, 
receives notification of failed matches,
and may get a successful match result from the `Success` process.
The `Executor` exits after the result is returned to the calling client.

A _oneshot_ `Executor` builds a private NFA process network,
manages execution for the input string, 
and tears down the network at the end of the match.

A _batch_ `Executor` just re-uses an existing NFA process network
and does not tear the network down at the end.

## Multiple Matches

Some regular expressions are ambiguous and will have multiple matches, 
For example, the string `a` matches the regex `(a?)(a*)` in 2 different ways,
and the resulting captures will have different values: `"a",""` and `"","a"`.

The outcome for ambiguous regexes is usually 
based on whether the operators are _greedy_ or not. 
The Myrex implementation has local atomic operators 
that execute in parallel as an NFA, so they cannot choose 
`greedy` or `non-greedy` behaviour.

However, there is an option to choose how multiple matches are handled:
* _First_ - stop at the first successful match and return the capture.
  If it is a oneshot execution, then teardown the NFA process network.
  If it is a batch execution, then just halt the `Executor` process.
* _All_ - wait for all traversals to complete and return all possible captures.

The first match is non-deterministic - the clue is in the name _*N*_ FA :)
The actual outcome depends on the Erlang BEAM scheduler.
In practice, it appears that non-greedy execution is favoured.
If the regular expression is not ambiguous, then the option should be _first,_
because there may be a long delay to wait for all traversals to finish.

For example: let's say the exponential operator `^` means repeat 
characters and groups, so `a^4` means `aaaa` and `(a?)^4` means `a?a?a?a?`.
We will consider a regex of the form `(a?)^n (a*)^n` matching a string of `a^n`
(a wild exaggeration from the example in
\[[Cox](https://swtch.com/~rsc/regexp/regexp1.html)\]).

The no. of matches, _M(n),_ is calculated by a dot product
of two vectors sliced from Pascal's Triangle
e.g. `M(3) = [1,3,3,1] * [1,3,6,10] = 1+9+18+10 = 38`
(but this margin is too small to contain a proof :)

Here is the number of traversals _M_ for each value of _n,_

```
+------+---+---+----+-----+-------+-------+--------+---------+---------+
|  n   | 1 | 2 |  3 |   4 |     5 |     6 |      7 |       8 |       9 |
| M(n) | 2 | 8 | 38 | 192 | 1,002 | 5,336 | 28,814 | 157,184 | 864,146 |
+------+---+---+----+-----+-------+-------+--------+---------+---------+
```

## Usage

### Public Interface

`myrex` module

### Options

Options are passed as `Keyword` pairs.

The currently supported keys and values are:

`:return` the capture values to return in match results:
* `:all` (default) - all captures are returned, 
  except those explicitly excluded using `(?:...)` group syntax.
* _names_ - a list of names (1-based integers) to return a capture value.
* `:none` - no captures are returned.

`:return` the type for group capture results:
* `:index` (default) - the raw `{ position, length }` reference into the input string.
* `:binary` - the actual substring of the capture.

`:dotall` (boolean) (default `false`) - 
  force the _any character_ wildcard `.` to include newline `\n`.
  
`:timeout` (default 1000ms) - the timeout (ms) for executing a string match

`:multiple` decide bahviour when the regular expression is ambiguous:
* `:first` (default) - stop at the first successful match, return the capture.
  If it is a oneshot execution, then teardown the NFA process network.
  If it is a batch execution, then just halt the `Executor` process.
* `:all` - wait for all traversals to complete and return all possible captures.


### Examples

## Performance

`TODO`

## Project 

Compile the project:

`mix deps.get`

`mix compile`

Run dialyzer for type analysis:

`mix dialyzer`

Run the tests:

`mix test`

Generate the documentation:

`mix docs`

## License

This software is released under the permissive open source [MIT License](LICENSE.txt).

The code and documentation are Copyright © 2022 Mike French

