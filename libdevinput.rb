#!/usr/bin/env ruby

# libdevinput
# A ruby library to read input device events on linux systems
#
# Copyright (c) 2010 Peter Rullmann (peter AT p4n.net / http://p4n.net)
# Homepage: http://github.com/prullmann/libdevinput

# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 3 of the License, or 
# (at your option) any later version.
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA 02111-1307 USA

require 'set'

class DevInput

    require 'time'

    TYPES = []
    TYPES[0] = 'Sync'
    TYPES[1] = 'Key'
    TYPES[2] = 'Relative'
    TYPES[3] = 'Absolute'
    TYPES[4] = 'Misc'
    TYPES[17] = 'LED'
    TYPES[18] = 'Sound'
    TYPES[20] = 'Repeat'
    TYPES[21] = 'ForceFeedback'
    TYPES[22] = 'Power'
    TYPES[23] = 'ForceFeedbackStatus'

    EVENTS = []
    EVENTS[0] = []
    EVENTS[0][0] = 'Sync'
    EVENTS[0][1] = 'Key'
    EVENTS[0][2] = 'Relative'
    EVENTS[0][3] = 'Absolute'
    EVENTS[0][4] = 'Misc'
    EVENTS[0][17] = 'LED'
    EVENTS[0][18] = 'Sound'
    EVENTS[0][20] = 'Repeat'
    EVENTS[0][21] = 'ForceFeedback'
    EVENTS[0][22] = 'Power'
    EVENTS[0][23] = 'ForceFeedbackStatus'
    EVENTS[1] = []
    EVENTS[1][0] = 'Reserved'
    EVENTS[1][1] = 'Esc'
    EVENTS[1][2] = '1'
    EVENTS[1][3] = '2'
    EVENTS[1][4] = '3'
    EVENTS[1][5] = '4'
    EVENTS[1][6] = '5'
    EVENTS[1][7] = '6'
    EVENTS[1][8] = '7'
    EVENTS[1][9] = '8'
    EVENTS[1][10] = '9'
    EVENTS[1][11] = '0'
    EVENTS[1][12] = 'Minus'
    EVENTS[1][13] = 'Equal'
    EVENTS[1][14] = 'Backspace'
    EVENTS[1][15] = 'Tab'
    EVENTS[1][16] = 'Q'
    EVENTS[1][17] = 'W'
    EVENTS[1][18] = 'E'
    EVENTS[1][19] = 'R'
    EVENTS[1][20] = 'T'
    EVENTS[1][21] = 'Y'
    EVENTS[1][22] = 'U'
    EVENTS[1][23] = 'I'
    EVENTS[1][24] = 'O'
    EVENTS[1][25] = 'P'
    EVENTS[1][26] = 'LeftBrace'
    EVENTS[1][27] = 'RightBrace'
    EVENTS[1][28] = 'Enter'
    EVENTS[1][29] = 'LeftControl'
    EVENTS[1][30] = 'A'
    EVENTS[1][31] = 'S'
    EVENTS[1][32] = 'D'
    EVENTS[1][33] = 'F'
    EVENTS[1][34] = 'G'
    EVENTS[1][35] = 'H'
    EVENTS[1][36] = 'J'
    EVENTS[1][37] = 'K'
    EVENTS[1][38] = 'L'
    EVENTS[1][39] = 'Semicolon'
    EVENTS[1][40] = 'Apostrophe'
    EVENTS[1][41] = 'Grave'
    EVENTS[1][42] = 'LeftShift'
    EVENTS[1][43] = 'BackSlash'
    EVENTS[1][44] = 'Z'
    EVENTS[1][45] = 'X'
    EVENTS[1][46] = 'C'
    EVENTS[1][47] = 'V'
    EVENTS[1][48] = 'B'
    EVENTS[1][49] = 'N'
    EVENTS[1][50] = 'M'
    EVENTS[1][51] = 'Comma'
    EVENTS[1][52] = 'Dot'
    EVENTS[1][53] = 'Slash'
    EVENTS[1][54] = 'RightShift'
    EVENTS[1][55] = 'KPAsterisk'
    EVENTS[1][56] = 'LeftAlt'
    EVENTS[1][57] = 'Space'
    EVENTS[1][58] = 'CapsLock'
    EVENTS[1][59] = 'F1'
    EVENTS[1][60] = 'F2'
    EVENTS[1][61] = 'F3'
    EVENTS[1][62] = 'F4'
    EVENTS[1][63] = 'F5'
    EVENTS[1][64] = 'F6'
    EVENTS[1][65] = 'F7'
    EVENTS[1][66] = 'F8'
    EVENTS[1][67] = 'F9'
    EVENTS[1][68] = 'F10'
    EVENTS[1][69] = 'NumLock'
    EVENTS[1][70] = 'ScrollLock'
    EVENTS[1][71] = 'KP7'
    EVENTS[1][72] = 'KP8'
    EVENTS[1][73] = 'KP9'
    EVENTS[1][74] = 'KPMinus'
    EVENTS[1][75] = 'KP4'
    EVENTS[1][76] = 'KP5'
    EVENTS[1][77] = 'KP6'
    EVENTS[1][78] = 'KPPlus'
    EVENTS[1][79] = 'KP1'
    EVENTS[1][80] = 'KP2'
    EVENTS[1][81] = 'KP3'
    EVENTS[1][82] = 'KP0'
    EVENTS[1][83] = 'KPDot'
    EVENTS[1][85] = 'Zenkaku/Hankaku'
    EVENTS[1][86] = '_102nd'
    EVENTS[1][87] = 'F11'
    EVENTS[1][88] = 'F12'
    EVENTS[1][89] = 'RO'
    EVENTS[1][90] = 'Katakana'
    EVENTS[1][91] = 'HIRAGANA'
    EVENTS[1][92] = 'Henkan'
    EVENTS[1][93] = 'Katakana/Hiragana'
    EVENTS[1][94] = 'Muhenkan'
    EVENTS[1][95] = 'KPJpComma'
    EVENTS[1][96] = 'KPEnter'
    EVENTS[1][97] = 'RightCtrl'
    EVENTS[1][98] = 'KPSlash'
    EVENTS[1][99] = 'SysRq'
    EVENTS[1][100] = 'RightAlt'
    EVENTS[1][101] = 'LineFeed'
    EVENTS[1][102] = 'Home'
    EVENTS[1][103] = 'Up'
    EVENTS[1][104] = 'PageUp'
    EVENTS[1][105] = 'Left'
    EVENTS[1][106] = 'Right'
    EVENTS[1][107] = 'End'
    EVENTS[1][108] = 'Down'
    EVENTS[1][109] = 'PageDown'
    EVENTS[1][110] = 'Insert'
    EVENTS[1][111] = 'Delete'
    EVENTS[1][112] = 'Macro'
    EVENTS[1][113] = 'Mute'
    EVENTS[1][114] = 'VolumeDown'
    EVENTS[1][115] = 'VolumeUp'
    EVENTS[1][116] = 'Power'
    EVENTS[1][117] = 'KPEqual'
    EVENTS[1][118] = 'KPPlusMinus'
    EVENTS[1][119] = 'Pause'
    EVENTS[1][121] = 'KPComma'
    EVENTS[1][122] = 'Hanguel'
    EVENTS[1][123] = 'Hanja'
    EVENTS[1][124] = 'Yen'
    EVENTS[1][125] = 'LeftMeta'
    EVENTS[1][126] = 'RightMeta'
    EVENTS[1][127] = 'Compose'
    EVENTS[1][128] = 'Stop'
    EVENTS[1][129] = 'Again'
    EVENTS[1][130] = 'Props'
    EVENTS[1][131] = 'Undo'
    EVENTS[1][132] = 'Front'
    EVENTS[1][133] = 'Copy'
    EVENTS[1][134] = 'Open'
    EVENTS[1][135] = 'Paste'
    EVENTS[1][136] = 'Find'
    EVENTS[1][137] = 'Cut'
    EVENTS[1][138] = 'Help'
    EVENTS[1][139] = 'Menu'
    EVENTS[1][140] = 'Calc'
    EVENTS[1][141] = 'Setup'
    EVENTS[1][142] = 'Sleep'
    EVENTS[1][143] = 'WakeUp'
    EVENTS[1][144] = 'File'
    EVENTS[1][145] = 'SendFile'
    EVENTS[1][146] = 'DeleteFile'
    EVENTS[1][147] = 'X-fer'
    EVENTS[1][148] = 'Prog1'
    EVENTS[1][149] = 'Prog2'
    EVENTS[1][150] = 'WWW'
    EVENTS[1][151] = 'MSDOS'
    EVENTS[1][152] = 'Coffee'
    EVENTS[1][153] = 'Direction'
    EVENTS[1][154] = 'CycleWindows'
    EVENTS[1][155] = 'Mail'
    EVENTS[1][156] = 'Bookmarks'
    EVENTS[1][157] = 'Computer'
    EVENTS[1][158] = 'Back'
    EVENTS[1][159] = 'Forward'
    EVENTS[1][160] = 'CloseCD'
    EVENTS[1][161] = 'EjectCD'
    EVENTS[1][162] = 'EjectCloseCD'
    EVENTS[1][163] = 'NextSong'
    EVENTS[1][164] = 'PlayPause'
    EVENTS[1][165] = 'PreviousSong'
    EVENTS[1][166] = 'StopCD'
    EVENTS[1][167] = 'Record'
    EVENTS[1][168] = 'Rewind'
    EVENTS[1][169] = 'Phone'
    EVENTS[1][170] = 'ISOKey'
    EVENTS[1][171] = 'Config'
    EVENTS[1][172] = 'HomePage'
    EVENTS[1][173] = 'Refresh'
    EVENTS[1][174] = 'Exit'
    EVENTS[1][175] = 'Move'
    EVENTS[1][176] = 'Edit'
    EVENTS[1][177] = 'ScrollUp'
    EVENTS[1][178] = 'ScrollDown'
    EVENTS[1][179] = 'KPLeftParenthesis'
    EVENTS[1][180] = 'KPRightParenthesis'
    EVENTS[1][183] = 'F13'
    EVENTS[1][184] = 'F14'
    EVENTS[1][185] = 'F15'
    EVENTS[1][186] = 'F16'
    EVENTS[1][187] = 'F17'
    EVENTS[1][188] = 'F18'
    EVENTS[1][189] = 'F19'
    EVENTS[1][190] = 'F20'
    EVENTS[1][191] = 'F21'
    EVENTS[1][192] = 'F22'
    EVENTS[1][193] = 'F23'
    EVENTS[1][194] = 'F24'
    EVENTS[1][200] = 'PlayCD'
    EVENTS[1][201] = 'PauseCD'
    EVENTS[1][202] = 'Prog3'
    EVENTS[1][203] = 'Prog4'
    EVENTS[1][205] = 'Suspend'
    EVENTS[1][206] = 'Close'
    EVENTS[1][207] = 'Play'
    EVENTS[1][208] = 'Fast Forward'
    EVENTS[1][209] = 'Bass Boost'
    EVENTS[1][210] = 'Print'
    EVENTS[1][211] = 'HP'
    EVENTS[1][212] = 'Camera'
    EVENTS[1][213] = 'Sound'
    EVENTS[1][214] = 'Question'
    EVENTS[1][215] = 'Email'
    EVENTS[1][216] = 'Chat'
    EVENTS[1][217] = 'Search'
    EVENTS[1][218] = 'Connect'
    EVENTS[1][219] = 'Finance'
    EVENTS[1][220] = 'Sport'
    EVENTS[1][221] = 'Shop'
    EVENTS[1][222] = 'Alternate Erase'
    EVENTS[1][223] = 'Cancel'
    EVENTS[1][224] = 'Brightness down'
    EVENTS[1][225] = 'Brightness up'
    EVENTS[1][226] = 'Media'
    EVENTS[1][240] = 'Unknown'
    EVENTS[1][256] = 'Btn0'
    EVENTS[1][257] = 'Btn1'
    EVENTS[1][258] = 'Btn2'
    EVENTS[1][259] = 'Btn3'
    EVENTS[1][260] = 'Btn4'
    EVENTS[1][261] = 'Btn5'
    EVENTS[1][262] = 'Btn6'
    EVENTS[1][263] = 'Btn7'
    EVENTS[1][264] = 'Btn8'
    EVENTS[1][265] = 'Btn9'
    EVENTS[1][272] = 'LeftBtn'
    EVENTS[1][273] = 'RightBtn'
    EVENTS[1][274] = 'MiddleBtn'
    EVENTS[1][275] = 'SideBtn'
    EVENTS[1][276] = 'ExtraBtn'
    EVENTS[1][277] = 'ForwardBtn'
    EVENTS[1][278] = 'BackBtn'
    EVENTS[1][279] = 'TaskBtn'
    EVENTS[1][288] = 'Trigger'
    EVENTS[1][289] = 'ThumbBtn'
    EVENTS[1][290] = 'ThumbBtn2'
    EVENTS[1][291] = 'TopBtn'
    EVENTS[1][292] = 'TopBtn2'
    EVENTS[1][293] = 'PinkieBtn'
    EVENTS[1][294] = 'BaseBtn'
    EVENTS[1][295] = 'BaseBtn2'
    EVENTS[1][296] = 'BaseBtn3'
    EVENTS[1][297] = 'BaseBtn4'
    EVENTS[1][298] = 'BaseBtn5'
    EVENTS[1][299] = 'BaseBtn6'
    EVENTS[1][303] = 'BtnDead'
    EVENTS[1][304] = 'BtnA'
    EVENTS[1][305] = 'BtnB'
    EVENTS[1][306] = 'BtnC'
    EVENTS[1][307] = 'BtnX'
    EVENTS[1][308] = 'BtnY'
    EVENTS[1][309] = 'BtnZ'
    EVENTS[1][310] = 'BtnTL'
    EVENTS[1][311] = 'BtnTR'
    EVENTS[1][312] = 'BtnTL2'
    EVENTS[1][313] = 'BtnTR2'
    EVENTS[1][314] = 'BtnSelect'
    EVENTS[1][315] = 'BtnStart'
    EVENTS[1][316] = 'BtnMode'
    EVENTS[1][317] = 'BtnThumbL'
    EVENTS[1][318] = 'BtnThumbR'
    EVENTS[1][320] = 'ToolPen'
    EVENTS[1][321] = 'ToolRubber'
    EVENTS[1][322] = 'ToolBrush'
    EVENTS[1][323] = 'ToolPencil'
    EVENTS[1][324] = 'ToolAirbrush'
    EVENTS[1][325] = 'ToolFinger'
    EVENTS[1][326] = 'ToolMouse'
    EVENTS[1][327] = 'ToolLens'
    EVENTS[1][330] = 'Touch'
    EVENTS[1][331] = 'Stylus'
    EVENTS[1][332] = 'Stylus2'
    EVENTS[1][333] = 'Tool Doubletap'
    EVENTS[1][334] = 'Tool Tripletap'
    EVENTS[1][336] = 'WheelBtn'
    EVENTS[1][337] = 'Gear up'
    EVENTS[1][352] = 'Ok'
    EVENTS[1][353] = 'Select'
    EVENTS[1][354] = 'Goto'
    EVENTS[1][355] = 'Clear'
    EVENTS[1][356] = 'Power2'
    EVENTS[1][357] = 'Option'
    EVENTS[1][358] = 'Info'
    EVENTS[1][359] = 'Time'
    EVENTS[1][360] = 'Vendor'
    EVENTS[1][361] = 'Archive'
    EVENTS[1][362] = 'Program'
    EVENTS[1][363] = 'Channel'
    EVENTS[1][364] = 'Favorites'
    EVENTS[1][365] = 'EPG'
    EVENTS[1][366] = 'PVR'
    EVENTS[1][367] = 'MHP'
    EVENTS[1][368] = 'Language'
    EVENTS[1][369] = 'Title'
    EVENTS[1][370] = 'Subtitle'
    EVENTS[1][371] = 'Angle'
    EVENTS[1][372] = 'Zoom'
    EVENTS[1][373] = 'Mode'
    EVENTS[1][374] = 'Keyboard'
    EVENTS[1][375] = 'Screen'
    EVENTS[1][376] = 'PC'
    EVENTS[1][377] = 'TV'
    EVENTS[1][378] = 'TV2'
    EVENTS[1][379] = 'VCR'
    EVENTS[1][380] = 'VCR2'
    EVENTS[1][381] = 'Sat'
    EVENTS[1][382] = 'Sat2'
    EVENTS[1][383] = 'CD'
    EVENTS[1][384] = 'Tape'
    EVENTS[1][385] = 'Radio'
    EVENTS[1][386] = 'Tuner'
    EVENTS[1][387] = 'Player'
    EVENTS[1][388] = 'Text'
    EVENTS[1][389] = 'DVD'
    EVENTS[1][390] = 'Aux'
    EVENTS[1][391] = 'MP3'
    EVENTS[1][392] = 'Audio'
    EVENTS[1][393] = 'Video'
    EVENTS[1][394] = 'Directory'
    EVENTS[1][395] = 'List'
    EVENTS[1][396] = 'Memo'
    EVENTS[1][397] = 'Calendar'
    EVENTS[1][398] = 'Red'
    EVENTS[1][399] = 'Green'
    EVENTS[1][400] = 'Yellow'
    EVENTS[1][401] = 'Blue'
    EVENTS[1][402] = 'ChannelUp'
    EVENTS[1][403] = 'ChannelDown'
    EVENTS[1][404] = 'First'
    EVENTS[1][405] = 'Last'
    EVENTS[1][406] = 'AB'
    EVENTS[1][407] = 'Next'
    EVENTS[1][408] = 'Restart'
    EVENTS[1][409] = 'Slow'
    EVENTS[1][410] = 'Shuffle'
    EVENTS[1][411] = 'Break'
    EVENTS[1][412] = 'Previous'
    EVENTS[1][413] = 'Digits'
    EVENTS[1][414] = 'TEEN'
    EVENTS[1][415] = 'TWEN'
    EVENTS[1][448] = 'Delete EOL'
    EVENTS[1][449] = 'Delete EOS'
    EVENTS[1][450] = 'Insert line'
    EVENTS[1][451] = 'Delete line'
    EVENTS[2] = []
    EVENTS[2][0] = 'X'
    EVENTS[2][1] = 'Y'
    EVENTS[2][2] = 'Z'
    EVENTS[2][6] = 'HWheel'
    EVENTS[2][7] = 'Dial'
    EVENTS[2][8] = 'Wheel'
    EVENTS[2][9] = 'Misc'
    EVENTS[3] = []
    EVENTS[3][0] = 'X'
    EVENTS[3][1] = 'Y'
    EVENTS[3][2] = 'Z'
    EVENTS[3][3] = 'Rx'
    EVENTS[3][4] = 'Ry'
    EVENTS[3][5] = 'Rz'
    EVENTS[3][6] = 'Throttle'
    EVENTS[3][7] = 'Rudder'
    EVENTS[3][8] = 'Wheel'
    EVENTS[3][9] = 'Gas'
    EVENTS[3][10] = 'Brake'
    EVENTS[3][16] = 'Hat0X'
    EVENTS[3][17] = 'Hat0Y'
    EVENTS[3][18] = 'Hat1X'
    EVENTS[3][19] = 'Hat1Y'
    EVENTS[3][20] = 'Hat2X'
    EVENTS[3][21] = 'Hat2Y'
    EVENTS[3][22] = 'Hat3X'
    EVENTS[3][23] = 'Hat 3Y'
    EVENTS[3][24] = 'Pressure'
    EVENTS[3][25] = 'Distance'
    EVENTS[3][26] = 'XTilt'
    EVENTS[3][27] = 'YTilt'
    EVENTS[3][28] = 'Tool Width'
    EVENTS[3][32] = 'Volume'
    EVENTS[3][40] = 'Misc'
    EVENTS[4] = []
    EVENTS[4][0] = 'Serial'
    EVENTS[4][1] = 'Pulseled'
    EVENTS[4][2] = 'Gesture'
    EVENTS[4][3] = 'RawData'
    EVENTS[4][4] = 'ScanCode'
    EVENTS[17] = []
    EVENTS[17][0] = 'NumLock'
    EVENTS[17][1] = 'CapsLock'
    EVENTS[17][2] = 'ScrollLock'
    EVENTS[17][3] = 'Compose'
    EVENTS[17][4] = 'Kana'
    EVENTS[17][5] = 'Sleep'
    EVENTS[17][6] = 'Suspend'
    EVENTS[17][7] = 'Mute'
    EVENTS[17][8] = 'Misc'
    EVENTS[18] = []
    EVENTS[18][0] = 'Click'
    EVENTS[18][1] = 'Bell'
    EVENTS[18][2] = 'Tone'
    EVENTS[20] = []
    EVENTS[20][0] = 'Delay'
    EVENTS[20][1] = 'Period'

    KEY_VALUES = ['Release', 'Press', 'Repeat']

    Event = Struct.new(:tv_sec, :tv_usec, :type, :code, :value)

    MODIFIERS = [:leftcontrol, :leftshift, :leftmeta, :leftalt, :rightshift, :rightalt]

    # open Event class and add some convenience methods
    class Event
        def time; Time.at(tv_sec) end
        def type_str; TYPES[type] end
        def code_str; EVENTS[type][code] if EVENTS[type] end
        def code_sym; EVENTS[type][code].downcase.gsub(' ', '_').to_sym if EVENTS[type] end
        def value_str; KEY_VALUES[value] if type == 1 end
        def value_sym; KEY_VALUES[value].downcase.to_sym if type == 1 end
        def to_s
            type_s = type.to_s
            type_s += " (#{type_str})" if type_str
            code_s = code.to_s
            code_s += " (#{code_str})" if code_str
            value_s = value.to_s
            value_s += " (#{value_str})" if value_str
            "#{time.iso8601} type: #{type_s} code: #{code_s} value: #{value_s}"
        end
    end

    def initialize(filename)
        @dev = File.open(filename)
        @modifiers_set = Set.new
        @modifiers = {}
        MODIFIERS.each do |x|
            @modifiers[x] = false
        end
        @code_to_char = {
            :grave => '^',
            :minus => 'ß',
            :leftbrace => 'ü',
            :rightbrace => '+',
            :backslash => '#',
            :semicolon => 'ö',
            :apostrophe => 'ä',
            :comma => ',',
            :dot => '.',
            :slash => '-',
            :_102nd => '<',
            :space => ' '
        }
        ('a'..'z').each { |x| @code_to_char[x.to_sym] = x }
        ('0'..'9').each { |x| @code_to_char[x.to_sym] = x }
        @code_to_char[:y] = 'z'
        @code_to_char[:z] = 'y'

        @code_to_char_shift = {
            :grave => '°',
            :minus => '?',
            :leftbrace => 'Ü',
            :rightbrace => '*',
            :backslash => '\'',
            :semicolon => 'Ö',
            :apostrophe => 'Ä',
            :comma => ';',
            :dot => ':',
            :slash => '_',
            :_102nd => '>',
            :space => ' '
        }
        ('A'..'Z').each { |x| @code_to_char_shift[x.downcase.to_sym] = x }
        ('0'..'9').each_with_index { |x, _| @code_to_char_shift[x.to_sym] = '=!"§$%&/()'[_] }
        @code_to_char_shift[:y] = 'Z'
        @code_to_char_shift[:z] = 'Y'

        @code_to_char_alt_gr = {
            '7'.to_sym => '{',
            '8'.to_sym => '[',
            '9'.to_sym => ']',
            '0'.to_sym => '}',
            :minus => '\\',
            :rightbrace => '~',
            :_102nd => '|',
            :q => '@'
        }
    end

    attr_reader :dev

    def read
        bin = @dev.read(16)
        Event.new(*bin.unpack("llSSl"))
    end

    def each
        begin
            loop do
                yield read
            end
        rescue Errno::ENODEV
        end
    end

    def handle()
        event = read
        if event.type == 1
            if MODIFIERS.include?(event.code_sym)
                if event.value_sym == :press
                    @modifiers[event.code_sym] = true
                    @modifiers_set << event.code_sym
                end
                if event.value_sym == :release
                    @modifiers[event.code_sym] = false
                    @modifiers_set.delete(event.code_sym)
                end
            else
                if event.value_sym == :press || event.value_sym == :repeat
                    char = nil
                    lookup_table = nil
                    if @modifiers_set.empty?
                        lookup_table = @code_to_char
                    elsif !(@modifiers_set && Set.new([:leftshift, :rightshift])).empty? && (@modifiers_set - Set.new([:leftshift, :rightshift])).empty?
                        lookup_table = @code_to_char_shift
                    elsif @modifiers_set == Set.new([:rightalt])
                        lookup_table = @code_to_char_alt_gr
                    end
                    if lookup_table && lookup_table.include?(event.code_sym)
                        char = lookup_table[event.code_sym]
                    end
                    return {:modifiers => @modifiers.dup, :event => event, :char => char}
                end
            end
        end
        nil
    end

end
