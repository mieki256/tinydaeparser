#!ruby -Ku
# -*- mode: ruby; coding: utf-8 -*-
# Last updated: <2017/03/30 15:00:18 +0900>
#
# DXRuby 1.5.21dev以降で追加された CustomRenderTarget の動作確認
# 公式サンプル spheretest.rb を改造
# tinydaeparser.rb を使って COLLADA形式(.dae) を直接読んで使ってみる
#
# usage:
#   ruby dxruby_readdae.rb [0-7]
#
# DXRuby開発版の入手先
# Home - mirichi/dxruby-doc Wiki
# https://github.com/mirichi/dxruby-doc/wiki

require 'dxruby'
require 'json'
require 'pp'
require_relative '../tinydaeparser'

# モデルデータの頂点配列やシェーダを格納するクラス
class Material
  attr_accessor :vbuf0
  attr_accessor :vbuf1
  attr_accessor :vbuf2
  attr_accessor :vbuf3
  attr_accessor :shader
  attr_accessor :m

  # @return [true, false] テクスチャを使っているか否か
  attr_accessor :use_uv

  # @return [Image] テクスチャ画像
  attr_accessor :image

  # 描画用HLSL。テクスチャ使用版
  HLSL_USE_TEX = <<EOS
float4x4 mWorld;
float4x4 mView;
float4x4 mProj;
texture tex0;   // 使用テクスチャ
float4 vLight;  // 光源

sampler Samp = sampler_state
{
  Texture =<tex0>;
};

struct VS_INPUT
{
  float4 vPosition    : POSITION0;   // 頂点座標
  float4 vNormal      : NORMAL;      // 法線ベクトル
  float2 vTexCoords   : TEXCOORD0;   // テクスチャUV
  float4 vDiffuse     : COLOR0;      // デフューズ色
};

struct VS_OUTPUT
{
  float4 vPosition    : POSITION;    // 頂点座標
  float3 vNormal      : TEXCOORD2;   // 法線
  float2 vTexCoords   : TEXCOORD0;   // テクスチャUV
  float4 vDiffuse     : COLOR0;      // デフューズ色
};

VS_OUTPUT VS(VS_INPUT v)
{
  VS_OUTPUT output;

  output.vPosition = mul(mul(mul(v.vPosition, mWorld), mView), mProj);
  output.vNormal = mul(v.vNormal, mWorld).xyz;
  output.vDiffuse = v.vDiffuse;
  output.vTexCoords = v.vTexCoords;

  return output;
}

struct PS_INPUT
{
  float3 vNormal      : TEXCOORD2;   // 法線
  float4 vDiffuse     : COLOR0;      // デフューズ色
  float2 vTexCoords   : TEXCOORD0;   // テクスチャUV
};

struct PS_OUTPUT
{
  float4 vColor       : COLOR0;      // 最終的な出力色
};

PS_OUTPUT PS(PS_INPUT p)
{
  PS_OUTPUT output;
  float diffuse = max(dot(vLight, normalize(p.vNormal)), 0.0);
  float4 tcolor = tex2D( Samp, p.vTexCoords );
  output.vColor.rgb = tcolor * p.vDiffuse * diffuse + 0.1;
  output.vColor.a = 1;

  return output;
}

technique
{
  pass
  {
    VertexShader = compile vs_2_0 VS();
    PixelShader = compile ps_2_0 PS();
  }
}
EOS

  # 描画用HLSL。テクスチャ未使用版
  HLSL_NOT_USE_TEX = <<EOS
float4x4 mWorld, mView, mProj;
float4 vLight;  // 光源

struct VS_INPUT {
  float4 vPosition    : POSITION0;   // 頂点座標
  float4 vNormal      : NORMAL;      // 法線ベクトル
  float4 vDiffuse     : COLOR0;      // デフューズ色
};

struct VS_OUTPUT {
  float4 vPosition    : POSITION;    // 頂点座標
  float3 vNormal      : TEXCOORD2;   // 法線
  float4 vDiffuse     : COLOR0;      // デフューズ色
};

VS_OUTPUT VS(VS_INPUT v) {
  VS_OUTPUT output;
  output.vPosition = mul(mul(mul(v.vPosition, mWorld), mView), mProj);
  output.vNormal = mul(v.vNormal, mWorld).xyz;
  output.vDiffuse = v.vDiffuse;
  return output;
}

struct PS_INPUT {
  float3 vNormal      : TEXCOORD2;   // 法線
  float4 vDiffuse     : COLOR0;      // デフューズ色
};

struct PS_OUTPUT {
  float4 vColor       : COLOR0;      // 最終的な出力色
};

