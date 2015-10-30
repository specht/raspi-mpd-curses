#!/usr/bin/env ruby
require 'curses'
require 'date'
require 'json'
require 'pry'
require 'set'
require 'socket'
require 'thread'
require 'yaml'
include Curses

def sfix(s)
    return s.to_s.gsub('ä', 'ae').gsub('ö', 'oe').gsub('ü', 'ue').gsub('Ä', 'Ae').gsub('Ö', 'Oe').gsub('Ü', 'Ue').gsub('ß', 'ss')
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
    def initialize(win, width, height, y0, y1)
        @win = win
        @width = width
        @height = height
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
                            s += fit(@entries[yo][:labels][1], @width - 2 - @max_widths[0] - @max_widths[2])
                            s += ' '
                            s += rfit(@entries[yo][:labels][2], @max_widths[2])
                        else
                            s += fit(@entries[yo][:labels][0], @width)
                        end
                        @win.addstr(s)
                    end
                else
                    @win.attron(color_pair(63) | A_BOLD) do
                        s = ''
                        s += fit(@entries[yo][:label], @width)
                        @win.addstr(s)
                    end
                end
            else
                @win.attron(color_pair(0) | A_NORMAL) do
                    @win.addstr(fit('', @width))
                end
            end
        end
    end
end

class CursesMpdPlayer

    class ScrollLabel
        def initialize(width)
            @label = ''
            @old_label = ''
            @start_time = Time.now.to_f
            @width = width
            @scroll_wait = 5
            @scroll_pause_end = 2
            @scroll_pause_begin = 5
            @scroll_speed = 10
        end

        def set_label(label)
            fixed_label = sfix(label)
            return if fixed_label == @label
            @old_label_screenshot = scroll_string(@label, @width, @start_time)
            @old_label_screenshot[@width - 1] = ' '
            @old_label_screenshot[@width - 2] = ' '
            @old_label = @label
            @label = fixed_label
            @start_time = Time.now.to_f
        end

        def scroll_string(s, length, t)
            now = Time.now.to_f
            dt = now - t - @scroll_wait
            if dt < 0
                wipe_in_time = 0.5
                negative_shift = ((wipe_in_time - (now - t)) * length / wipe_in_time).to_i
                negative_shift = 0 if negative_shift < 0
                result = ' ' * negative_shift + s
                if @old_label_screenshot
                    result = @old_label_screenshot[@old_label_screenshot.size - negative_shift, negative_shift] + s
                end
                return fit(result, length)
            end
            if s.size > length
                if dt > 0
                    extra = s.size - length
                    shift = (dt * @scroll_speed).to_i % (extra * 2 + (@scroll_pause_begin + @scroll_pause_end) * @scroll_speed)
                    shift = extra - (shift - extra - @scroll_pause_end * @scroll_speed) if shift > extra + @scroll_pause_end * @scroll_speed
                    shift = s.size - length if shift > s.size - length
                    shift = 0 if shift < 0
                    return fit(s[shift, s.size], length)
                end
            end
            return fit(s, length)
        end

        def render(win, y, x)
            win.setpos(y, x)
            win.addstr(scroll_string(@label, @width, @start_time))
        end
    end

    def initialize()
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

        @panes = [:playlist, :search, :artist, :album, :playlists, :radio, :chat, :status]
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
        @state[:status] = nil
        @state[:stats] = nil

        # init curses
        Curses.noecho()
        Curses.nonl()
        Curses.cbreak()
        Curses.stdscr.nodelay = 1
        Curses.stdscr.keypad(true)
        Curses.init_screen()
        Curses.start_color()
        @width = Curses.cols
        @height = Curses.lines
        @width = 20 if @width < 20
