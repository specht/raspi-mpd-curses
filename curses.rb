#!/usr/bin/env ruby

require 'curses'
require 'date'
require 'json'
require './libdevinput.rb'
require 'openssl'
# require 'pry'
require 'set'
require 'socket'
require 'thread'
require 'uri'
require 'yaml'
include Curses

# dev = DevInput.new "/dev/input/event0"
# # grab keyboard
# dev.dev.ioctl(1074021776, 1)
# dev.each do |event|
#     next unless event.type == 1
#     if [:press, :repeat].include?(event.value_sym)
#         puts "got event #{event.code_sym}"
#     end
# end
#
# exit(1)

# Berlin Steglitz-Zehlendorf: 7290245
# API key: 956465b12517b778dc896eacbc4c9593
OPENWEATHERMAP_API_KEY = '956465b12517b778dc896eacbc4c9593'

def sfix(s)
    return s.to_s.
        gsub('ä', 'ae').gsub('ö', 'oe').gsub('ü', 'ue').gsub('Ä', 'Ae').
        gsub('Ö', 'Oe').gsub('Ü', 'Ue').gsub('ß', 'ss').gsub('’', '\'').
        gsub('Ã', 'ss').
        gsub('á', 'a').gsub('à', 'a').gsub('â', 'a').gsub('Á', 'A').gsub('À', 'A').gsub('Â', 'A').
        gsub('é', 'e').gsub('è', 'e').gsub('ê', 'e').gsub('É', 'E').gsub('È', 'E').gsub('Ê', 'E').
        gsub('í', 'i').gsub('ì', 'i').gsub('î', 'i').gsub('Í', 'I').gsub('Ì', 'I').gsub('Î', 'I').
        gsub('ó', 'o').gsub('ò', 'o').gsub('ô', 'o').gsub('Ó', 'O').gsub('Ò', 'O').gsub('Ô', 'O').
        gsub('ú', 'p').gsub('ù', 'u').gsub('û', 'u').gsub('Ú', 'U').gsub('Ù', 'U').gsub('Û', 'U').
        gsub('„', '"').gsub('“', '"')
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

    def add_colon()
        @add_colon = true
    end

    def stay_on_top_of_list()
        @stay_on_top_of_list = true
    end

    def keep_all()
        @keep_all = true
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
        while true
            set_selected(@selected_entry + 1)
            break if @selected_entry.nil?
            break if @entries[@selected_entry].nil?
            break if [:entry, :chat_entry].include?(@entries[@selected_entry][:type])
        end
    end

    def prev_selected()
        return if @first_selectable_entry.nil?
        @selected_entry = @highlighted_entry if @selected_entry.nil?
        @selected_entry ||= 0
        while true
            set_selected(@selected_entry - 1)
            break if @selected_entry.nil?
            break if @entries[@selected_entry].nil?
            break if [:entry, :chat_entry].include?(@entries[@selected_entry][:type])
        end
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
            x ||= ''
            if @max_widths.size <= _
                @max_widths << 1
            end
            if x.size > @max_widths[_]
                @max_widths[_] = x.size
            end
        end
    end

    def wordwrap(s, length)
        @wordwrap_regex ||= Regexp.new('.{1,' + length.to_s + '}(?:\s|\Z)')
        s.gsub(/\t/,"     ").gsub(@wordwrap_regex){($& + 5.chr).gsub(/\n\005/,"\n").gsub(/\005/,"\n")}
    end

    def add_chat_entry(entry)
        if @stay_on_top_of_list
            return if @entries.size >= @yh
        end
        entry['name'] = sfix(entry['name'])
        entry['message'] = sfix(entry['message'])
        @first_selectable_entry ||= @entries.size
        @last_selectable_entry = @entries.size
        print_name = true
        if (!@entries.empty?) && @entries.last[:entry] && (@entries.last[:entry]['name'] == entry['name'])
            print_name = false
        end
        complete_line = ''
        if print_name
            complete_line += entry['name']
            complete_line += ':' if @add_colon
            complete_line += ' '
        end
        complete_line += entry['message']
        lines = wordwrap(complete_line, @width).split("\n")
        lines.each_with_index do |line, _|
            new_entry = {:type => :chat_entry, :entry => entry, :line => line}
            new_entry[:highlight] = entry['name'].size + 1 if print_name && _ == 0
            @entries << new_entry
        end
        unless @keep_all
            while @entries.size > @yh
                @entries.shift
            end
        end
        if @stay_on_top_of_list
            first_selected()
        else
            last_selected()
        end
    end

    def render()
        (@y0..@y1).each do |y|
            @win.setpos(y, 0)
            yo = y - @y0 + @scroll_offset
            if yo >= 0 && yo < @entries.size
                entry = @entries[yo]
                if entry[:type] == :entry
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
                        if entry[:labels].size == 3
                            s += rfit(entry[:labels][0], @max_widths[0])
                            s += ' '
                            s += fit(entry[:labels][1], @width - 2 - @max_widths[0] - @max_widths[2])
                            s += ' '
                            s += rfit(entry[:labels][2], @max_widths[2])
                        else
                            s += fit(entry[:labels][0], @width)
                        end
                        @win.addstr(s)
                    end
                elsif entry[:type] == :chat_entry
                    s = fit(entry[:line], @width)
                    cut = 0
                    if entry[:highlight]
                        @win.attron(color_pair(entry[:entry]['color'] || 7) | A_BOLD) do
                            @win.addstr(s[0, entry[:highlight]])
                            cut = entry[:highlight]
                        end
                    end
                    @win.attron(color_pair(6) | A_NORMAL) do
                        s = fit(entry[:line][cut, entry[:line].size - cut], @width - cut)
                        @win.addstr(s)
                    end
                else
                    @win.attron(color_pair(63) | A_BOLD) do
                        s = ''
                        s += fit(entry[:label], @width)
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

