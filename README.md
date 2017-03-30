TinyDaeParser
=============

COLLADA形式(.dae)の3Dモデルデータを読み込んでテキスト出力するRubyスクリプト。

Description
-----------

[COLLADA形式(.dae)](https://ja.wikipedia.org/wiki/COLLADA) の3Dモデルデータファイルを簡易解析して、DXRuby や Gosu + OpenGL 等から使いやすい形式でテキスト出力します。

全属性には対応していませんが、3D描画関係の実験用モデルデータを用意する、ぐらいのことには使えるんじゃないかなと…。

Demo
----

[tinydaeparser rb demo - YouTube](https://youtu.be/NFcjUXSUZW0)

Usage
-----

### 使用可能なオプション

    ruby tinydaeparser.rb --help

    Usage : ruby tinydaeparser.rb INFILE.obj [options]
            --[no-]index                 use vertex index
        -x, --xflip                      x flip
        -y, --yflip                      y flip
        -z, --zflip                      z flip
            --[no-]vflip                 v flip
            --[no-]color                 forced use of vertex color
            --hexcolor                   color code 0xAARRGGBB
            --json                       output json format
            --dxruby                     set --no-index --vflip --hexcolor
            --debug                      dump .obj information

### Rubyソース内に書ける形で出力

    ruby tinydaeparser.rb sampledata/uv_vcol.dae

### jsonで出力

    ruby tinydaeparser.rb sampledata/uv_vcol.dae --json

### 出力したjsonを読み込んで利用

    require 'json'
    ...
    vertex_array  = nil
    normal_array  = nil
    uv_array      = nil
    color_array   = nil

    File.open("sample.json") { |file|
      hash = JSON.load(file)
      vertex_array = hash["vertex"]
      normal_array = hash["normal"]  if hash.key?("normal")
      uv_array     = hash["uv"]      if hash.key?("uv")
      color_array  = hash["color"]   if hash.key?("color")  # vertex color
    }

### Rubyソース内で利用して頂点配列等を取得(DXRuby用)

    require_relative 'tinydaeparser'
    ...
    o = TinyDaeParser.new("sampledata/uv_vcol.dae", dxruby: true)
    vertex_array   = o.get_vertex_array
    normal_array   = o.get_normal_array
    uv_array       = o.get_uv_array
    color_array    = o.get_color_array   # vertex color
    material_names = o.get_material_name_list
    matname        = material_names[0]
    material_data  = o.get_material_data(matname)
    ...
    puts "use normal"  if o.use_normal
    puts "use texture" if o.use_uv
    puts "use color"   if o.use_color

Testing environment
-------------------

Ruby 2.2.6 p396 mingw32 + Windows10 x64

Licence
-------

tinydaeparser.rb : CC0 / Public Domain
sampledata/*.* : CC0 / Public Domain

Author
------

mieki256

サンプルデータについて
----------------------

### blenderからエクスポートしたデータ

* plane_uv_vcol.dae : テクスチャ、頂点カラー使用。
* uv_vcol.dae : テクスチャ、頂点カラー使用。
* uv_novcol.dae : テクスチャ使用。頂点カラー未使用。
* nouv_novcol.dae : テクスチャ、頂点カラー未使用。
* animal.dae : テクスチャ、頂点カラー未使用。
* landscape.dae : テクスチャ使用。頂点カラー未使用。

### Wings 3Dからエクスポートしたデータ

* w3d_uv_vcol.dae : テクスチャ、頂点カラー使用。
* w3d_nouv_vcol.dae : テクスチャ、頂点カラー使用。

### 座標系について補足

TinyDaeParser 内で下記の設定は自動的に行われるので特に指定する必要無し。daeファイルのヘッダー部分を見て、blender から出力されたか、Wings 3D から出力されたかを調べて、座標の交換や反転をしている。

#### blenderの座標系

* blender の座標系は、右が +X、上が +Z、前が -Y。
* エクスポートしたdaeファイルには Z_UP の指定が含まれる。
* OpenGLで使うなら、z値反転、及び、UV の v値を反転させて使う。
* DXRuby(DircetX)で使うなら、z値はそのまま、UV の v値を反転させて使う。

#### Wings 3Dの座標系

* Wings 3D の座標系は、右が +X、上が +Y、前が +Z。
* エクスポートしたdaeファイルには Y_UP の指定が含まれる。
* OpenGLで使うなら、z値はそのまま、UV の v値を反転させて使う。
* DXRubyで使うなら、z値反転、及び、UV の v値を反転させて使う。

#### Wings 3D からdaeをエクスポートする際の注意点

* エクスポート時の単位は「m(メートル)」を選択。
* エクスポート時のオプション指定に「三角形化」は存在しないので、あらかじめモデルデータそのものを「テッセレート」を使って三角形化しておく必要がある。
* diffuseの設定値は COLLADA形式(.dae)に含まれない。

Wings 3D はエクスポート時の謎仕様やバグが多いので、Wings 3D からエクスポートした .dae を一旦 blender でインポートして調整後、blender から .dae をエクスポートし直して使ったほうがハマりにくい、かもしれない。
