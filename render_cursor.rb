#!/usr/bin/env ruby
# frozen_string_literal: true

require 'nokogiri'

start = Time.now

# Opens cursor.xml and shapes.svg
@doc = Nokogiri::XML(File.open('cursor.xml'))
@img = Nokogiri::XML(File.open('shapes.svg'))

# Get cursor timestamps
timestamps = @doc.xpath('//@timestamp').to_a.map(&:to_s).map(&:to_f)

# Creates new file to hold the timestamps and the cursor's position
File.open('timestamps/cursor_timestamps', 'w') {}

# Obtains all cursor events
cursor = @doc.xpath('//event/cursor')

File.open('timestamps/cursor_timestamps', 'a') do |file|
    timestamps.each.with_index do |timestamp, frame_number|

        # Query to figure out which slide we're on - based on interval start since slide can change if mouse stationary
        slide = @img.xpath("(//xmlns:image[@in <= #{timestamp}])[last()]", 'xmlns' => 'http://www.w3.org/2000/svg')
    
        width = slide.attr('width').to_s
        height = slide.attr('height').to_s
    
        # Get cursor coordinates
        pointer = cursor[frame_number].text.split
    
        cursor_x = pointer[0].to_f * width.to_f
        cursor_y = pointer[1].to_f * height.to_f
    
        # Scaling required to reach target dimensions
        x_scale = 1600 / width.to_f
        y_scale = 1080 / height.to_f
    
        # Keep aspect ratio
        scale_factor = [x_scale, y_scale].min
        
        # Scale
        cursor_x *= scale_factor
        cursor_y *= scale_factor
    
        # Translate given difference to new on-screen dimensions
        x_offset = (1600 - scale_factor * width.to_f) / 2
        y_offset = (1080 - scale_factor * height.to_f) / 2
    
        cursor_x += x_offset
        cursor_y += y_offset
    
        # puts "x offset: #{x_offset}, y offset: #{y_offset}, scale factor: #{scale_factor}"
    
        # Move whiteboard to the right, making space for the chat and webcams
        cursor_x += 320
    
        # Writes the timestamp and position down
        file.puts "#{timestamp}"
        file.puts "overlay@mouse x #{cursor_x.round(3)},"
        file.puts "overlay@mouse y #{cursor_y.round(3)};"
    end
end

finish = Time.now
puts finish - start