#!/usr/bin/env ruby19
#
# brainfuck-to-piet translator  (c) Yusuke Endoh, 2009
#
#
# usage:
#
#   $ ruby19 bf2piet.rb hello.bf > hello.piet.png
#
#
# translation approach:
#
# 1. Correspond brainfuck's tape and piet's stack.
#    - The top of the piet's stack must equal to the value that the brainfuck's
#      pointer indicates.
#    - The second top is current index of pointer, plus 3.
#    - The third top is total length of the whole tape, plus 3.
#    - The remain part of the stack is data of type except the value on the
#      current pointer.
#
#    example:
#
#    brainfuck's tape:  +---+---+---+---+---+---+
#                       | A | B | C | D | E | F |
#                       +---+---+---+---+---+---+
#                                     ^
#                                  pointer
#
#    piet's stack: (top) D 6 9 A B C E F (bottom)
#
#       where n is current index of pointer + 3
#             l is total length of tape + 3
#
#
# 2. Define auxiliary functions: pick, deposit, withdraw.
#
#    pick(n): push the n-th top value of the stack.
#     (top) A B C D E F (bottom)
#       |
#       | pick(3)
#       v
#     (top) D A B C D E F (bottom)
#
#    deposit: insert the top value to the n-th index
#
#     (top) D 6 9 A B C E F (bottom)
#       |
#       | deposit
#       v
#     (top) 6 9 A B C D E F (bottom)
#
#    withdraw: pull the n-th value to the top (inversion of deposit)
#
#     (top) 5 9 A B C D E F (bottom)
#       |
#       | withdraw
#       v
#     (top) C 5 9 A B C E F (bottom)
#
#    definitions:
#      pick(0) = dup
#      pick(n) = push(n+1); push(-1); roll; dup; push(n+2); push(1); roll
#      deposit: pick(1); push(1); roll
#      withdraw: dup; push(-1); roll
#
#
# 3. Put initializer of the piet's stack.
#
#    initial state of the stack: (top) 0 3 3 (bottom)
#
#
# 4. Put piet's instractions correspoinding to each brainfuck's instruction.
#
#    +: push(1); add
#    -: push(1); sub
#    >: deposit
#       if (the second top value) > (top value)
#         # extend tape
#         #  (top) 9 9 A B C D E F (bottom)
#         #    |
#         #    | extend
#         #    v
#         #  (top) 0 10 10 A B C D E F (bottom)
#         pop; push(1); add; dup; push(0)
#       else
#         push(1); iadd; withdraw
#       end
#    <: deposit; push(1); sub; withdraw
#    [: if (top value) * 2 <= 0
#         goto the corresponding ']'
#       end
#    ]: goto the corresponding '['
#    ,: pop; in(char)
#    .: dup; out(char)
#
# 5. Put a terminator of execution.
#

require "zlib"
require "optparse"