class EditField
    def initialize(win, width, height)
        @win = win
        @max_length = 256
        @width = width
        @height = height
        @string = ''
    end

    attr_reader :string

    def add_char(c)
        return if @string.size > @max_length
        @string += c
    end

    def backspace()
        return if @string.empty?
        @string = @string[0, @string.size - 1]
    end

    def clear()
        @string = ''
    end

    def render()
        @win.attron(color_pair(39) | A_BOLD) do
            @win.setpos(@height - 1, 0)
            @win.addstr(' > ')
            remaining_width = @width - 4
            offset = 0
            if @string.size > remaining_width
                offset = @string.size - remaining_width
            end
            @win.addstr(fit(@string[offset, remaining_width], @width - 3))
            @win.setpos(@height - 1, @string.size + 3)
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
        @keys[:delete]      = [0x1b, 0x5b, 0x33, 0x7e]
        @keys[:ae]          = [0xc3, 0xa4]
        @keys[:oe]          = [0xc3, 0xb6]
        @keys[:ue]          = [0xc3, 0xbc]
        @keys[:AE]          = [0xc3, 0x84]
        @keys[:OE]          = [0xc3, 0x96]
        @keys[:UE]          = [0xc3, 0x9c]
        @keys[:sz]          = [0xc3, 0x9f]

        @keys_char = {}
        @keys_char[:ae]     = 'ä'
        @keys_char[:oe]     = 'ö'
        @keys_char[:ue]     = 'ü'
        @keys_char[:AE]     = 'Ä'
        @keys_char[:OE]     = 'Ö'
        @keys_char[:UE]     = 'Ü'
        @keys_char[:sz]     = 'ß'

        @panes = [:playlist, :search, :artist, :album, :playlists, :radio, :chat, :wikipedia, :weather, :status]
        @pane_titles = {
            :playlist => 'Currently playing',
            :search => 'Search',
            :artist => 'Artists',
            :album => 'Albums',
            :playlists => 'Playlists',
            :radio => 'Radio',
            :chat => 'Chat',
            :wikipedia => 'Wikipedia',
            :weather => 'Weather',
            :status => 'Status'
        }
        @current_pane = 0
        @pane_lists = {}
        @pane_sublists = {}
        @pane_editfields = {}

        @state = {}
        @state[:playlist] = []
        @state[:status] = nil
        @state[:stats] = nil

        # init curses
        Curses.init_screen()
        Curses.noecho()
