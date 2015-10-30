#!/usr/bin/env ruby

# require 'curses'
#
# Curses::init_screen
# w = Curses::Window.new 20,60,0,0
# w.box ?|, ?-
# w.keypad true
# chr = w.getch
# w.setpos 2,4
# w.addstr %q{Caught enter} if chr == Curses::Key::ENTER
# w.addstr %q{Caught LEFT} if chr == Curses::Key::LEFT
# # w.addstr %q{Caught "\n"} if chr.chr == "\n"
# w.refresh
# w.getch
# Curses::close_screen
#
# __END__

require 'curses'
require 'json'
# require 'ncurses'
require 'pry'
# require 'ruby-mpd'
require 'set'
require 'socket'
require 'thread'
require 'yaml'
include Curses

WIDTH = 40
HEIGHT = 30

def s_to_h_m_s(s)
    m = s / 60
    s -= m * 60
    return sprintf('%d:%02d', m, s)
end

begin
    Curses.init_screen()
    Curses.noecho()
#         Curses.nonl()
    Curses.cbreak()
    Curses.start_color()

    (0..7).each do |y|
        (0..7).each do |x|
            Curses.init_pair(y * 8 + x, x, y)
        end
    end
    Curses.curs_set(0)

    # init window
    win = Curses::Window.new(HEIGHT, WIDTH, 0, 0)
#     win.nodelay = true
    win.keypad = true

    (0..63).each do |x|
        win.attron(color_pair(x) | A_NORMAL) do
            win.addstr(" #{sprintf('%2d', x)} ")
        end
    end
    win.addstr("\n")
    (0..63).each do |x|
        win.attron(color_pair(x) | A_BOLD) do
            win.addstr(" #{sprintf('%2d', x)} ")
        end
    end
    win.addstr("\n")
    (0..63).each do |y|
        x = ((y & 7) << 3) | ((y >> 3) & 7)
        win.attron(color_pair(x | A_BOLD | A_REVERSE)) do
            win.addstr(" #{sprintf('%2d', x)} ")
        end
    end
    (32..127).each do |y|
        win.attron(0 | A_ALTCHARSET) do
            win.addstr(y.chr)
        end
    end
    win.refresh

    while true do
        rs, ws, es = IO.select([STDIN], [], [])
        x = win.getch
#                 if x == Curses::Key::RIGHT
        begin
            print "#{x} "
        rescue
            print 'BOTCH'
        end
    end
end
