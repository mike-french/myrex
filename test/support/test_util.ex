defmodule Myrex.TestUtil do
  # ----------------------------------------------
  # dumping of trace and debug info during testing

  # control dumping within a test
  def set_dump(dump?) do
    Process.put(:dump, dump?)
  end

  # drop-in replacement for IO.inspect
  def dump(arg, opts \\ []) do
    if Process.get(:dump, false) do
      IO.inspect(arg, opts)
    end
  end

  # drop-in replacement for IO.puts
  def puts(arg) do
    if Process.get(:dump, false) do
      IO.puts(arg)
    end
  end

  def newline(), do: puts("")
end
