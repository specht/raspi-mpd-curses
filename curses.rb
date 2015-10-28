#!/usr/bin/env ruby
require 'curses'
require 'json'
require 'pry'
require 'set'
require 'socket'
require 'thread'
require 'yaml'
include Curses

def sfix(s)
    s.gsub('ä', 'ae').gsub('ö', 'oe').gsub('ü', 'ue').gsub('Ä', 'AE').gsub('Ö', 'OE').gsub('Ü', 'UE').gsub('ß', 'ss')
end

def fit(s, width)
    s = sfix(s)
    return s[0, width] if s.size > width
    return sprintf("%-#{width}s", s)
end

def rfit(s, width)
    s = sfix(s)
    return s[0, width] if s.size > width
    return sprintf("%#{width}s", s)
end

class List
    def initialize(win, y0, y1)
        @win = win
        @y0 = y0
        @y1 = y1
        @yh = y1 - y0 + 1
        clear()
    end

    def clear()
        @entries = []
        @scroll_offset = 0
        @max_widths = []
        @selected_entry = nil
        @highlighted_entry = nil
        @first_selectable_entry = nil
        @last_selectable_entry = nil
        @index_for_key = {}
    end

    def set_highlighted(n)
        @highlighted_entry = n
        fix_scrolling()
    end

    def set_highlighted_by_key(key)
        set_highlighted(@index_for_key[key])
    end

    def set_selected(n)
        return if @first_selectable_entry.nil?
        unless n.nil?
            n = @first_selectable_entry if n < @first_selectable_entry
            n = @last_selectable_entry if n > @last_selectable_entry
        end
        @selected_entry = n
        fix_scrolling()
    end

    def selected()
        return nil if @selected_entry.nil?
        return @entries[@selected_entry]
    end

    def fix_scrolling()
        scroll_to = @selected_entry
        scroll_to ||= @highlighted_entry
        return if scroll_to.nil?
        screen_y = scroll_to - @scroll_offset
        if screen_y >= @yh
            @scroll_offset = scroll_to - @yh + 1
        end
        if screen_y < @first_selectable_entry
            @scroll_offset = scroll_to - @first_selectable_entry
        end
    end

    def next_selected()
        return if @first_selectable_entry.nil?
        @selected_entry = @highlighted_entry if @selected_entry.nil?
        @selected_entry ||= 0
        begin
            set_selected(@selected_entry + 1)
        end until @selected_entry.nil? || @entries[@selected_entry][:type] == :entry
    end

    def prev_selected()
        return if @first_selectable_entry.nil?
        @selected_entry = @highlighted_entry if @selected_entry.nil?
        @selected_entry ||= 0
        begin
#             if @selected_entry == 0
#                 set_selected(nil)
#             else
                set_selected(@selected_entry - 1)
#             end
        end until @selected_entry.nil? || @entries[@selected_entry][:type] == :entry
    end

    def first_selected()
        return if @first_selectable_entry.nil?
        set_selected(@first_selectable_entry)
    end

    def last_selected()
        return if @first_selectable_entry.nil?
        set_selected(@last_selectable_entry)
    end

    def add_separator(label)
        @entries << {:type => :separator, :label => label}
    end

    def add_entry(key, labels)
        @first_selectable_entry ||= @entries.size
        @last_selectable_entry = @entries.size
        @index_for_key[key] = @entries.size
        labels = [labels] unless labels.class == Array
        @entries << {:type => :entry, :labels => labels, :key => key}
        labels.each_with_index do |x, _|
            if @max_widths.size <= _
                @max_widths << 1
            end
            if x.size > @max_widths[_]
                @max_widths[_] = x.size
            end
        end
    end

    def render()
        (@y0..@y1).each do |y|
            @win.setpos(y, 0)
            yo = y - @y0 + @scroll_offset
            if yo >= 0 && yo < @entries.size
                if @entries[yo][:type] == :entry
                    attr = color_pair(0) | A_NORMAL
                    if yo == @highlighted_entry
                        if yo == @selected_entry
                            attr = color_pair(34) | A_BOLD
                        else
                            attr = color_pair(2) | A_BOLD
                        end
                    else
                        if yo == @selected_entry
                            attr = color_pair(38) | A_BOLD
                        else
                            attr = color_pair(6) | A_NORMAL
                        end
                    end
                    @win.attron(attr) do
                        s = ''
                        if @entries[yo][:labels].size == 3
                            s += rfit(@entries[yo][:labels][0], @max_widths[0])
                            s += ' '
                            s += fit(@entries[yo][:labels][1], 38 - @max_widths[0] - @max_widths[2])
                            s += ' '
                            s += rfit(@entries[yo][:labels][2], @max_widths[2])
                        else
                            s += fit(@entries[yo][:labels][0], 40)
                        end
                        @win.addstr(s)
                    end
                else
                    @win.attron(color_pair(63) | A_BOLD) do
                        s = ''
                        s += fit(@entries[yo][:label], 40)
                        @win.addstr(s)
                    end
                end
            else
                @win.attron(color_pair(0) | A_NORMAL) do
                    @win.addstr(sprintf('%-40s', ''))
                end
            end
        end
    end
