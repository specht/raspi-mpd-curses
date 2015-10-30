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
    Curses.noecho
    Curses.init_screen()
#     Curses.nonl()
    Curses.raw()
    Curses.cbreak
#     Curses.stdscr.nodelay = 1
    Curses.start_color()
    (0..7).each do |y|
        (0..7).each do |x|
            Curses.init_pair(y * 8 + x, x, y)
        end
    end

    win = Curses::Window.new(HEIGHT, WIDTH, 0, 0)
    win.keypad = true
#     win.box(0, 0)
    win.setpos(0, 0)

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

    def handle_message(win, data)
#         if data[:from_first] == 'playlistinfo'
#             data[:data].each_with_index do |x, _|
#                 win.setpos(_ + 1, 1)
#                 win.attron(color_pair(1) | A_NORMAL) do
#                     win.addstr("#{_ + 1}. #{x['Title']}")
#                 end
#                 win.setpos(_ + 1, 33)
#                 win.addstr(sprintf('%6s', s_to_h_m_s(x['Time'])))
#             end
#             win.refresh
#         end
        if data[:from_full] == 'list album'

#             (0..24).each do |_|
#                 x = data[:data][_ + 10]
#                 win.setpos(_ + 2, 1)
#                 win.attron(color_pair(1) | A_NORMAL) do
#                     win.addstr(x[0, 37])
#                 end
#             end
            win.refresh
        end
    end

    $current_command_mutex = Mutex.new
    $current_command = []

    pipe_r, $pipe_w = IO.pipe
    mpd_socket = TCPSocket.new('127.0.0.1', 6600)
    mpd_socket.set_encoding('UTF-8')
    response = mpd_socket.gets
    # puts response

    def push_command(command)
        unless command == 'noidle'
            $current_command_mutex.synchronize { $current_command.push({:first => command.split(' ').first, :full => command}) }
        end
        $pipe_w.puts command
    end

    response = ''

    def promote(x)
        return x.to_i if x =~ /^\d+$/
        return x.to_f if x =~ /^\d+\.\d+$/
        return x.split(':').map { |x| x.to_i } if x =~ /^((\d+):?)+$/
        return x
    end

    push_command('noidle')
    push_command('playlistinfo')
    push_command('list artist')
    push_command('list album')
    push_command('playlistinfo')
    push_command('idle')
    while true do
        rs, ws, es = IO.select([STDIN, mpd_socket, pipe_r], [], [], 30)
        if rs.nil?
            push_command('noidle')
            push_command('@ping')
            push_command('idle')
        else
            if rs.include?(STDIN)
                x = win.getch
#                 if x == Curses::Key::RIGHT
                    print "0x#{x.ord.to_s(16)}"
#                 end
            end
            if rs.include?(pipe_r)
                message = pipe_r.gets
    #             puts "> #{message}"
                mpd_socket.puts(message.sub(/^@/, ''))
            end
            if rs.include?(mpd_socket)
                result = mpd_socket.gets
    #             puts "< #{result}"
                response += result
                if result.strip == 'OK' || result.strip.split(' ').first == 'ACK'
                    $current_command_mutex.synchronize do
                        from_command = $current_command.shift

                        result = {}
                        result[:from_full] = from_command[:full]
                        result[:from_first] = from_command[:first]
                        result[:data] = response
                        if ['stats', 'status'].include?(from_command[:first])
                            lines = response.split("\n")
                            lines.pop
                            result[:data] = {}
                            lines.each do |line|
                                k = line.split(':')[0]
                                v = line[k.size + 1, line.size].strip
                                result[:data][k] = promote(v)
                            end
                        end
                        if ['playlistinfo', 'search', 'currentsong'].include?(from_command[:first])
                            lines = response.split("\n")
                            lines.pop
                            result[:data] = []
                            lines.each do |line|
                                k = line.split(':')[0]
                                v = line[k.size + 1, line.size].strip
                                if k == 'file'
                                    result[:data] << {}
                                end
                                result[:data].last[k] = (from_command[:first] == 'search') ? v : promote(v)
                            end
                            if from_command[:first] == 'search'
                                # group by artist, album, song
                                songs = result[:data]
                                [:artist, :album, :title].each { |x| result[x] = Set.new() }
                                songs.each do |song|
                                    [:artist, :album, :title].each { |x| result[x] << song[x.to_s.capitalize] }
                                end
                                [:artist, :album, :title].each { |x| result[x] = result[x].to_a.sort }
                            end
                        end
                        if ['list', 'list'].include?(from_command[:first])
                            lines = response.split("\n")
                            lines.pop
                            result[:data] = []
                            lines.each do |line|
                                k = line.split(':')[0]
                                v = line[k.size + 1, line.size].strip
                                result[:data] << v
                            end
                        end
                        if from_command[:first] == 'idle'
                            # add information of interest
                            result[:changed] = {}
                            response.split("\n").each do |line|
                                if line[0, 8] == 'changed:'
                                    what = line.sub('changed:', '').strip
                                    result[:changed][what] = true
                                    # player mixer playlist
                                end
                            end
                        end
#                         result[:lines] = []
#                         response.split("\n").each do |line|
#                             result[:lines] << line
#                         end
                        if result[:from_first] != 'idle' && result[:from_first][0] != '@'
#                                 $ws._send(result.to_json)
                            handle_message(win, result)
                        end
                    end
                    if response[0, 8] == 'changed:'
                        push_command('noidle')
                        response.split("\n").each do |line|
                            if line[0, 8] == 'changed:'
                                what = line.sub('changed:', '').strip
                                # player mixer playlist
                                if what == 'playlist'
                                    push_command('playlistinfo')
                                end
                                if what == 'player'
                                    push_command('status')
                                    push_command('currentsong')
                                end
                            end
                        end
                        push_command('idle')
                    end
                    response = ''
                end
            end
        end
    end

#     win.getch

    mpd_socket.close
ensure
#     win.close
end
