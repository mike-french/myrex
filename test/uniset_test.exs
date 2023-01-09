defmodule Myrex.UnisetTest do
  use ExUnit.Case

  import Myrex.TestUtil

  alias Myrex.Uniset

  alias Unicode.Block
  alias Unicode.GeneralCategory, as: Category
  alias Unicode.Script

  test "char" do
    set_dump(true)
    a = Uniset.new(?a)
    do_uniset(a, "a")
    set_dump(false)
  end

  test "char ranges" do
    set_dump(true)
    az = Uniset.new({?a, ?z})
    do_uniset(az, "az")
    digit = Uniset.new({?0, ?9})
    do_uniset(digit, "az")
    set_dump(false)
  end

  test "blocks" do
    for block <- Block.known_blocks() do
      uni = Uniset.new(:char_block, block)
      do_uniset(uni, block)
    end
  end

  test "categories" do
    set_dump(true)

    for cat <- Category.known_categories() -- [:Any] do
      uni = Uniset.new(:char_category, cat)
      do_uniset(uni, cat)
    end
  end

  test "scripts" do
    for script <- Script.known_scripts() do
      uni = Uniset.new(:char_script, script)
      do_uniset(uni, script)
    end
  end

  test "extensions" do
    set_dump(true)

    for ext <- [:Xan, :Xwd, :Xsp] do
      uni = Uniset.new(:char_category, ext)
      do_uniset(uni, ext)
    end

    set_dump(false)
  end

  test "all characters" do
    do_uniset(Uniset.new(:all), "ALL", false)
  end

  defp do_uniset({_uni_set, n, runs} = uni, label, neg? \\ true) do
    dump(uni, label: "#{label}")
    assert n == Uniset.count(runs)
    c = Uniset.pick(uni)
    dump(c, label: "#{label} char")
    assert Uniset.contains?(uni, c)

    if neg? do
      d = Uniset.pick_neg(uni)
      dump(d, label: "#{label} char neg")
      assert not Uniset.contains?(uni, d)
    end
  end
end