#         Curses.nonl()
        Curses.cbreak()
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
        @win.nodelay = 1
        @win.keypad = true

        @spinner = '/-\\|'
        @spinner_index = 0
        @last_play_start_time = nil
        @last_play_start_elapsed = nil

        @pane_lists[:playlist] = List.new(@win, @width, @height, 3, @height - 7)
        @pane_lists[:search] = List.new(@win, @width, @height, 3, @height - 2)
        @pane_lists[:artist] = List.new(@win, @width, @height, 3, @height - 2)
        @pane_lists[:album] = List.new(@win, @width, @height, 3, @height - 2)
        @pane_lists[:playlists] = List.new(@win, @width, @height, 3, @height - 2)
        @pane_lists[:radio] = List.new(@win, @width, @height, 3, @height - 2)
        @pane_lists[:radio].add_entry({:file => 'http://kiraka.akacast.akamaistream.net/7/285/119443/v1/gnl.akacast.akamaistream.net/kiraka'}, 'KiRaKa')
        @pane_lists[:radio].add_entry({:file => 'http://rbb-mp3-radioeins-m.akacast.akamaistream.net/7/854/292097/v1/gnl.akacast.akamaistream.net/rbb_mp3_radioeins_m'}, 'radio eins')
        @pane_lists[:radio].add_entry({:file => 'http://rbb-mp3-fritz-m.akacast.akamaistream.net/7/799/292093/v1/gnl.akacast.akamaistream.net/rbb_mp3_fritz_m'}, 'Radio Fritz')
        @pane_lists[:chat] = List.new(@win, @width, @height, 3, @height - 2)
        @pane_lists[:chat].add_colon()
        @pane_lists[:wikipedia] = List.new(@win, @width, @height, 3, @height - 2)
        @pane_lists[:wikipedia].keep_all()
        @pane_lists[:weather] = List.new(@win, @width, @height, 3, @height - 2)
        @pane_lists[:weather].stay_on_top_of_list()
        @pane_editfields[:search] = EditField.new(@win, @width, @height)
        @pane_editfields[:chat] = EditField.new(@win, @width, @height)
        @pane_editfields[:wikipedia] = EditField.new(@win, @width, @height)
        @pane_editfields[:weather] = EditField.new(@win, @width, @height)

        @artist_label = ScrollLabel.new(@width - 8)
        @title_label = ScrollLabel.new(@width - 8)

        draw_pane()
    end

    def s_to_h_m_s(s)
        s ||= 0
        m = s / 60
        s -= m * 60
        return sprintf('%d:%02d', m, s)
    end

    def draw_pane()
        @win.attron(color_pair(35) | A_BOLD) do
            @win.setpos(0, 0)
            @win.addstr(' ' * @width)
            title = @pane_titles[@panes[@current_pane]]
            @win.addstr(fit(" [##{@current_pane + 1}]#{' ' * (((((@width - 7 - 6) / 2) - title.size / 2) - 2).to_i)}>> #{title} <<", @width - 7))
            @win.addstr(" #{DateTime.now.strftime('%H:%M')} ")
        end
        start_x = (@current_pane * @width) / @panes.size
        end_x = ((@current_pane + 1) * @width) / @panes.size
        @win.attron(color_pair(38) | A_NORMAL) do
            @win.addstr('_' * start_x)
        end
        @win.attron(color_pair(35) | A_BOLD) do
            @win.addstr('_' * (end_x - start_x))
        end
        @win.attron(color_pair(38) | A_NORMAL) do
            @win.addstr('_' * (@width - end_x))
        end
        (@height - 3).times { @win.addstr(' ' * @width) }
        @pane_lists[@panes[@current_pane]].render() if @pane_lists[@panes[@current_pane]]
        if @panes[@current_pane] == :artist || @panes[@current_pane] == :album ||
           @panes[@current_pane] == :playlists || @panes[@current_pane] == :radio
            @win.attron(color_pair(9) | A_BOLD) do
                @win.setpos(@height - 1, 0)
                @win.addstr(fit(' Play | Append', @width))
            end
            @win.attron(color_pair(15) | A_BOLD) do
                @win.setpos(@height - 1, 1)
                @win.addstr('P')
                @win.setpos(@height - 1, 8)
                @win.addstr('A')
            end
        end
        draw_spinner()
        if @pane_editfields[@panes[@current_pane]]
            @pane_editfields[@panes[@current_pane]].render()
            Curses.curs_set(1)
        else
            Curses.curs_set(0)
            @win.setpos(@height - 1, @width - 1)
        end
        @win.refresh
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
                artist = x['AlbumArtist']
                artist ||= x['Artist']
                artist ||= x['Name']
                album = x['Album']
                l = []
                l << artist if artist
                l << album if album
                new_artist_and_album = l.join(' - ').strip
                if new_artist_and_album != artist_and_album
                    artist_and_album = new_artist_and_album
                    unless artist_and_album.empty?
                        @pane_lists[:playlist].add_separator(new_artist_and_album)
                    end
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
                @artist_label.set_label(@state[:current_song]['Artist'] || @state[:current_song]['Name'])
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
        if data[:from_full] == 'listplaylists'
            @pane_lists[:playlists].clear()
            data[:data].sort.each_with_index do |x, _|
                @pane_lists[:playlists].add_entry({:playlist => x}, x)
            end
            draw_pane() if @panes[@current_pane] == :playlists
        end
        if data[:from_full].index('list album artist') == 0 ||
           data[:from_full].index('list title artist') == 0 ||
           data[:from_full].index('list artist album') == 0 ||
           data[:from_full].index('list title album') == 0 ||
           data[:from_first] == 'search'
            table_key = data[:options][:source]
            @pane_lists[table_key].clear()
            @pane_sublists[table_key] ||= {}
            @pane_sublists[table_key][data[:options][:target]] = data[:data]
            key_label = {:artist => 'Artists', :album => 'Albums', :title => 'Songs'}
            [:artist, :album, :title].each do |key|
                next if @pane_sublists[table_key].nil?
                next if @pane_sublists[table_key][key].nil?
                sublist = @pane_sublists[table_key][key]
                next if sublist.empty?
                description = []
                description << data[:options][:artist] if data[:options][:artist]
                description << data[:options][:album] if data[:options][:album]
                description << data[:options][:title] if data[:options][:title]
                description << data[:options][:any] if data[:options][:any]
                @pane_lists[table_key].add_separator("#{key_label[key]} (#{description.join(' / ')})")
                sublist.each_with_index do |x, _|
                    @pane_lists[table_key].add_entry({:artist => data[:options][:artist],
                                                    key => x}, x)
                end
            end
            draw_pane() if @panes[@current_pane] == table_key
        end
        if ['find', 'listplaylist'].include?(data[:from_first])
            if data[:options][:command]
                if [:play, :append].include?(data[:options][:command])
                    push_command_no_lock('noidle')
                    if data[:options][:command] == :play
                        push_command_no_lock('clear')
                    end
                    data[:data].each do |item|
                        push_command_no_lock("add \"#{item['file']}\"")
                    end
                    push_command_no_lock('play')
                    push_command_no_lock('idle')
                end
            end
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
            progress = (t * @width / (@state[:current_song]['Time'] || 1)).to_i
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
            attr = (color_pair(9) | A_BOLD)
            @win.setpos(@height - 1, 0)
            @win.attron(attr) do
                @win.addstr(' ')
            end
            attr = (color_pair(9) | A_BOLD)
            attr = (color_pair(15) | A_BOLD) if @state[:status]['repeat'] == 1
            @win.attron(attr) do
                s = (@state[:status]['single'] == 1) ? 'Repeat one' : 'Repeat'
                @win.addstr(s)
                x += s.size + 1
            end
            attr = (color_pair(9) | A_BOLD)
            @win.attron(attr) do
                @win.addstr(' | ')
                x += 3
            end
            attr = (color_pair(9) | A_BOLD)
            attr = (color_pair(15) | A_BOLD) if @state[:status]['random'] == 1
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

    def handle_weather_update()
        if @weather_socket.eof?
            @weather_socket.close
            @weather_socket = nil
        else
            response = @weather_socket.read()
            chunky_bacon = response.split("\r\n\r\n")[1]
            data = JSON.parse(chunky_bacon)
            @pane_lists[:weather].clear()
            if data['list']
                @pane_lists[:weather].add_separator("#{data['city']['name']} (#{data['city']['country']})")
                day = nil
                data['list'].each do |entry|
                    new_day = Time.at(entry['dt']).strftime('%a, %d %b %Y')
                    if new_day != day
                        @pane_lists[:weather].add_separator(new_day)
                        day = new_day
                    end
                    message = ''
                    message += "#{sprintf('%2d', entry['main']['temp'] - 273.15)} C, "
                    message += entry['weather'].map { |x| x['description'] }.join(', ')
                    @pane_lists[:weather].add_chat_entry({'name' => Time.at(entry['dt']).strftime('%H:%M'), 'color': 7, 'message' => message})
                end
            else
                @pane_lists[:weather].add_chat_entry({'name' => 'Error:', 'color': 7, 'message' => 'no data received'})
            end
            if @panes[@current_pane] == :weather
                draw_pane()
            end
        end
    end

    def handle_wikipedia_update()
        if @wikipedia_socket.eof?
            @wikipedia_socket.close
            @wikipedia_socket = nil
        else
            response = @wikipedia_socket.read()
            chunky_bacon = response.split("\r\n\r\n")[1]
            begin