PS_OUTPUT PS(PS_INPUT p) {
  PS_OUTPUT output;
  float diffuse = max(dot(vLight, normalize(p.vNormal)), 0.0);
  output.vColor.rgb = p.vDiffuse * diffuse + 0.1;
  output.vColor.a = 1;
  return output;
}

technique {
  pass {
    VertexShader = compile vs_2_0 VS();
    PixelShader = compile ps_2_0 PS();
  }
}
EOS

  # initialize
  #
  # @param vertex [Array<Float>] 頂点座標配列
  # @param normal [Array<Float>] 法線ベクトル配列
  # @param uv [Array<Float>] uv座標配列
  # @param color [Array<Integer>] 頂点カラー配列
  # @param image [Image, nil] テクスチャ画像。nilならuvは使わない
  #
  def initialize(vertex: nil, normal: nil, uv: nil, color: nil, image: nil)
    @use_uv = (image != nil)? true : false
    @vertex = vertex
    @normal = normal
    @uv = uv
    @color = color
    @image = image

    if @use_uv
      # テクスチャ使用
      init_use_tex(@vertex, @normal, @uv, @color, @image)
    else
      # テクスチャ未使用
      init_not_use_tex(@vertex, @normal, @color)
    end
  end

  # テクスチャ使用時の初期化処理
  # @param vtx [Array<Float>] 頂点座標配列
  # @param nml [Array<Float>] 法線ベクトル配列
  # @param uv [Array<Float>] uv座標配列
  # @param col [Array<Integer>] 頂点カラー配列
  # @param img [Image] テクスチャ画像
  def init_use_tex(vtx, nml, uv, col, img)
    # Shader::Core生成
    @core = Shader::Core.new(HLSL_USE_TEX,
                             mWorld: :float,
                             mView: :float,
                             mProj: :float,
                             tex0: :texture,
                             vLight: :float,
                            )

    # 頂点座標、法線ベクトル、テクスチャ座標、頂点カラー用バッファ
    @vbuf0 = VertexBuffer.new([[D3DDECLTYPE_FLOAT3, D3DDECLUSAGE_POSITION, 0],])
    @vbuf1 = VertexBuffer.new([[D3DDECLTYPE_FLOAT3, D3DDECLUSAGE_NORMAL, 0],])
    @vbuf2 = VertexBuffer.new([[D3DDECLTYPE_FLOAT2, D3DDECLUSAGE_TEXCOORD, 0],])
    @vbuf3 = VertexBuffer.new([[D3DDECLTYPE_D3DCOLOR, D3DDECLUSAGE_COLOR, 0],])

    @vbuf0.vertices = vtx
    @vbuf1.vertices = nml
    @vbuf2.vertices = uv
    @vbuf3.vertices = col

    @m = Matrix.new
    @shader = Shader.new(@core)
    @shader.tex0 = img
  end

  # テクスチャ未使用時の初期化処理
  # @param vtx [Array<Float>] 頂点座標配列
  # @param nml [Array<Float>] 法線ベクトル配列
  # @param col [Array<Integer>] 頂点カラー配列
  def init_not_use_tex(vtx, nml, col)
    @core = Shader::Core.new(HLSL_NOT_USE_TEX,
                             mWorld: :float,
                             mView: :float,
                             mProj: :float,
                             vLight: :float,
                            )
    # 頂点座標、法線ベクトル、頂点カラー用バッファ
    @vbuf0 = VertexBuffer.new([[D3DDECLTYPE_FLOAT3, D3DDECLUSAGE_POSITION, 0],])
    @vbuf1 = VertexBuffer.new([[D3DDECLTYPE_FLOAT3, D3DDECLUSAGE_NORMAL, 0],])
    @vbuf2 = VertexBuffer.new([[D3DDECLTYPE_D3DCOLOR, D3DDECLUSAGE_COLOR, 0],])

    @vbuf0.vertices = vtx
    @vbuf1.vertices = nml
    @vbuf2.vertices = col

    @m = Matrix.new
    @shader = Shader.new(@core)
  end
end

