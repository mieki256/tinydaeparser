#!ruby
# -*- mode: ruby; coding: utf-8 -*-
# Last updated: <2017/03/25 23:32:06 +0900>
#
# TinyDaeParser
#
# COLLADA (.dae) tiny parser
#
# testing environment : Ruby 2.2.6 p396 mingw32
# License : CC0 / Public Domain

Version = "1.0.0"

require 'rexml/document'
require 'pp'
require 'optparse'
require 'json'

class TinyDaeParser

  # return [true, false] use vertex data
  attr_accessor :use_vertex

  # return [true, false] use normal data
  attr_accessor :use_normal

  # return [true, false] use uv data
  attr_accessor :use_uv

  # return [true, false] use vertex color data
  attr_accessor :use_color

  # return [Hash] vertex position, normal vector, uv, etc
  attr_accessor :source

  # return [Hash] polygon data
  attr_accessor :polylist

  # return [Hash] material data
  attr_accessor :materials

  # return [Integer] face count
  attr_accessor :face_count

  # return [Integer] vertex count
  attr_accessor :vertex_count

  # initialize
  #
  # @param daepath [String] .dae file path
  # @param use_index [true, false] use vertex index
  # @param use_color_force [true, false] make vertex colors from material
  # @param vflip [true, false] v flip of u,v
  # @param zflip [true, false] z flip
  # @param hexcolor [true, false] color code 0xAARRGGBB
  # @param add_alpha [true, false] RGB to RGBA. A = 1.0
  # @param dxruby [true, false] for DXRuby
  # @param xyzmul [Array<Float>] x,y,z flip
  def initialize(daepath,
                 use_index: true,
                 use_color_force: false,
                 vflip: true,
                 zflip: false,
                 hexcolor: false,
                 add_alpha: false,
                 dxruby: false,
                 xyzmul: [1.0, 1.0, 1.0],
                 debug: false)

    @dbg = debug

    @daepath = daepath
    @xyzmul = xyzmul
    @use_index = use_index
    @use_color_force = use_color_force
    @vflip = vflip
    @hexcolor = hexcolor
    @add_alpha = add_alpha

    @use_vertex = false
    @use_normal = false
    @use_uv = false
    @use_color = false

    @material_hash = {}
    @effects = {}
    @materials = {}
    @source = {}
    @polylist = {}
    @face_count = 0
    @vertex_count = 0

    @dae_text = File.read(@daepath)
    @doc = REXML::Document.new(@dae_text)

    assettag = @doc.elements["COLLADA/asset"]
    @z_up = (assettag.elements["up_axis"].text == "Z_UP")? true : false
    @authoring_tool = assettag.elements["contributor/authoring_tool"].text
    if @authoring_tool =~ /^Blender/
      @authoring_tool = "Blender"
    elsif @authoring_tool =~ /^Wings3D/
      @authoring_tool = "Wings3D"
    else
      @authoring_tool = "Unknown"
    end

    if dxruby
      @use_index = false
      @use_color_force = true
      @vflip = true
      @hexcolor = true
      zflip = true if @authoring_tool == "Wings3D"
    else
      zflip = true unless @authoring_tool == "Wings3D"
    end

    if zflip and @xyzmul == [1.0, 1.0, 1.0]
      @xyzmul[2] = -1.0
    end

    parse_libeffects(@doc)
    parse_libmaterials(@doc)
    parse_source(@doc)
    parse_face_list(@doc)
    parse_geom(@doc)

    make_vertex_array
  end

  def parse_libeffects(doc)
    efc = doc.elements["COLLADA/library_effects"]

    @effects = {}
    efc.elements.each("effect") do |e|
      id = e.attributes["id"]

      tech = e.elements["profile_COMMON/technique"]
      reflect = tech.elements.first.name  # phong, lambert
      pg = tech.elements[reflect]

      case reflect
      when "phong"
        specular = pg.elements["specular/color"].text.split(" ").map { |v| v.to_f }
        shininess = pg.elements["shininess/float"].text.to_f
        if shininess > 0.0 and shininess < 1.0
          # maybe the .dae exported Wings 3D. convert 1.0 to 128.0
          shininess *= 128.0
        end
      when "lambert"
        specular = [0.0, 0.0, 0.0, 1.0]
        shininess = 0.0
      else
        puts "Error : Unknonw reflection. [#{reflect}]"
      end

      emission = pg.elements["emission/color"].text.split(" ").map { |v| v.to_f }
      ambient = pg.elements["ambient/color"].text.split(" ").map { |v| v.to_f }

      diffuse_tag = pg.elements["diffuse"]
      diffuse_first = diffuse_tag.elements.first
      if diffuse_first.name == "color"
        diffuse = diffuse_first.text.split(" ").map { |v| v.to_f }
      else
        # maybe exported Wings 3D
        diffuse = [1.0, 1.0, 1.0, 1.0]
      end


      @effects[id] = {
        :reflection => reflect,
        :emission => emission,
        :ambient => ambient,
        :diffuse => diffuse,
        :specular => specular,
        :shininess => shininess
      }
    end

    # pp @effects
  end

  def parse_libmaterials(doc)
    mats = doc.elements["COLLADA/library_materials"]

    @materials = {}
    mats.elements.each("material") do |mat|
      id = mat.attributes["id"]
      name = mat.attributes["name"]
      instance_effect = mat.elements["instance_effect"]
      url = instance_effect.attributes["url"].gsub(/^\#/, "")
      @materials[id] = {
        :id => id,
        :name => name,
        :url => url
      }
    end

    @materials.each do |matname, v|
      id = v[:url]
      if @effects.key?(id)
        @materials[matname][:reflection] = @effects[id][:reflection]
        @materials[matname][:emission] = @effects[id][:emission]
        @materials[matname][:ambient] = @effects[id][:ambient]
        @materials[matname][:diffuse] = @effects[id][:diffuse]
        @materials[matname][:specular] = @effects[id][:specular]
        @materials[matname][:shininess] = @effects[id][:shininess]
      else
        puts "Error : Not found #{id}"
      end
    end
  end

  def parse_source(doc)
    geo = doc.elements["COLLADA/library_geometries/geometry/mesh"]

    @source = {}
    geo.elements.each("source") do |src|
      id = src.attributes["id"]
      float_array = src.elements["float_array"]
      fcount = float_array.attributes["count"].to_i
      a = float_array.text.split(" ").map { |v| v.to_f }
      tech = src.elements["technique_common/accessor"]
      stride = tech.attributes["stride"].to_i
      tcount = tech.attributes["count"].to_i
      data = []
      (a.size / stride).times do |j|
        d = []
        stride.times { |i| d.push(a[j * stride + i]) }
        data.push(d)
      end

      @source[id] = {
        :data => [],
        :data_org => data,
        :data_text => float_array.text,
        :stride => stride,
        :count => fcount,
        :tcount => tcount
      }
    end
  end

  def dump_source
    puts "\# source"
    puts "\# " + ("-" * 40)
    pp @source
    puts
  end

  def parse_face_list(doc)
    geo = doc.elements["COLLADA/library_geometries/geometry/mesh"]

    @polylist = {}
    geo.elements.each("polylist") do |poly|
      matname = poly.attributes["material"]
      polycount = poly.attributes["count"].to_i

      flag = {}
      tn = 0
      poly_input = {}
      poly.elements.each("input") do |inp|
        sem = inp.attributes["semantic"]
        source = inp.attributes["source"].gsub(/^\#/, "")
        ofs = inp.attributes["offset"].to_i
        poly_input[ofs] = {
          :semntic => sem,
          :source => source
        }
        flag[sem] = true

        case sem
        when "VERTEX" then @use_vertex = true
        when "NORMAL" then @use_normal = true
        when "TEXCOORD" then @use_uv = true
        when "COLOR" then @use_color = true
        end

        tn += 1
      end

      vcount = poly.elements["vcount"].text.split(" ").map { |v| v.to_i }
      plst_text = poly.elements["p"].text
      plst = plst_text.split(" ").map { |v| v.to_i }

      vdata = []
      idx = 0
      vcount.each do |vcnt|
        vdt = []
        vcnt.times do |j|
          t = []
          tn.times { t.push(plst.shift) }
          vdt.push(t)
        end
        vdata.push(vdt)
      end

      @polylist[matname] = {
        :material_id => matname,
        :use_flag => flag,
        :input => poly_input,
        :face_count => polycount,
        :vertex_count => vcount,
        :vertex_indexs => vdata,
        :vertex_indexs_text => plst_text,
        :material => @materials[matname],
      }
    end
  end

  def dump_polylist
    puts "\# polylist"
    puts "\# " + ("-" * 40)
    pp @polylist
    puts
  end

  def parse_geom(doc)
    geo = doc.elements["COLLADA/library_geometries/geometry/mesh"]

    vtx_pos = geo.elements["vertices"]
    vtx_pos_id = vtx_pos.attributes["id"]
    vtx_pos_input = vtx_pos.elements["input"]
    vtx_pos_name = vtx_pos_input.attributes["source"].gsub(/^\#/, "")
    @polylist.each do |matname, poly|
      poly[:input].each do |k, v|
        v[:source] = vtx_pos_name if v[:source] == vtx_pos_id
      end
    end

    @polylist.each do |matname, poly|
      poly[:input].each do |k, v|
        src_name = v[:source]
        if @source.key?(src_name)
          @source[src_name][:semntic] = v[:semntic]
        else
          puts "Error : not found source ID [#{src_name}]"
        end
      end
    end

    @source.each do |src_name, v|
      sem = v[:semntic]
      src_data = v[:data_org]
      case sem
      when "VERTEX"
        dst = get_mul_xyz((@z_up)? swap_y_z(src_data) : src_data)
        @source[src_name][:data] = dst
      when "NORMAL"
        dst = get_mul_xyz((@z_up)? swap_y_z(src_data) : src_data)
        @source[src_name][:data] = dst
      when "TEXCOORD"
        @source[src_name][:data] = (@vflip)? swap_v(src_data) : src_data
      when "COLOR"
        @source[src_name][:data] = src_data
      else
        puts "Error : Unknown semntic in source. [#{sem}]"
      end
    end
  end

  def swap_y_z(src)
    dst = []
    src.each do |v|
      x, y, z = v
      dst.push([x, z, y])
    end
    return dst
  end

  def get_mul_xyz(src)
    dst = []
    src.each do |v|
      x, y, z = v
      x *= @xyzmul[0]
      y *= @xyzmul[1]
      z *= @xyzmul[2]
      dst.push([x, y, z])
    end
    return dst
  end

  def swap_v(src)
    dst = []
    src.each do |uv|
      dst.push([uv[0], (1.0 - uv[1])])
    end
    return dst
  end

  def make_vertex_array
    @face_count = 0
    @vertex_count = 0
    @polylist.each do |matname, poly|
      vtx = []
      nml = []
      uv = []
      col = []
      inp = poly[:input]
      idxs = poly[:vertex_indexs]
      idxs.each do |face|
        face.each do |vtxidxs|
          vtxidxs.each_with_index do |n, ofs|
            src_name = inp[ofs][:source]
            sem = inp[ofs][:semntic]
            v = @source[src_name][:data][n]
            case sem
            when "VERTEX" then vtx.push(v)
            when "NORMAL" then nml.push(v)
            when "TEXCOORD" then uv.push(v)
            when "COLOR" then col.push(v)
            end
          end
        end
      end
      @polylist[matname][:vertex_array] = vtx
      @polylist[matname][:normal_array] = nml
      @polylist[matname][:uv_array] = uv
      @polylist[matname][:color_array] = get_col(col)

      if col.empty? and @use_color_force
        # diffuse material of face is used as vertex color
        r, g, b = @materials[matname][:diffuse]
        vtx.size.times { col.push([r, g, b]) }
        @polylist[matname][:color_array] = get_col(col)
        @use_color = true
      end

      vcount = poly[:vertex_count]
      @face_count += vcount.size
      @vertex_count += vcount.inject { |sum, n| sum + n }
    end
  end

  def get_col(col)
    return col unless @add_alpha
    ncol = []
    col.each { |c| ncol.push([c[0], c[1], c[2], 1.0]) }
    return ncol
  end

  # get vertex array. not use vertex index
  # @return [Array<Float>] vertex array
  def get_vertex_array
    return nil unless @use_vertex
    a = []
    @polylist.each_value { |poly| a.push(poly[:vertex_array]) }
    return a.flatten
  end

  # get normal array. not use vertex index
  # @return [Array<Float>] normal array
  # @return [nil] normal unused
  def get_normal_array
    return nil unless @use_normal
    a = []
    @polylist.each_value { |poly| a.push(poly[:normal_array]) }
    return a.flatten
  end

  # get uv array. not use vertex index
  # @return [Array<Float>] uv array
  # @return [nil] uv unused
  def get_uv_array
    return nil unless @use_uv
    a = []
    @polylist.each_value { |poly| a.push(poly[:uv_array]) }
    return a.flatten
  end

  # get vertex color array (1byte). not use vertex index
  # @return [Array<Integer>] vertex color array
  # @return [nil] vertex color unused
  def get_color_array
    return nil unless @use_color
    return get_hexcolor_array if @hexcolor
    a = []
    @polylist.each_value { |poly| a.push(poly[:color_array]) }
    return a.flatten
  end

  # get vertex color array (hex). not use vertex index
  # @return [Array<Integer>] vertex color array (0xAARRGGBB)
  # @return [nil] vertex color unused
  def get_hexcolor_array
    a = []
    @polylist.each_value { |poly| a.concat(poly[:color_array]) }
    dst = []
    a.each do |rgb|
      r, g, b = rgb
      dst.push(get_hexcolor(r, g, b, 1.0))
    end
    return dst
  end

  # get vertex array data
  # @return [Hash<Array>] vertex array data (not use vertex index)
  def get_vertex_array_data
    dt = {}
    dt["vertex"] = get_vertex_array
    dt["normal"] = get_normal_array if @use_normal
    dt["uv"] = get_uv_array if @use_uv
    if @use_color
      dt["color"] = (@hexcolor)? get_hexcolor_array : get_color_array
    end
    return dt
  end

  # get material name list
  # @return [Array<String>] material name list
  def get_material_name_list
    return @polylist.keys
  end

  # get material data
  # @param matname [String] material name
  # @return [Hash] material data
  def get_material_data(matname)
    return @materials[matname]
  end

  def iclamp(v, minv, maxv)
    return minv if v < minv
    return maxv if v > maxv
    return v
  end

  def get_8bit_color(r, g, b, a)
    a = iclamp((255 * a).to_i, 0, 255)
    r = iclamp((255 * r).to_i, 0, 255)
    g = iclamp((255 * g).to_i, 0, 255)
    b = iclamp((255 * b).to_i, 0, 255)
    return [r, g, b, a]
  end

  def get_hexcolor(r, g, b, a)
    a = iclamp((255 * a).to_i, 0, 255)
    r = iclamp((255 * r).to_i, 0, 255)
    g = iclamp((255 * g).to_i, 0, 255)
    b = iclamp((255 * b).to_i, 0, 255)
    return ((a << 24) + (r << 16) + (g << 8) + b)
  end

  def dump_vertex_array(use_format = "raw")
    case use_format
    when "json"
      puts get_vertex_array_json
    else
      puts get_vertex_array_raw
    end
  end

  def get_vertex_array_json(pretty = false)
    dt = get_vertex_array_data
    return ((pretty)? JSON.pretty_generate(dt) : JSON.generate(dt))
  end

  def get_vertex_array_raw
    s = []
    s.push("\# " + ("-" * 40))
    s.concat(get_array_str(get_vertex_array, "@vertex = [", 3))
    s.concat(get_array_str(get_normal_array, "@normal = [", 3))
    s.concat(get_array_str(get_uv_array, "@uv = [", 2)) if @use_uv

    if @use_color
      if @hexcolor
        s.concat(get_array_str(get_hexcolor_array, "@color = [", 1))
      else
        s.concat(get_array_str(get_color_array, "@color = [", 3))
      end
    end

    return s.join("\n")
  end

  def get_array_str(a, title, sz)
    s = []
    s.push(title)
    spc = " " * (title.size)
    if sz == 3
      (a.size / sz).times do |i|
        x, y, z = a[(i * sz)..(i * sz + (sz - 1))]
        s.push("#{spc}[#{x}, #{y}, #{z}],  \# #{i}")
      end
    elsif sz == 2
      (a.size / sz).times do |i|
        x, y, z = a[(i * sz)..(i * sz + (sz - 1))]
        s.push("#{spc}[#{x}, #{y}],  \# #{i}")
      end
    elsif sz == 1
      a.size.times do |i|
        s.push("#{spc}#{a[i]},  \# #{i}")
      end
    end
    s.push((" " * (title.size - 1)) + "]")
    s.push("")
    return s
  end

  def self.parse_options(argv)

    opts = {
      :index => false,
      :xflip => false,
      :yflip => false,
      :zflip => false,
      :vflip => true,
      :color => false,
      :hexcolor => false,
      :json => false,
      :dxruby => false,
      :debug => false,
    }

    OptionParser.new do |opt|
      opt.banner = "Usage : ruby #{$0} INFILE.obj [options]"
      opt.on("--[no-]index", "use vertex index") { |v| opts[:index] = v }
      opt.on("-x", "--xflip", "x flip") { |v| opts[:xflip] = v }
      opt.on("-y", "--yflip", "y flip") { |v| opts[:yflip] = v }
      opt.on("-z", "--zflip", "z flip") { |v| opts[:zflip] = v }
      opt.on("--[no-]vflip", "v flip") { |v| opts[:vflip] = v }
      opt.on("--[no-]color", "forced use of vertex color") { |v| opts[:color] = v }
      opt.on("--hexcolor", "color code 0xAARRGGBB") { |v| opts[:hexcolor] = v }
      opt.on("--json", "output json format") { |v| opts[:json] = v }
      opt.on("--dxruby", "set --no-index --vflip --hexcolor") { |v| opts[:dxruby] = v }
      opt.on("--debug", "dump .obj information") { |v| opts[:debug] = v }

      begin
        opt.parse!(argv)
      rescue
        abort "Invalid option. \n#{opt}"
      end

      unless argv.empty?
        if argv[0] =~ /\.dae$/i
          opts[:infile] = argv.shift
        end
        abort "Invalid option. \n#{opt}" unless argv.empty?
      end

      abort "Not found .dae file. \n#{opt}" unless opts.key?(:infile)

      if opts[:dxruby]
        opts[:index] = false
        opts[:vflip] = true
        opts[:hexcolor] = true
      end

      xyzmul = [
        ((opts[:xflip])? -1.0 : 1.0),
        ((opts[:yflip])? -1.0 : 1.0),
        ((opts[:zflip])? -1.0 : 1.0),
      ]
      opts[:xyzmul] = xyzmul

      return opts
    end
  end
end

# ----------------------------------------
if $0 == __FILE__
  opts = TinyDaeParser.parse_options(ARGV)
  o = TinyDaeParser.new(opts[:infile],
                        use_index: opts[:index],
                        use_color_force: opts[:color],
                        dxruby: opts[:dxruby],
                        vflip: opts[:vflip],
                        hexcolor: opts[:hexcolor],
                        xyzmul: opts[:xyzmul],
                        debug: opts[:debug])
  if opts[:debug]
    o.dump_source
    o.dump_polylist
  else
    fmt = "raw"
    fmt = "json" if opts[:json]
    o.dump_vertex_array(fmt)
  end
end
