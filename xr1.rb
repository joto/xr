#!/usr/bin/ruby
#-----------------------------------------------------------------------------
#
#  xr1.rb
#
#  experimental renderer no. 1
#
#  The "configuration language" is very much inspired by the Protovis
#  framework (see http://vis.stanford.edu/protovis/ ).
#
#  In this experiment I wanted to see how I can translate that approach to
#  map rendering. Important for this approach is that symbolizer classes can
#  be derived from other symbolizer classes and extend them.
#
#-----------------------------------------------------------------------------

require 'rubygems'

require 'GD'
require 'geo_ruby'

#-----------------------------------------------------------------------------

module XR

    class Map

        attr_reader :canvas_width, :canvas_height, :xmin, :ymin, :xmax, :ymax

        def initialize
            @vis = []
        end

        def canvas(width, height)
            @canvas_width  = width
            @canvas_height = height
            self
        end

        def bbox(xmin, ymin, xmax, ymax)
            @xmin = xmin
            @ymin = ymin
            @xmax = xmax
            @ymax = ymax
            self
        end

        def add(vis)
            @vis << vis
            vis.set_map = self
            vis
        end

        def render
            im = GD::Image.newTrueColor(@canvas_width, @canvas_height)
            white = GD::Image.trueColor(255, 255, 255)
            im.filledRectangle(0, 0, @canvas_width, @canvas_height, white)
            @vis.each do |vis|
                vis.render(im)
            end
            File.open('xr1.png', 'w+') do |png|
                im.png png
            end
        end

    end

    #--------------------------

    module Data

        class Shapefile

            def initialize(filename)
                @shpfile = GeoRuby::Shp4r::ShpFile.open(filename)
            end

            def each
                @shpfile.each do |shp|
                    geom = shp.geometry
                    attr = shp.data
                    yield geom, attr
                end
            end

            def records
                @shpfile.records
            end

        end

    end

    #--------------------------

    module Symbolizer

        class Base

            attr_reader :map

            def set_map=(map)
                @map = map
            end

        end

        class Layer < Base

            def initialize
                @vis = []
            end

            def add(vis)
                @vis << vis
                vis.set_map = map
                vis
            end

            def render(im)
                (-5..5).each do |layer|
                    STDERR.puts "layer: #{layer}"
                    @vis.each do |vis|
                        vis.filter{ |attr|
                            attr['layer'].to_i == layer
                        }
                        vis.render(im)
                    end
                end
            end

        end

        class Line < Base

            def initialize
                @widthproc = proc { 1 }
                @colorproc = proc { [0, 0, 0] }
                @sortproc = proc { 0 }
                @filterproc = proc { true }
            end

            def filter(&block)
                @filterproc = block
                self
            end

            def color(color = [0, 0, 0], &block)
                @colorproc = block ? block : proc { color }
                self
            end

            def width(width=1, &block)
                @widthproc = block ? block : proc { width }
                self
            end

            def data(datasource)
                @datasource = datasource
                self
            end

            def sort(&block)
                @sortproc = block
                self
            end

            def projx(x)
                r = (x-map.xmin) / (map.xmax-map.xmin) * map.canvas_width
                r
            end

            def projy(y)
                r = (map.ymax-y) / (map.ymax-map.ymin) * map.canvas_height
                r
            end

            def render(im)
                @datasource.records.sort{ |a, b| @sortproc.call(a.data, b.data) }.each do |record|
                    geom = record.geometry
                    attr = record.data
                    if @filterproc.call(attr)
                        lastx = nil
                        lasty = nil
                        geom.geometries.each do |g|
                            g.points.each do |point|
                                if lastx != nil
                                    color = @colorproc.call(attr)
                                    im.thickness = @widthproc.call(attr)
                                    im.line(projx(lastx), projy(lasty), projx(point.x), projy(point.y), GD::Image.trueColor(*color))
                                end
                                lastx = point.x
                                lasty = point.y
                            end
                        end
                    end
                end
            end

        end # class Line

        class LineWithCasing < Line

            def initialize
                @core = Line.new
                @casing = Line.new
                @core_width = 0
                @casing_width = 0
                self
            end

            def filter(&block)
                @core.filter(&block)
                @casing.filter(&block)
                self
            end

            def sort(&block)
                @core.sort(&block)
                @casing.sort(&block)
                self
            end

            def core_color(*args, &block)
                @core.color(*args, &block)
                self
            end

            def casing_color(*args, &block)
                @casing.color(*args, &block)
                self
            end

            def core_width(width=1, &block)
                @core_widthproc = block ? block : proc { width }
                self
            end

            def casing_width(width=1, &block)
                @casing_widthproc = block ? block : proc { width }
                self
            end

            def render(im)
                @casing.set_map = map
                @core.set_map = map

                @casing.data(@datasource)
                @core.data(@datasource)

                @casing.width do |attr|
                    cw = @core_widthproc.call(attr)
                    cw + @casing_widthproc.call(attr)
                end

                @core.width(&@core_widthproc)

                @casing.render(im)
                @core.render(im)
            end

        end # class LineWithCasing

    end # module Symbolizer

end # module XR


#-----------------------------------------------------------------------------
#
#  the "configuration" starts here
#
#-----------------------------------------------------------------------------

roads = XR::Data::Shapefile.new('data/roads.shp')

rails = XR::Data::Shapefile.new('data/rails.shp')

map = XR::Map.new.
        canvas(1200, 700).
        bbox(8.38, 48.995, 8.42, 49.01)

type2width = {
    'motorway' => 10,
    'trunk' => 10,
    'primary' => 8,
    'motorway_link' => 2,
    'trunk_link' => 2,
    'primary_link' => 2,
    'secondary' => 8,
    'tertiary' => 6,
    'unclassified' => 6,
    'residential' => 6,
    'cycleway' => 1,
    'footway' => 1,
    'service' => 2,
    'living_street' => 6,
    'pedestrian' => 6
}

road_prio = [ 'motorway', 'trunk', 'primary', 'secondary', 'tertiary', 'motorway_link', 'trunk_link', 'primary_link', 'unclassified', 'residential', 'living_street', 'pedestrian', 'service', 'cycleway', 'footway' ]
road_prio_lookup = {}
road_prio.each_with_index { |el, idx|
    road_prio_lookup[el] = idx
}

layer = map.add(XR::Symbolizer::Layer.new)

layer.add(XR::Symbolizer::LineWithCasing.new).
        data(roads).
        sort{ |a, b|
            road_prio_lookup[b['type']] <=> road_prio_lookup[a['type']]
        }.
        core_color{ |attr|
            attr['type'] =~ /^(motorway|trunk|primary)(_link)?$/ ? [229, 181, 13] :
                attr['type'] =~ /^(secondary|tertiary)$/ ? [229, 225, 13] :
                [255, 255, 255]
        }.
        casing_color{ |attr|
            attr['bridge'] ? [0, 0, 0] : [150, 150, 150]
        }.
        core_width{ |attr|
            type2width[attr['type']]
        }.
        casing_width{ |attr|
            attr['bridge'] ? 4 : 2
        }

layer.add(XR::Symbolizer::Line.new).
        data(rails).
        color([0, 0, 200]).
        width(1)

map.render