#         @height = 20 if @height < 20

        (0..7).each do |y|
            (0..7).each do |x|
                Curses.init_pair(y * 8 + x, x, y)
            end
        end
        Curses.curs_set(0)

        # init window
        @win = Curses::Window.new(@height, @width, 0, 0)
        
        @spinner = '/-\\|'
        @spinner_index = 0
        @last_play_start_time = nil
        @last_play_start_elapsed = nil

        @pane_lists[:playlist] = List.new(@win, @width, @height, 3, @height - 7)
        @pane_lists[:artist] = List.new(@win, @width, @height, 3, @height - 1)
        @pane_lists[:album] = List.new(@win, @width, @height, 3, @height - 1)

        @artist_label = ScrollLabel.new(@width - 8)
        @title_label = ScrollLabel.new(@width - 8)

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
            @win.addstr(fit(" >> #{@pane_titles[@panes[@current_pane]]} <<", @width - 7))
            @win.addstr(" #{DateTime.now.strftime('%H:%M')} ")
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
            # draw playlist
            @pane_lists[:playlist].render()
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
        draw_spinner()
        @win.refresh
        @win.setpos(@height - 1, @width - 1)
    end

    def handle_message(data)
        if data[:from_first] == 'status'
            @state[:status] = data[:data]
            if @state[:status]['state'] == 'play'
                @last_play_start_time = Time.now.to_f
                @last_play_start_elapsed = @state[:status]['elapsed']
            else
                @last_play_start_time = Time.now.to_f
                @last_play_start_elapsed = @state[:status]['elapsed']
            end
            draw_spinner()
        end
        if data[:from_first] == 'stats'
            @state[:stats] = data[:data]
        end
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
                @artist_label.set_label(@state[:current_song]['Artist'])
                @title_label.set_label(@state[:current_song]['Title'])
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

    def draw_spinner()
        return if @current_pane != 0
        t = 0
        if @state[:status] && @last_play_start_elapsed
            t = @last_play_start_elapsed
            t += Time.now.to_f - @last_play_start_time if @state[:status]['state'] == 'play'
        end

        @win.attron(color_pair(35) | A_BOLD) do
            @win.setpos(@height - 5, 0)
            @win.addstr(' ' * @width)
        end