end

class CursesMpdPlayer
    def initialize()
        @width = 40
        @height = 30

        @keys = {}
        @keys[:arrow_left]  = [0x1b, 0x5b, 0x44]
        @keys[:arrow_right] = [0x1b, 0x5b, 0x43]
        @keys[:arrow_up]    = [0x1b, 0x5b, 0x41]
        @keys[:arrow_down]  = [0x1b, 0x5b, 0x42]
        @keys[:page_up]     = [0x1b, 0x5b, 0x35, 0x7e]
        @keys[:page_down]   = [0x1b, 0x5b, 0x36, 0x7e]
        @keys[:home]        = [0x1b, 0x5b, 0x31, 0x7e]
        @keys[:end]         = [0x1b, 0x5b, 0x34, 0x7e]
        @key_buffer = []

        @panes = [:playlist, :search, :artist, :album]#, :playlists, :radio, :chat, :status]
        @pane_titles = {
            :playlist => 'Currently playing',
            :search => 'Search',
            :artist => 'Artists',
            :album => 'Albums',
            :playlists => 'Playlists',
            :radio => 'Radio',
            :chat => 'Chat',
            :status => 'Status'
        }
        @current_pane = 0
        @pane_lists = {}
        @pane_sublists = {}

        @state = {}
        @state[:playlist] = []

        # init curses
        Curses.noecho()
        Curses.nonl()
        Curses.cbreak()
        Curses.stdscr.nodelay = 1
        Curses.stdscr.keypad(true)
        Curses.init_screen()
        Curses.start_color()
        (0..7).each do |y|
            (0..7).each do |x|
                Curses.init_pair(y * 8 + x, x, y)
            end
        end
        Curses.curs_set(0)

        # init window
        @win = Curses::Window.new(@height, @width, 0, 0)

        @pane_lists[:playlist] = List.new(@win, 3, 24)
        @pane_lists[:artist] = List.new(@win, 3, 29)
        @pane_lists[:album] = List.new(@win, 3, 29)
        draw_pane()
    end

    def test_key(which)
        return @keys[which] == @key_buffer[@key_buffer.size - @keys[which].size, @keys[which].size]
    end

    def s_to_h_m_s(s)
        m = s / 60
        s -= m * 60
        return sprintf('%d:%02d', m, s)
    end

    def draw_pane()
        @win.attron(color_pair(35) | A_BOLD) do
            @win.setpos(0, 0)
            @win.addstr(' ' * @width)
            @win.addstr(sprintf('%-40s', " >> #{@pane_titles[@panes[@current_pane]]} <<"))
        end
        start_x = (@current_pane * @width) / @panes.size
        end_x = ((@current_pane + 1) * @width) / @panes.size
        @win.attron(color_pair(39) | A_NORMAL) do
            @win.addstr('_' * start_x)
        end
        @win.attron(color_pair(35) | A_BOLD) do
            @win.addstr('_' * (end_x - start_x))
        end
        @win.attron(color_pair(39) | A_NORMAL) do
            @win.addstr('_' * (@width - end_x))
        end
        (@height - 3).times { @win.addstr(' ' * @width) }
        if @panes[@current_pane] == :playlist
            @win.attron(color_pair(3) | A_BOLD) do
                @win.setpos(@height - 5, 0)
                progress = 10
                @win.addstr('_' * progress)
                @win.addstr(' ' * (@width- progress))
            end
            @win.attron(color_pair(35) | A_BOLD) do
                @win.setpos(@height - 4, 0)
                @win.addstr(' ' * @width)
                unless @state[:current_song].nil?
                    @win.addstr(sprintf('%-40s', " #{@state[:current_song]['Artist']}"))
                    @win.addstr(sprintf('%-40s', " #{@state[:current_song]['Title']}"))
                else
                    @win.addstr(sprintf('%-40s', ''))
                    @win.addstr(sprintf('%-40s', ''))
                end
                @win.addstr(' ' * @width)
            end
            # draw playlist
            @pane_lists[:playlist].render()
