  [[FX]]


  [[VS]]
#version 410

  #include "shaders/utilityLib/vertCommon.glsl"

  const vec3 color_array[8] = vec3[8](
      vec3(1.0, 1.0, 1.0),
      vec3(1.0, 0.0, 0.0),
      vec3(0.0, 1.0, 0.0),
      vec3(0.0, 0.0, 1.0),
      vec3(1.0, 1.0, 0.0),
      vec3(0.0, 1.0, 1.0),
      vec3(0.3, 0.8, 0.3),
      vec3(1.0, 0.0, 1.0)
  );

  uniform mat4 viewProjMat;
  uniform float gridId;

  in vec3 vertPos;

  out vec3 col;

  void main(void)
  {
    vec4 pos = calcWorldPos(vec4(vertPos, 1.0));
    col = color_array[int(gridId)];
    gl_Position = viewProjMat * pos;
  }


  [[FS]]
#version 410
out vec4 fragColor;

  in vec3 col;
  void main(void)
  {
    fragColor = vec4(col, 1.0);
  }