class Brainfuck2Piet
  def self.build_color(color)
    (0..4).step(2).map {|i| color[i, 2].hex }
  end

  COLORS = [
    ["FFC0C0", "FFFFC0", "C0FFC0", "C0FFFF", "C0C0FF", "FFC0FF"],
    ["FF0000", "FFFF00", "00FF00", "00FFFF", "0000FF", "FF00FF"],
    ["C00000", "C0C000", "00C000", "00C0C0", "0000C0", "C000C0"],
  ].map {|line| line.map {|color| build_color(color) } }
  WHITE = build_color("FFFFFF")
  BLACK = build_color("000000")

  def initialize(codel_size, code)
    @codel_size = codel_size
    depth = max_depth = 0
    @code = code.each_char.map do |c|
      case c
      when ?[; depth += 1; max_depth = [depth, max_depth].max; [?[, depth]
      when ?]; depth -= 1; [?], depth + 1]
      else c
      end
    end.map do |c, depth|
      depth ? [c, (max_depth - depth) * 2 + 4] : c
    end
    @bitmap = []
    translate
  end

  [ [nil, :push, :pop],
    [:add, :sub, :mul],
    [:div, :mod, :not],
    [:greater, :pointer, :switch],
    [:dup, :roll, :inn],
    [:inc, :outn, :outc]
  ].each_with_index do |line, hue_d|
    line.each_with_index do |insn, light_d|
      define_method("i" + insn.to_s) do |value = 1|
        (value / 2).times { paint(2) }
        paint if value % 2 == 1
        @hue = (@hue + hue_d) % 6
        @light = (@light + light_d) % 3
      end
    end
  end

  def rect(hash)
    w = hash.fetch(:w, 1)
    h = hash.fetch(:h, 1)
    x = hash.fetch(:x, @x)
    y = hash.fetch(:y, @y)
    color = hash.fetch(:c, COLORS[@light][@hue])

    @bitmap << [] until @bitmap.size >= x + w
    (x ... x + w).each do |x|
      (y ... y + h).each do |y|
        @bitmap[x][y] = color
      end
    end
  end

  def push(n)
    case
    when n >  0; ipush(n)
    when n == 0; ipush(1); ipush(1); isub
    when n <  0; ipush(1); ipush(1 - n); isub
    end
  end

  def pick(n)
    case n
    when 0; idup
    else push(n + 1); push(-1); iroll; idup; push(n + 2); push(1); iroll
    end
  end

  def deposit
    pick(1); push(1); iroll
  end

  def withdraw
    idup; push(-1); iroll
  end

  def paint(h = 1)
    rect(h: h)
    @x += 1
  end

  def white(h = 1)
    rect(h: h, c: WHITE)
    @x += 1
  end

  def save
    x, y, hue, light = @x, @y, @hue, @light
    yield
    @x, @y, @hue, @light = x, y, hue, light
  end

  def mark(*a)
    a.each_with_index do |line, y|
      line.each_char.with_index do |c, x|
        rect(x: @x + x, y: 1 + y, c: WHITE) if c != " "
      end
    end
  end

  def translate
    # initializer
    @light = @hue = 0
    rect(x: 0, y: 0, w: 2, h: 2)
    @x, @y = 0, 0; ipush(1)
    rect(x: 0, y: 1, w: 1, h: 1)
    rect(x: 0, y: 2, w: 2, h: 1)
    @x, @y = 1, 2; ipush(1)
    @x, @y = 1, 3; ipush(1)
    @x, @y = 1, 4; ipush(1)
    rect(x: 0, y: 5, w: 3, h: 1)
    rect(x: 2, y: 6, w: 1, h: 1)
    @x, @y = 2, 5; isub

    # body
    @code.each do |c, depth|
      case c
      when ?+
        mark(" # ", "###", " # ")

        push(1); paint; paint; iadd

      when ?-
        mark("", "###", "")

        push(1); paint; paint; isub

      when ?>
        mark("#", " #", "#")

        deposit; pick(1); pick(1); igreater; iswitch; paint(2); white(2)
        @hue = @light = 0
        save { ipop; push(1); iadd; idup; push(0); paint; white }
        @hue = 1
        @y += 1; push(1); iadd; withdraw; paint; white; @y -= 1
        paint(2); white

      when ?<
        mark(" #", "#", " #")

        deposit; push(1); isub; withdraw

      when ?[
        mark("##", "#", "##")

        rect(x: @x, y: @y, w: 1, h: depth - 1, c: WHITE)
        rect(x: @x, y: @y + depth - 1)
        idup; idup; imul; push(0); igreater; inot; iswitch
        paint(depth); white

      when ?]
        mark("##", " #", "##")

        push(2); ipointer; paint(depth); white
        x = @x - 3
        x -= 1 until @bitmap[x][@y + depth - 1]
        rect(x: x + 1, y: @y + depth - 1, w: @x - x - 3, h: 1, c: WHITE)
        x -= 1
        x -= 1 until @bitmap[x][@y + depth - 1]
        rect(x: x + 1, y: @y + depth - 1, w: 8, h: 1, c: WHITE)

      when ?,
        mark("", " #", "#")

        ipop; push(1); push(-1); iinc; idup; push(-1); igreater; iswitch
        save { paint; white; white }
        @y += 1
        iadd; paint; white
        @y -= 1
        iadd(2); paint; white

      when ?.
        mark("", "", "#")

        idup; ioutc
      end
    end

    # terminator
    paint
    white
    rect(x: @x, y: @y - 1, w: 1, h: 3, c: COLORS[0][0])
  end

  def png
    # normalize
    img = @bitmap
    max_height = @bitmap.map {|line| line.size }.max
    img = @bitmap.map do |line|
      line += [BLACK] * (max_height - line.size)
      line.map {|c| c || BLACK } + [BLACK]
    end.transpose

    # zoom
    img = img.map do |line|
      [line.map {|color| [color] * @codel_size }.flatten(1)] * @codel_size
    end.flatten(1)

    # build png
    bin = "\x89PNG\r\n\x1a\n"
    header = [img.first.size, img.size, 8, 2, 0, 0, 0].pack("NNCCCCC")
    bin << png_chunk("IHDR", header)
    data = img.map {|line| ([0] + line.flatten).pack("C*") }.join
    bin << png_chunk("IDAT", Zlib::Deflate.deflate(data))
    bin << png_chunk("IEND", "")

    bin
  end

  def png_chunk(type, data)
    [data.bytesize, type, data, Zlib.crc32(type + data)].pack("NA4A*N")
  end
end

codel_size = 8
output = $>
ARGV.options do |op|
  op.banner = "usage: bf2piet.rb [option] bf-code.bf > piet-code.png"
  op.on("-c=SIZE", "--codel-size=SIZE", "set codel size", Integer) do |x|
    codel_size = x.to_i
  end
  op.on("-o=FILE", "--output=FILE", "set output file") do |x|
    output = open(x, "wb")
  end
  op.parse!
end

output.print Brainfuck2Piet.new(codel_size, $<.read).png
