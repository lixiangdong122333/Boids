// Position compute shader
// Reads current position and adds velocity * delta to produce new position

uniform float uDelta;

void main() {
  vec2 uv = gl_FragCoord.xy / resolution.xy;

  vec4 posData = texture2D(texturePosition, uv);
  vec4 velData = texture2D(textureVelocity, uv);

  vec3 pos = posData.xyz;
  vec3 vel = velData.xyz;

  pos += vel * uDelta;

  gl_FragColor = vec4(pos, posData.w);
}
