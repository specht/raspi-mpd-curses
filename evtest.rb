#!/usr/bin/env ruby
require './libdevinput.rb'

dev = DevInput.new "/dev/input/event0"
# grab keyboard
dev.dev.ioctl(1074021776, 1)
dev.each do |event|
    puts "got event #{event}"
end
