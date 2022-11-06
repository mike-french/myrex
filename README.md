
# myrex

An Elixir library for matching strings against regular expressions (REGEX).

The implementation is based on the idea of _Process Oriented Programming._ 
Algorithms are implemented using a network of independent shared-nothing processes
that communicate by passing messages. 
The networks naturally run in parallel across multiple cores.

The REGEX is converted to an Abstract Syntax Tree (AST)
using a variation of the Shunting Yard parsing algorithm.
The AST is used to build a Non-deterministic Finite Automaton (NFA)
using a variation of Thomson's Algorithm.

## Features

A simple regular expression processor.

Standard syntax:
* literal char _c_
* `.` any char
* `|` alternate choice
* `?` zero or one 
* `+` one or  more
* `*` zero or more
* `(` begin group
* `(?:` begin group without capture
* `)` end  group
* `[`  begin character class
* `]`  end character class
* `-`  character range
* `\` escape character

Escapes:
* `\c` escape special character _c_
* `\xHH` escape character value _HH_ with 2 hex digits
* `\uHHHH` escape Unicode codepoint _HHHH_ with 4 hex digits

Binary Data
* strings are preserved as 
  [Erlang binaries](https://www.erlang.org/doc/efficiency_guide/binaryhandling.html)
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

