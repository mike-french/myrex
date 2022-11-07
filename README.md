
# myrex - MY Regular Expression in eliXir

An Elixir library for matching strings against regular expressions (REGEX).

The implementation is based on the idea of _Process Oriented Programming:_ 
* Algorithms are implemented using a fine-grain directed graph of 
  independent shared-nothing processes.
* Processes communicate asynchronously by passing messages. 
* Process networks naturally run in parallel.

The REGEX is converted to an Abstract Syntax Tree (AST)
using a variation of the _Shunting Yard_ 
[Wikipedia](https://en.wikipedia.org/wiki/Shunting_yard_algorithm)
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
* strings are preserved as binaries
  \{[Erlang](https://www.erlang.org/doc/efficiency_guide/binaryhandling.html)\]
* short input strings (< 64B) are copied between processes
* large input strings (>=64B) are kept as a single copy,
  with all processes using references into shared memory

Stages of pre-processing:
* compiling a REGEX into an NFA:
  * lexical processing of the REGEX to a token sequence
  * parsing the tokens into an AST
  * traversing the AST to build an NFA process network
* matching an input string against an NFA process network

Two execution patterns:
* single network that process multiple input strings simultaneously 
* a dedicated independent network is built and torn down for each input 

### Captures

A _group_ in the REGEX is delimited by brackets: `(...)`. 
When an input string is successfully matched, 
the fragment matching the group is stored as a _capture._
The set of all captures is returned as a map of name keys
to capture valules. 

Names are the 1-based integer order 
of the opening `(` in the REGEX. 
The 0-index capture always refers to the whole input string.

Capture values can be represented in two ways:
* The `{position, length}` reference into the input string.
* The actual substring matched by the group.

## NFA Design

A process network is a directed graph that has processes for nodes
and message pathways as edges.
A process subgraph has a single input edge and one or more output edges.
The subgraph may be a single process that has both an input and outputs.

The NFA is built using a variation of Thomson's Algorithm 
based on process _combinators._
A combinator is a function that takes one or more process subgraphs
and combines them into a single larger graph.
Process combinators correspond to AST branch nodes.
Combinators used to recursively build larger networks
from smaller operator subgraphs, 
grounded in atomic character matchers
\[[Cox](https://swtch.com/~rsc/regexp/regexp1.html)\].

There are four processes that are used by combinators
to implement parts of the AST as process subgraphs:
* Branch nodes use `Split` to clone (fan out) 
  traversals across 2 or more downstream subgraphs.
* Groups use `BeginGroup` and `EndGroup` to record captures.
* Leaf nodes use `Match` with an acceptor function
  to do the actual matching of individual characters, 
  character ranges and character classes.
  
### Sequence and Group

Combinator for a sequence of process networks `_P1..Pn_` :

```
       +----+             +----+
in --->| P1 |---> ... --->| Pn | ---> outputs
       +----+             +----+
```
Combinator for a group capture around a sequence `(...)`.

```
       +-----+    +--+             +--+    +-----+
in --->|Begin|--->|P1|---> ... --->|Pn|--->| End |---> out
       |Group|    +--+             +--+    |Group|
       +-----+                             +-----+
```

  
### Alternate Choice

Combinator for fan-out of alternate matches `|`.

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

### Quantifiers

Combinator for zero or one repetitions `?`.

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

Combinator for one or more repetitions `+`. 

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
Combinator for zero or more repetitions `*`.

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

