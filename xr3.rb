#!/usr/bin/ruby
#-----------------------------------------------------------------------------
#
#  xr3.rb
#
#  experimental renderer no. 3
#
#  ... which makes the ordering more configurable and less magic
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
            @objects = []
            @order = []
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

        def order(*el)
            @order = el
            self
        end

        def add(vis)
            @vis << vis
            vis.set_map = self
            vis
        end

        def add_object(object)
            @objects << object
            object
        end

        def proj(x, y)
            [ (x-xmin) / (xmax-xmin) * canvas_width,
              (ymax-y) / (ymax-ymin) * canvas_height ]
        end

        def compare(a, b)
            @order.each do |el|
                ao = a.order[el] || 0
                bo = b.order[el] || 0
                if ao != bo
                    return ao <=> bo
                end
            end
            0
        end

        def render
            @vis.each do |vis|
                vis.prepare
            end

            @objects.sort! do |a,b|
                compare(a, b)
            end

            im = GD::Image.newTrueColor(@canvas_width, @canvas_height)
            white = GD::Image.trueColor(255, 255, 255)
            im.filledRectangle(0, 0, @canvas_width, @canvas_height, white)

            @objects.each do |object|
                object.render(im)
            end

            File.open('xr3.png', 'w+') do |png|
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

        end

    end

    #--------------------------

    module Features

        class Base

            attr_accessor :map, :geom, :options, :order

            def initialize(map, geom, options)
                @map = map
                @geom = geom
                @options = options
                @order = []
            end

        end

        class Line < Base

            def render(im)
                lastx = nil
                lasty = nil
                geom.geometries.each do |g|
                    g.points.each do |point|
                        if lastx != nil
                            color = options[:color]
                            im.thickness = options[:width]
                            lpp = map.proj(lastx, lasty)
                            pp = map.proj(point.x, point.y)
                            im.line(lpp[0], lpp[1], pp[0], pp[1], GD::Image.trueColor(*color))
                        end
                        lastx = point.x
                        lasty = point.y
                    end
                end
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

        class Line < Base

            def initialize
                @widthproc = proc { 1 }
                @colorproc = proc { [0, 0, 0] }
                @orderproc = proc { {} }
            end

            def color(color = [0, 0, 0], &block)
                @colorproc = block ? block : proc { color }
                self
            end

            def width(width=1, &block)
                @widthproc = block ? block : proc { width }
                self
            end

            def order(order={}, &block)
                @orderproc = block ? block : proc { order }
                self
            end

            def data(datasource)
                @datasource = datasource
                self
            end

            def prepare(prio=0)
                @datasource.each do |geom, attr|
                    line = XR::Features::Line.new(map, geom, {
                        :color => @colorproc.call(attr),
                        :width => @widthproc.call(attr)
                    })
                    line.order = @orderproc.call(attr)
                    map.add_object(line)
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

            def order(order={}, &block)
                orderproc = block ? block : proc { order }
                @casing.order{ |attr|
                    o = orderproc.call(attr)
                    o[:casing_core] = 0
                    o
                }
                @core.order{ |attr|
                    o = orderproc.call(attr)
                    o[:casing_core] = 1
                    o
                }
                self
            end

            def prepare
                @casing.set_map = map
                @core.set_map = map

                @casing.data(@datasource)
                @core.data(@datasource)

                @casing.width do |attr|
                    cw = @core_widthproc.call(attr)
                    cw + @casing_widthproc.call(attr)
                end

                @core.width(&@core_widthproc)

                @casing.prepare
                @core.prepare
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
        bbox(8.38, 48.995, 8.42, 49.01).
        order(:layer, :casing_core, :road_type)

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
    road_prio_lookup[el] = 100 - idx
}

map.add(XR::Symbolizer::LineWithCasing.new).
        data(roads).
        order{ |attr|
            { :layer => attr['layer'].to_i,
              :road_type => road_prio_lookup[attr['type']].to_i
            }
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

map.add(XR::Symbolizer::Line.new).
        data(rails).
        order{ |attr|
            { :layer => attr['layer'].to_i }
        }.
        color([0, 0, 200]).
        width(1)

map.render