#         @win.attron(color_pair(56) | A_NORMAL) do
#             @win.addstr(' ' * @width)
#         end
        @win.attron(color_pair(38) | A_BOLD) do
            unless @state[:current_song].nil?
                @win.setpos(@height - 4, 0)
                @win.addstr(' ')
                @artist_label.render(@win, @height - 4, 1)
                @win.setpos(@height - 3, 0)
                @win.addstr(' ')
                @title_label.render(@win, @height - 3, 1)
            else
                @win.setpos(@height - 4, 0)
                @win.addstr(' ')
                @win.addstr(fit('', @width - 8))
                @win.setpos(@height - 3, 0)
                @win.addstr(' ')
                @win.addstr(fit('', @width - 8))
            end
        end

        @spinner_index = (Time.now.to_f * 5.0).to_i
        @spinner_index %= @spinner.size
        @win.attron(color_pair(39) | A_BOLD) do
            @win.setpos(@height - 4, @width - 7)
            c = @spinner[@spinner_index, 1]
            c = ' ' if @state[:status] && @state[:status]['state'] != 'play'
            @win.addstr("   [#{c}] ")
            if @state[:status]
                @win.setpos(@height - 3, @width - 7)
                @win.addstr(rfit(s_to_h_m_s(t.to_i) + ' ', 7))
            end
        end
        @win.setpos(@height - 6, 0)
        progress = 0
        if @state[:current_song]
            progress = (t * @width / @state[:current_song]['Time']).to_i
            progress = @width if progress > @width
        end
        @win.attron(color_pair(6) | A_BOLD) do
            @win.addstr('_' * progress)
        end
        @win.attron(color_pair(6) | A_NORMAL) do
            @win.addstr('_' * (@width - progress))
        end
        @win.attron(color_pair(32) | A_NORMAL) do
            @win.setpos(@height - 2, 0)
            @win.addstr(' ' * @width)
        end
        if @state[:status]
            x = 0
            attr = (color_pair(56) | A_BOLD)
            attr = (color_pair(63) | A_BOLD) if @state[:status]['repeat'] == 1
            @win.setpos(@height - 1, 0)
            @win.attron(attr) do
                @win.addstr(' ')
                s = (@state[:status]['single'] == 1) ? 'Repeat one' : 'Repeat'
                @win.addstr(s)
                x += s.size + 1
            end
            attr = (color_pair(56) | A_BOLD)
            @win.attron(attr) do
                @win.addstr(' | ')
                x += 3
            end
            attr = (color_pair(63) | A_BOLD) if @state[:status]['random'] == 1
            @win.attron(attr) do
                s = 'Shuffle    '
                @win.addstr(s)
                x += s.size
                @win.addstr(' ' * (@width - x))
            end
        end
        @win.attron(color_pair(35) | A_BOLD) do
            @win.setpos(1, @width - 6)
            @win.addstr(DateTime.now.strftime('%H:%M'))
        end
        @win.setpos(@height - 1, @width - 1)
        @win.refresh
    end

    def main_loop
        $current_command_mutex = Mutex.new
        $current_command = []

        # command pipe
        @pipe_r, @pipe_w = IO.pipe
        # refresh pipe
        @rpipe_r, @rpipe_w = IO.pipe
        mpd_socket = TCPSocket.new('127.0.0.1', 6600)
        mpd_socket.set_encoding('UTF-8')
        response = mpd_socket.gets
        # puts response

        def push_command(command, options = {})
            unless command == 'noidle'
                $current_command_mutex.synchronize { $current_command.push({:first => command.split(' ').first, :full => command, :options => options}) }
            end
            @pipe_w.puts command
        end

        Thread.new do
            while true do
                @rpipe_w.puts '.'
                sleep 0.1
            end
        end

        response = ''

        def promote(x)
            return x.to_i if x =~ /^\d+$/
            return x.to_f if x =~ /^\d+\.\d+$/
            return x.split(':').map { |x| x.to_i } if x =~ /^((\d+):?)+$/
            return x
        end

        push_command('noidle')
        push_command('status')
        push_command('playlistinfo')
        push_command('currentsong')
        push_command('list artist')
        push_command('list album')
        push_command('idle')
        while true do
            rs, ws, es = IO.select([STDIN, mpd_socket, @pipe_r, @rpipe_r], [], [], 30)
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
                    elsif x == 's' || x == 'S'
                        if @state[:status]
                            push_command('noidle')
                            push_command("random #{1 - @state[:status]['random']}")
                            push_command('idle')
                        end
                    elsif x == 'r' || x == 'R'
# //             // SR
# //             // 00 0
# //             // 01 1
# //             // 10 2
# //             // 11 3
# //             var current_code = (~~(state.repeat)) + ((~~(state.single)) << 1);
# //             current_code += 1;
# //             if (current_code === 2)
# //                 current_code = 3;
# //             if (current_code > 3)
# //                 current_code = 0;
# //             state.repeat = (current_code & 1) !== 0;
# //             state.single = (current_code & 2) !== 0;
                        if @state[:status]
                            current_code = (~~(@state[:status]['repeat'])) + ((~~(@state[:status]['single'])) << 1);
                            current_code += 1;
                            current_code = 3 if current_code == 2
                            current_code = 0 if current_code > 3
                            push_command('noidle')
                            push_command("repeat #{(current_code) & 1}")
                            push_command("single #{(current_code >> 1) & 1}")
                            push_command('idle')
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
                if rs.include?(@pipe_r)
                    message = @pipe_r.gets
        #             puts "> #{message}"
                    mpd_socket.puts(message.sub(/^@/, ''))
                end
                if rs.include?(@rpipe_r)
                    s = @rpipe_r.gets
                    draw_spinner()
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
                                        push_command('currentsong')
                                    end
                                    if what == 'player'
                                        push_command('status')
                                        push_command('currentsong')
                                    end
                                    if what == 'options'
                                        push_command('status')
                                    end
#                                     puts what
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

STDERR.puts "Ahoy!"
player = CursesMpdPlayer.new
player.main_loop