#             @win.attron(color_pair(48) | A_NORMAL) do
#                 @win.setpos(3, 0)
#                 @win.addstr(sprintf('%-40s', ' Muse - Drones'))
#             end
#             @state[:playlist].each_with_index do |x, _|
#                 is_current_song = false
#                 unless @state[:current_song].nil?
#                     is_current_song = (@state[:current_song]['Pos'] == _)
#                 end
#                 @win.attron(color_pair(is_current_song ? 2 : 7) | (is_current_song ? A_BOLD : A_NORMAL)) do
#                     @win.setpos(_ + 4, 0)
#                     @win.addstr("#{sprintf('%2d.', _ + 1)} #{x['Title']}")
#                 end
#                 @win.attron(color_pair(is_current_song ? 2 : 7) | (is_current_song ? A_BOLD : A_NORMAL)) do
#                     @win.setpos(_ + 4, 34)
#                     @win.addstr(sprintf('%6s', s_to_h_m_s(x['Time'])))
#                 end
#             end
        end
        if @panes[@current_pane] == :artist
            @pane_lists[:artist].render()
        end
        if @panes[@current_pane] == :album
            @pane_lists[:album].render()
        end
        if @panes[@current_pane] == :chat
            @win.attron(color_pair(5) | A_BOLD) do
                @win.setpos(3, 0)
                @win.addstr('Charlotte: ')
            end
            @win.attron(color_pair(7) | A_NORMAL) do
                @win.addstr("Hallo!\n")
            end
            @win.attron(color_pair(2) | A_BOLD) do
                @win.addstr('Leo: ')
            end
            @win.attron(color_pair(7) | A_NORMAL) do
                @win.addstr("Was?!\n")
            end
            @win.attron(color_pair(39) | A_BOLD) do
                @win.setpos(@height - 1, 0)
                @win.addstr(' ' * @width)
            end
        end
        @win.refresh
        @win.setpos(@height - 1, @width - 1)
    end

    def handle_message(data)
        if data[:from_first] == 'playlistinfo'
            @state[:playlist] = data[:data]
            @pane_lists[:playlist].clear()

            artist_and_album = nil
            @state[:playlist].each_with_index do |x, _|
                new_artist_and_album = "#{x['Artist']} - #{x['Album']}"
                if new_artist_and_album != artist_and_album
                    @pane_lists[:playlist].add_separator(new_artist_and_album)
                    artist_and_album = new_artist_and_album
                end
                @pane_lists[:playlist].add_entry(x['Pos'], ["#{(_+1)}.", x['Title'], s_to_h_m_s(x['Time'])])
            end
            draw_pane() if @panes[@current_pane] == :playlist
        end
        if data[:from_first] == 'currentsong'
            if data[:data].size == 0
                @state[:current_song] = nil
                @pane_lists[:playlist].set_highlighted(nil)
            else
                @state[:current_song] = data[:data].first
                @pane_lists[:playlist].set_highlighted_by_key(@state[:current_song]['Pos'])
            end
            draw_pane() if @panes[@current_pane] == :playlist
        end
        if data[:from_full] == 'list artist'
            @state[:artists] = data[:data]
            @pane_lists[:artist].clear()
            @state[:artists].each_with_index do |x, _|
                @pane_lists[:artist].add_entry({:artist => x}, x)
            end
            draw_pane() if @panes[@current_pane] == :artist
        end
        if data[:from_full] == 'list album'
            @state[:albums] = data[:data]
            @pane_lists[:album].clear()
            @state[:albums].each_with_index do |x, _|
                @pane_lists[:album].add_entry({:album => x}, x)
            end
            draw_pane() if @panes[@current_pane] == :album
        end
        if data[:from_full].index('list album artist') == 0 ||
           data[:from_full].index('list title artist') == 0 ||
           data[:from_full].index('list artist album') == 0 ||
           data[:from_full].index('list title album') == 0
            table_key = data[:options][:source]
            @pane_lists[table_key].clear()
            @pane_sublists[table_key] ||= {}
            @pane_sublists[table_key][data[:options][:target]] = data[:data]
            [:album, :title].each do |key|
                next if @pane_sublists[table_key].nil?
                next if @pane_sublists[table_key][key].nil?
                sublist = @pane_sublists[table_key][key]
                next if sublist.empty?
                description = []
                description << data[:options][:artist] if data[:options][:artist]
                description << data[:options][:album] if data[:options][:album]
                @pane_lists[table_key].add_separator("#{key == :album ? 'Albums' : 'Songs'} (#{description.join(' / ')})")
                sublist.each_with_index do |x, _|
                    @pane_lists[table_key].add_entry({:artist => data[:options][:artist],
                                                      key => x}, x)
                end
            end
            draw_pane() if @panes[@current_pane] == table_key
        end
    end

    def main_loop
        $current_command_mutex = Mutex.new
        $current_command = []

        pipe_r, $pipe_w = IO.pipe
        mpd_socket = TCPSocket.new('127.0.0.1', 6600)
        mpd_socket.set_encoding('UTF-8')
        response = mpd_socket.gets
        # puts response

        def push_command(command, options = {})
            unless command == 'noidle'