#                 STDERR.puts response
                data = JSON.parse(chunky_bacon)
                @pane_lists[:wikipedia].clear()
                data['query']['pages'].values.each do |page|
                    @pane_lists[:wikipedia].add_separator(page['title'])
                    @pane_lists[:wikipedia].add_chat_entry({'name' => '', 'message' => page['extract']})
                end
                @pane_lists[:wikipedia].first_selected()
            rescue
                @pane_lists[:wikipedia].clear()
                @pane_lists[:wikipedia].add_chat_entry({'name' => 'Error:', 'color': 7, 'message' => 'no data received'})
            end
            if @panes[@current_pane] == :wikipedia
                draw_pane()
            end
        end
    end

    def main_loop()
        $current_command_mutex = Mutex.new
        $current_command = []

        # command pipe
        @pipe_r, @pipe_w = IO.pipe
        # refresh pipe
        @rpipe_r, @rpipe_w = IO.pipe
        mpd_socket = TCPSocket.new('127.0.0.1', 6600)
        mpd_socket.set_encoding('UTF-8')
        response = mpd_socket.gets

        @weather_socket = nil
        @weather_socket = TCPSocket.new('api.openweathermap.org', 80)
        @weather_socket.set_encoding('UTF-8')
        url = "/data/2.5/forecast?id=7290245&appid=#{OPENWEATHERMAP_API_KEY}"
        @weather_socket.print "GET #{url} HTTP/1.0\r\n\r\n"

        @wikipedia_socket = nil

        chat_socket = TCPSocket.new('192.168.106.42', 3000)
        chat_socket.set_encoding('UTF-8')
        chat_name = 'Anon'
        chat_color = 7
        begin
            info = YAML::load_file('config.yaml')
            chat_name = info['name']
            chat_color = info['color']
        rescue
        end
        chat_socket.puts({:name => chat_name, :color => chat_color}.to_json)
        chat_socket.puts('@@context')

        # puts response

        def push_command(command, options = {})
            unless command == 'noidle'
                $current_command_mutex.synchronize { $current_command.push({:first => command.split(' ').first, :full => command, :options => options}) }
            end
            @pipe_w.puts command
        end

        def push_command_no_lock(command, options = {})
            unless command == 'noidle'
                $current_command.push({:first => command.split(' ').first, :full => command, :options => options})
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
        push_command('listplaylists')
        push_command('list artist')
        push_command('list album')
        push_command('idle')

        @keyboard = DevInput.new "/dev/input/event0"
        # grab keyboard
        @keyboard.dev.ioctl(1074021776, 1)

        while true do
            fds = [@keyboard.dev, mpd_socket, chat_socket, @pipe_r, @rpipe_r]
            fds << @weather_socket if @weather_socket
            fds << @wikipedia_socket if @wikipedia_socket
