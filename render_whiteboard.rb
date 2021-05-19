#!/usr/bin/env ruby
# frozen_string_literal: true

require 'nokogiri'
require 'base64'
require 'zlib'

# Track how long the code is taking
start = Time.now

# Opens shapes.svg
@doc = Nokogiri::XML(File.open('shapes.svg'))

# Opens panzooms.xml
@pan = Nokogiri::XML(File.open('panzooms.xml'))

# Get intervals to display the frames
ins = @doc.xpath('//@in')
outs = @doc.xpath('//@out')
timestamps = @doc.xpath('//@timestamp')
undos = @doc.xpath('//@undo')
images = @doc.xpath('//xmlns:image', 'xmlns' => 'http://www.w3.org/2000/svg')
zooms = @pan.xpath('//@timestamp')

intervals = (ins + outs + timestamps + undos + zooms).to_a.map(&:to_s).map(&:to_f).uniq.sort

# Image paths need to follow the URI Data Scheme (for slides and polls)
images.each do |image|
  path = image.attr('xlink:href')

  # Open the image
  data = File.open(path).read

  image.set_attribute('xlink:href', "data:image/#{File.extname(path).delete('.')};base64,#{Base64.encode64(data)}")
  image.set_attribute('style', 'visibility:visible')
end

# Creates new file to hold the timestamps of the whiteboard
File.open('timestamps/whiteboard_timestamps', 'w') {}

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

  # Query slide we're currently on
  slide = @doc.xpath("//xmlns:image[@in <= #{interval_start} and #{interval_end} <= @out]", 'xmlns' => 'http://www.w3.org/2000/svg')

  # Query current viewbox parameter
  view_box = @pan.xpath("(//event[@timestamp <= #{interval_start}]/viewBox/text())[last()]")

  # Get slide information
  slide_id = slide.attr('id').to_s

  width = slide.attr('width').to_s
  height = slide.attr('height').to_s
  x = slide.attr('x').to_s
  y = slide.attr('y').to_s

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

  # Saves frame as SVGZ file
  File.open("frames/frame#{frame_number}.svgz", 'w') do |file|
    svgz = Zlib::GzipWriter.new(file)
    svgz.write(builder.to_xml)
    svgz.close
  end

  # Writes its duration down
  File.open('timestamps/whiteboard_timestamps', 'a') do |file|
    file.puts "file ../frames/frame#{frame_number}.svgz"
    file.puts "duration #{(interval_end - interval_start).round(1)}"
  end

  frame_number += 1
  #puts frame_number
end

# The last image needs to be specified twice, without specifying the duration (FFmpeg quirk)
File.open('timestamps/whiteboard_timestamps', 'a') do |file|
  file.puts "file ../frames/frame#{frame_number - 1}.svgz"
end

# Benchmark
finish = Time.now

puts finish - start
