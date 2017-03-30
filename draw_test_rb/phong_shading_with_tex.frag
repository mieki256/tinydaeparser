#version 120

// phong_shading_with_tex.frag

uniform sampler2D texture;

varying vec4 position;
varying vec3 normal;

void main (void)
{
  vec4 tcolor = texture2DProj(texture, gl_TexCoord[0]);
  vec3 light = normalize((gl_LightSource[0].position * position.w - gl_LightSource[0].position.w * position).xyz);
  vec3 fnormal = normalize(normal);
  float diffuse = max(dot(light, fnormal), 0.0);

  vec3 view = -normalize(position.xyz);
  vec3 halfway = normalize(light + view);
  float specular = pow(max(dot(fnormal, halfway), 0.0), gl_FrontMaterial.shininess);

  gl_FragColor = gl_Color * tcolor
    * (gl_LightSource[0].diffuse * gl_FrontMaterial.diffuse * diffuse
       + gl_LightSource[0].ambient * gl_FrontMaterial.ambient)
    + gl_LightSource[0].specular * gl_FrontMaterial.specular * specular;

  /* gl_FragColor = gl_Color * tcolor * (gl_LightSource[0].diffuse * diffuse + gl_LightSource[0].ambient) */
  /*   + gl_FrontLightProduct[0].specular * specular; */
}
