#!/usr/bin/env ruby
# frozen_string_literal: true

require 'nokogiri'
require 'base64'

# Opens shapes.svg
@doc = Nokogiri::XML(File.open('shapes.svg'))

# Get intervals to display the frames
ins = @doc.xpath('//@in')
outs = @doc.xpath('//@out')
timestamps = @doc.xpath('//@timestamp')
undos = @doc.xpath('//@undo')
images = @doc.xpath('//xmlns:image', 'xmlns' => 'http://www.w3.org/2000/svg')

intervals = (ins + outs + timestamps + undos).to_a.map(&:to_s).map(&:to_f).uniq.sort

# Image paths need to follow the URI Data Scheme (for slides and polls)
images.each do |image|
  path = image.attr('xlink:href')

  # Open the image
  puts path
  data = File.open(path).read

  image.set_attribute('xlink:href', "data:image/#{File.extname(path).delete('.')};base64,#{Base64.encode64(data)}")
  image.set_attribute('style', 'visibility:visible')
end

# Creates new file to hold the timestamps of the whiteboard
File.open('whiteboard_timestamps', 'w') {}

# Intervals with a value of -1 do not correspond to a timestamp
intervals = intervals.drop(1) if intervals.first == -1

# Obtain interval range that each frame will be shown for
frame_number = 0
frames = []

intervals.each_cons(2) do |(a, b)|
  frames << [a, b]
end

# Render the visible frame for each interval
frames.each do |frame|
  interval_start = frame[0]
  interval_end = frame[1]

  # Figure out which slide we're currently on
  slide = @doc.xpath("//xmlns:image[@in <= #{interval_start} and #{interval_end} <= @out]", 'xmlns' => 'http://www.w3.org/2000/svg')

  # Get slide information
  slide_id = slide.attr('id').to_s

  width = slide.attr('width').to_s
  height = slide.attr('height').to_s
  x = slide.attr('x').to_s
  y = slide.attr('y').to_s

  view_box = '0 0 1600 900'

  draw = @doc.xpath(
    "//xmlns:g[@class=\"canvas\" and @image=\"#{slide_id}\"]/xmlns:g[@timestamp < \"#{interval_end}\" and (@undo = \"-1\" or @undo >= \"#{interval_end}\")]", 'xmlns' => 'http://www.w3.org/2000/svg'
  )

  # Builds SVG frame
  builder = Nokogiri::XML::Builder.new(encoding: 'UTF-8') do |xml|
    xml.doc.create_internal_subset('svg', '-//W3C//DTD SVG 1.1//EN', 'http://www.w3.org/Graphics/SVG/1.1/DTD/svg11.dtd')

    xml.svg(width: width, height: height, x: x, y: y, version: '1.1', viewBox: view_box, 'xmlns' => 'http://www.w3.org/2000/svg', 'xmlns:xlink' => 'http://www.w3.org/1999/xlink') do
      # Display background image
      xml.image('xlink:href': slide.attr('href'), width: width, height: height, x: x, y: y, style: slide.attr('style'))

      # Add annotations
      draw.each do |shape|
        # Make shape visible
        style = shape.attr('style')
        style.sub! 'hidden', 'visible'

        xml.g(style: style) do
          xml << shape.xpath('./*').to_s
        end
      end
    end
  end

  # Saves frame as SVG file
  File.open("frames/frame#{frame_number}.svg", 'w') do |file|
    file.write(builder.to_xml)
  end

  # Writes its duration down
  File.open('whiteboard_timestamps', 'a') do |file|
    file.puts "file frames/frame#{frame_number}.svg"
    file.puts "duration #{(interval_end - interval_start).round(1)}"
  end

  frame_number += 1
  puts frame_number
end

# The last image needs to be specified twice, without specifying the duration (FFmpeg quirk)
File.open('whiteboard_timestamps', 'a') do |file|
  file.puts "file frames/frame#{frame_number - 1}.svg"
end
