defmodule Myrex.Proc.Types do
  @moduledoc "Types for process networks."

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
end