#             STDERR.puts "#{Time.now} IO.select(#{fds.size})"
            rs, ws, es = IO.select(fds, [], [], 30)
            if rs.nil?
                push_command('noidle')
                push_command('@ping')
                push_command('idle')
            else
                if rs.include?(@keyboard.dev)
                    event = @keyboard.handle
                    if event
                        key = event[:event].code_sym
                        modifiers = event[:modifiers]
                        char = event[:char]
                        if key == :backspace && modifiers[:leftcontrol] && modifiers[:leftalt]
                            break
                        end

                        if key == :f1
                            @current_pane = 0
                            draw_pane()
                        elsif key == :f2
                            @current_pane = 1
                            draw_pane()
                        elsif key == :f3
                            @current_pane = 2
                            draw_pane()
                        elsif key == :f4
                            @current_pane = 3
                            draw_pane()
                        elsif key == :f5
                            @current_pane = 4
                            draw_pane()
                        elsif key == :f6
                            @current_pane = 5
                            draw_pane()
                        elsif key == :f7
                            @current_pane = 6
                            draw_pane()
                        elsif key == :f8
                            @current_pane = 7
                            draw_pane()
                        elsif key == :f9
                            @current_pane = 8
                            draw_pane()
                        elsif key == :f10
                            @current_pane = 9
                            draw_pane()
                        elsif key == :left
                            if @current_pane > 0
                                @current_pane -= 1
                                draw_pane()
                            end
                        elsif key == :right
                            if @current_pane < @panes.size - 1
                                @current_pane += 1
                                draw_pane()
                            end
                        elsif key == :down
                            if @pane_lists.include?(@panes[@current_pane])
                                @pane_lists[@panes[@current_pane]].next_selected()
                                draw_pane()
                            end
                        elsif key == :up
                            if @pane_lists.include?(@panes[@current_pane])
                                @pane_lists[@panes[@current_pane]].prev_selected()
                                draw_pane()
                            end
                        elsif key == :pagedown
                            if @pane_lists.include?(@panes[@current_pane])
                                20.times { @pane_lists[@panes[@current_pane]].next_selected() }
                                draw_pane()
                            end
                        elsif key == :pageup
                            if @pane_lists.include?(@panes[@current_pane])
                                20.times { @pane_lists[@panes[@current_pane]].prev_selected() }
                                draw_pane()
                            end
                        elsif key == :home
                            if @pane_lists.include?(@panes[@current_pane])
                                @pane_lists[@panes[@current_pane]].first_selected()
                                draw_pane()
                            end
                        elsif key == :end
                            if @pane_lists.include?(@panes[@current_pane])
                                @pane_lists[@panes[@current_pane]].last_selected()
                                draw_pane()
                            end
                        elsif key == :delete
                            if @panes[@current_pane] == :playlist && !@pane_lists[@panes[@current_pane]].selected().nil?
                                push_command('noidle')
                                push_command("delete #{@pane_lists[@panes[@current_pane]].selected()[:key]}")
                                push_command('idle')
                            end
                        elsif key == :esc
                            # escape pressed!
                            if @pane_lists[@panes[@current_pane]].nil? || @pane_lists[@panes[@current_pane]].selected().nil?
                                @current_pane = 0
                                draw_pane()
                            else
                                @pane_lists[@panes[@current_pane]].set_selected(nil)
                                draw_pane()
                            end
                        end
                        found_special_char = false
    #                     [:ae, :oe, :ue, :AE, :OE, :UE, :sz].each do |_|
    #                         if test_key(_)
    #                             x = @keys_char[_]
    #                             found_special_char = true
    #                             break
    #                         end
    #                     end
                        if @pane_editfields[@panes[@current_pane]]
                            # this pane has an edit field
                            if char
                                new_char = sfix(char)
                                sfix(new_char).each_char do |c|
                                    @pane_editfields[@panes[@current_pane]].add_char(c)
                                end
                                draw_pane()
                            elsif key == :backspace
                                @pane_editfields[@panes[@current_pane]].backspace()
                                draw_pane()
                            elsif key == :enter
                                input = @pane_editfields[@panes[@current_pane]].string
                                @pane_editfields[@panes[@current_pane]].clear()
                                if @panes[@current_pane] == :search
                                    push_command('noidle')
                                    push_command("search any \"#{input}\"", {:source => :search, :any => input})
                                    push_command('idle')
                                    draw_pane()
                                elsif @panes[@current_pane] == :chat
                                    chat_socket.puts input
                                    draw_pane()
                                elsif @panes[@current_pane] == :weather
                                    if @weather_socket
                                        @weather_socket.close
                                        @weather_socket = nil
                                    end
                                    @weather_socket = TCPSocket.new('api.openweathermap.org', 80)
                                    @weather_socket.set_encoding('UTF-8')
                                    url = "/data/2.5/forecast?q=#{URI::escape(input.strip)}&appid=#{OPENWEATHERMAP_API_KEY}"
                                    @weather_socket.print "GET #{url} HTTP/1.0\r\n\r\n"
                                elsif @panes[@current_pane] == :wikipedia
                                    if @wikipedia_socket
                                        @wikipedia_socket.close
                                        @wikipedia_socket = nil
                                    end

                                    sock = TCPSocket.new('de.wikipedia.org', 443)
                                    ctx = OpenSSL::SSL::SSLContext.new
                                    ctx.set_params(verify_mode: OpenSSL::SSL::VERIFY_PEER)
                                    @wikipedia_socket = OpenSSL::SSL::SSLSocket.new(sock, ctx).tap do |socket|
                                        socket.sync_close = true
                                        socket.connect
                                    end
