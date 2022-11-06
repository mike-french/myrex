
# myrex - MY Regular Expression in eliXir

An Elixir library for matching strings against regular expressions (REGEX).

The implementation is based on the idea of _Process Oriented Programming._ 
Algorithms are implemented using a fine-grain directed graph of 
independent shared-nothing processes that communicate by passing messages. 
The process networks naturally run in parallel across multiple cores.

The REGEX is converted to an Abstract Syntax Tree (AST)
using a variation of the _Shunting Yard_ [Wikipedia] parsing algorithm.

The AST is used to build a Non-deterministic Finite Automaton (NFA)
using a variation of _Thomson's Algorithm_
\[[Wikipedia](https://en.wikipedia.org/wiki/Thompson%27s_construction)\]
\[[Cox](https://swtch.com/~rsc/regexp/regexp1.html)\]

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

Each message contains a copy or reference to the input string,
the current position in the string, traversal state for captures,
and a client process return address for the result.


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

Currently default naming by the order of the opening `(` in the REGEX.


### Options


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