# RenderTarget3Dクラス
class RenderTarget3D < CustomRenderTarget
  attr_accessor :view, :proj, :light

  def initialize(*)
    super
    @draw_data = []    # 描画予約的な配列
  end

  # CustomRenderTargetの描画メソッド
  def custom_render(o)
    o.set_viewport(0, 0, width, height, 0, 1)  # ビューポート設定

    o.begin_scene  # 描画開始

    # レンダーステート設定
    o.set_render_state(D3DRS_CULLMODE, D3DCULL_CW)
    o.set_render_state(D3DRS_ZENABLE, D3DZB_TRUE)
    o.set_render_state(D3DRS_ZWRITEENABLE, 1)  # bool値 TRUE=1, FALSE=0

    # 描画予約を順番に処理する
    @draw_data.each do |material|
      # シェーダパラメータ設定
      material.shader.mWorld = material.m
      material.shader.mView = @view
      material.shader.mProj = @proj
      material.shader.vLight = @light

      if material.use_uv
        # テクスチャ使用
        # シェーダパラメータのDirectXへの設定など面倒なことはusing_shaderがやってくれる
        o.using_shader(material.shader) do
          # 頂点バッファは複数指定できる
          o.set_stream(
            material.vbuf0,
            material.vbuf1,
            material.vbuf2,
            material.vbuf3
          )
          o.draw_primitive(D3DPT_TRIANGLELIST, material.vbuf0.vertex_count / 3)
        end
      else
        # テクスチャ未使用
        o.using_shader(material.shader) do
          o.set_stream(
            material.vbuf0,
            material.vbuf1,
            material.vbuf2
          )
          o.draw_primitive(D3DPT_TRIANGLELIST, material.vbuf0.vertex_count / 3)
        end
      end
    end

    o.end_scene       # 描画終了
    @draw_data.clear  # 描画予約のクリア
  end

  # 描画予約
  # @param material [Object] 描画したいモデル
  def draw(material)
    @draw_data << material
  end
end

# ----------------------------------------
# initialize

modelkind = 1
modelkind = ARGV[0].to_i unless ARGV.empty?

# テクスチャ画像ファイル名
TEXTURE_FILE = "../sampledata/uvchecker512.png"

# モデルデータファイル名
MODEL_FILE = [
  "../sampledata/plane_uv_vcol.dae",  # 0 : テクスチャ、頂点カラー使用
  "../sampledata/uv_vcol.dae",        # 1 : テクスチャ、頂点カラー使用
  "../sampledata/uv_novcol.dae",      # 2 : テクスチャ使用
  "../sampledata/nouv_novcol.dae",    # 3 : テクスチャ、頂点カラー未使用
  "../sampledata/animal.dae",         # 4 : テクスチャ、頂点カラー未使用
  "../sampledata/landscape.dae",      # 5 : テクスチャ使用
  "../sampledata/w3d_uv_vcol.dae",    # 6 : テクスチャ、頂点カラー使用
  "../sampledata/w3d_nouv_vcol.dae",  # 7 : 頂点カラー使用
]

# モデルデータを読み込み
o = TinyDaeParser.new(MODEL_FILE[modelkind], dxruby: true)

vtx = o.get_vertex_array  # 頂点座標配列を取得
nml = o.get_normal_array  # 法線ベクトル配列を取得
uv  = o.get_uv_array      # UV座標配列を取得
col = o.get_color_array   # 頂点カラー配列を取得

matnames = o.get_material_name_list  # マテリアル名リストを取得
matname = matnames[0]  # 仮で一番最初のマテリアルのみ使う
matdata = o.get_material_data(matname)  # マテリアル情報取得
# pp matdata

# テクスチャ画像読み込み
img = (o.use_uv)? Image.load(TEXTURE_FILE) : nil

# モデルデータクラスを生成
material = Material.new(vertex: vtx, normal: nml,
                        uv: uv, color: col,
                        image: img)

# 画面サイズ
Window.resize(640, 480)
Window.bgcolor = [64, 96, 128]  # background color R,G,B

# RenderTarget3Dオブジェクト生成
rt3d = RenderTarget3D.new(Window.width, Window.height)

rt3d.view = Matrix.look_at(
  Vector.new(0, 0, -6.0),  # 視点位置
  Vector.new(0, 0, 0),   # 注視座標
  Vector.new(0, 1, 0)    # 上方向
)

rt3d.proj = Matrix.projection_fov(
  60.0,   # 視野角
  Window.width.to_f / Window.height, # 画面比
  0.5,    # near clip
  1000.0  # far clip
)

rt3d.light = Vector.new(0.5, 0.5, -1).normalize

# 事前にモデルをx軸で回転させておく
# material.m = material.m * Matrix.rotation_x(-30)

fnt = Font.new(12)

# メインループ
Window.loop do
  break if Input.keyPush?(K_ESCAPE)

  # ライト位置をマウス座標を使って算出かつ設定
  x = Input.mouse_x.fdiv(Window.width/2) - 1
  y = -(Input.mouse_y.fdiv(Window.height/2) - 1)
  rt3d.light = Vector.new(x, y, -1).normalize

  # マテリアル(モデルデータ)を回転
  material.m = material.m * Matrix.rotation_x(0.2)
  material.m = material.m * Matrix.rotation_y(0.5)

  rt3d.draw(material)      # RenderTarget3Dにモデルを描画
  Window.draw(0, 0, rt3d)  # 画面に描画

  # FPSを描画
  Window.drawFont(4, 4, sprintf("%02d fps", Window.fps), fnt)
end