#                                     @wikipedia_socket.set_encoding('UTF-8')
                                    url = "/w/api.php?format=json&action=query&prop=extracts&exintro=&explaintext=&titles=#{URI::escape(input.strip)}"
                                    @wikipedia_socket.print "GET #{url} HTTP/1.0\r\nHost: de.wikipedia.org\r\n\r\n"
                                end
                            end
                        else
                            # this pane has no edit field, we can use shortcuts here
                            if key == :s
                                if @state[:status]
                                    push_command('noidle')
                                    push_command("random #{1 - @state[:status]['random']}")
                                    push_command('idle')
                                end
                            elsif key == :r
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
                            elsif key == :space
                                push_command('noidle')
                                push_command('pause')
                                push_command('idle')
                            elsif key == :dot
                                push_command('noidle')
                                push_command('previous')
                                push_command('idle')
                                @pane_lists[:playlist].set_selected(nil)
                            elsif key == :slash
                                push_command('noidle')
                                push_command('next')
                                push_command('idle')
                                @pane_lists[:playlist].set_selected(nil)
                            elsif key == :enter
                                if @pane_lists.include?(@panes[@current_pane]) && !(@pane_lists[@panes[@current_pane]].selected().nil?)
                                    if @panes[@current_pane] == :playlist
                                        push_command('noidle')
                                        push_command("play #{@pane_lists[@panes[@current_pane]].selected()[:key]}")
                                        push_command('idle')
                                        @pane_lists[@panes[@current_pane]].set_selected(nil)
                                    end
                                    if @panes[@current_pane] == :artist
                                        filter_artist = @pane_lists[@panes[@current_pane]].selected()[:key][:artist]
                                        push_command('noidle')
                                        push_command("list album artist \"#{filter_artist}\"", {:source => :artist, :target => :album, :artist => filter_artist})
                                        push_command("list title artist \"#{filter_artist}\"", {:source => :artist, :target => :title, :artist => filter_artist})
                                        push_command('idle')
                                    end
                                    if @panes[@current_pane] == :album
                                        filter_album = @pane_lists[@panes[@current_pane]].selected()[:key][:album]
                                        push_command('noidle')
                                        push_command("list artist album \"#{filter_album}\"", {:source => :album, :target => :artist, :album => filter_album})
                                        push_command("list title album \"#{filter_album}\"", {:source => :album, :target => :title, :album => filter_album})
                                        push_command('idle')
                                    end
                                end
                            elsif key == :p || key == :a
                                if @pane_lists.include?(@panes[@current_pane]) && !(@pane_lists[@panes[@current_pane]].selected().nil?)
                                    item = @pane_lists[@panes[@current_pane]].selected()
                                    if item && item[:key]
                                        if item[:key][:file]
                                            url = item[:key][:file]
                                            push_command('noidle')
                                            if key == :p
                                                push_command('clear')
                                            end
                                            push_command("add \"#{url}\"")
                                            if key == :p
                                                push_command('play')
                                            end
                                            push_command('idle')
                                            if key == :p
                                                @current_pane = 0
                                                draw_pane()
                                            end
                                        elsif item[:key][:playlist]
                                            playlist = item[:key][:playlist]
                                            push_command('noidle')
                                            push_command("listplaylist \"#{playlist}\"", {:source => :playlists, :command => ((key == 'p' || key == 'P') ? :play : :append)})
                                            push_command('idle')
                                            if key == :p
                                                @current_pane = 0
                                                draw_pane()
                                            end
                                        else
                                            filters = {}
                                            [:artist, :album, :title].each do |key|
                                                if item[:key].include?(key)
                                                    filters[key] = item[:key][key]
                                                end
                                            end
                                            if filters.size > 0
                                                push_command('noidle')
                                                push_command("find #{filters.map{ |k, v| "#{k} \"#{v}\""}.join(' ')}", {:source => :artist, :command => ((key == 'p' || key == 'P') ? :play : :append)})
                                                push_command('idle')
                                                if key == :p
                                                    @current_pane = 0
                                                    draw_pane()
                                                end
                                            end
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
                if rs.include?(@weather_socket)
                    handle_weather_update()
                end
                if rs.include?(@wikipedia_socket)
                    handle_wikipedia_update()
                end
                if rs.include?(@pipe_r)
                    message = @pipe_r.gets
        #             puts "> #{message}"
                    mpd_socket.puts(message.sub(/^@/, ''))
                end
                if rs.include?(@rpipe_r)
                    s = @rpipe_r.gets
                    if s.strip == '.'
                        draw_spinner()
                    end
                end
                if rs.include?(chat_socket)
                    s = JSON.parse(chat_socket.gets)
                    if s.class == Array
                        # it's the chat history
                        s.each do |entry|
                            @pane_lists[:chat].add_chat_entry(entry)
                        end
                        if @panes[@current_pane] == :chat
                            draw_pane()
                        end
                    else
                        @pane_lists[:chat].add_chat_entry(s)
                        if @panes[@current_pane] == :chat
                            draw_pane()
                        end
                    end
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
                            if ['listplaylist', 'playlistinfo', 'find', 'search', 'currentsong'].include?(from_command[:first])
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
                                        [:artist, :album, :title].each do |x|
                                            y = song[x.to_s.capitalize]
                                            y ||= ''
                                            result[x] << y
                                        end
                                    end
                                    [:artist, :album, :title].each do |x|
                                        result[x] = result[x].to_a.sort
                                        @pane_sublists[:search] ||= {}
                                        @pane_sublists[:search][x] = result[x]
                                    end
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
                            if ['listplaylists'].include?(from_command[:first])
                                lines = response.split("\n")
                                lines.pop
                                result[:data] = []
                                lines.each do |line|
                                    next unless line.index('playlist:') == 0
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

        mpd_socket.close
    end

end

player = CursesMpdPlayer.new
player.main_loop