#                 if command.index('list album artist') == 0
#                     throw command
#                 end
                $current_command_mutex.synchronize { $current_command.push({:first => command.split(' ').first, :full => command, :options => options}) }
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
        push_command('currentsong')
        push_command('list artist')
        push_command('list album')
        push_command('idle')
        while true do
            rs, ws, es = IO.select([STDIN, mpd_socket, pipe_r], [], [], 30)
            if rs.nil?
                push_command('noidle')
                push_command('@ping')
                push_command('idle')
            else
                if rs.include?(STDIN)
                    x = @win.getch
#                     print " #{x.ord}"
                    @key_buffer = [] if x.ord == 27
                    @key_buffer << x.ord
                    if test_key(:arrow_left)
                        if @current_pane > 0
                            @current_pane -= 1
                            draw_pane()
                        end
                    elsif test_key(:arrow_right)
                        if @current_pane < @panes.size - 1
                            @current_pane += 1
                            draw_pane()
                        end
                    elsif test_key(:arrow_down)
                        if @pane_lists.include?(@panes[@current_pane])
                            @pane_lists[@panes[@current_pane]].next_selected()
                            draw_pane()
                        end
                    elsif test_key(:arrow_up)
                        if @pane_lists.include?(@panes[@current_pane])
                            @pane_lists[@panes[@current_pane]].prev_selected()
                            draw_pane()
                        end
                    elsif test_key(:page_down)
                        if @pane_lists.include?(@panes[@current_pane])
                            20.times { @pane_lists[@panes[@current_pane]].next_selected() }
                            draw_pane()
                        end
                    elsif test_key(:page_up)
                        if @pane_lists.include?(@panes[@current_pane])
                            20.times { @pane_lists[@panes[@current_pane]].prev_selected() }
                            draw_pane()
                        end
                    elsif test_key(:home)
                        if @pane_lists.include?(@panes[@current_pane])
                            @pane_lists[@panes[@current_pane]].first_selected()
                            draw_pane()
                        end
                    elsif test_key(:end)
                        if @pane_lists.include?(@panes[@current_pane])
                            @pane_lists[@panes[@current_pane]].last_selected()
                            draw_pane()
                        end
                    elsif x.ord == 0x20
                        push_command('noidle')
                        push_command('pause')
                        push_command('idle')
                    elsif x.ord == 0x2e
                        push_command('noidle')
                        push_command('previous')
                        push_command('idle')
                    elsif x.ord == 0x2f
                        push_command('noidle')
                        push_command('next')
                        push_command('idle')
                    elsif x.ord == 0xd
                        if @pane_lists.include?(@panes[@current_pane]) && !(@pane_lists[@panes[@current_pane]].selected().nil?)
                            if @panes[@current_pane] == :playlist
                                push_command('noidle')
                                push_command("play #{@pane_lists[@panes[@current_pane]].selected()[:key]}")
                                push_command('idle')
                                @pane_lists[@panes[@current_pane]].set_selected(nil)
                            end
                            if @panes[@current_pane] == :artist
#                                 if @filter_artist.nil?
                                    filter_artist = @pane_lists[@panes[@current_pane]].selected()[:key][:artist]
                                    push_command('noidle')
                                    push_command("list album artist \"#{filter_artist}\"", {:source => :artist, :target => :album, :artist => filter_artist})
                                    push_command("list title artist \"#{filter_artist}\"", {:source => :artist, :target => :title, :artist => filter_artist})
                                    push_command('idle')
#                                 else
#                                 end
                            end
                            if @panes[@current_pane] == :album
#                                 if @filter_artist.nil?
                                    filter_album = @pane_lists[@panes[@current_pane]].selected()[:key][:album]
                                    push_command('noidle')
                                    push_command("list artist album \"#{filter_album}\"", {:source => :album, :target => :artist, :album => filter_album})
                                    push_command("list title album \"#{filter_album}\"", {:source => :album, :target => :title, :album => filter_album})
                                    push_command('idle')
#                                 else
#                                 end
                            end
                        end
                    end
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
                            result[:options] = from_command[:options]
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
                            if ['list'].include?(from_command[:first])
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
                                handle_message(result)
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
    end

end

player = CursesMpdPlayer.new
player.main_loop
