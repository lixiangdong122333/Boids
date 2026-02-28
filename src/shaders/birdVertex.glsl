// Bird vertex shader
// Reads GPGPU position/velocity textures to transform instanced cone geometry
// Builds rotation matrix from velocity direction so cone tip faces flight direction

uniform sampler2D uTexturePosition;
uniform sampler2D uTextureVelocity;

attribute vec2 reference;  // UV into GPGPU textures per instance

varying vec3 vNormal;
varying vec3 vWorldPosition;
varying vec3 vColor;

void main() {
  // Read GPGPU data for this instance
  vec3 birdPos = texture2D(uTexturePosition, reference).xyz;
  vec3 birdVel = texture2D(uTextureVelocity, reference).xyz;

  float speed = length(birdVel);
  vec3 forward = speed > 0.001 ? normalize(birdVel) : vec3(0.0, 0.0, 1.0);

  // Build orthonormal basis from velocity direction
  // ConeGeometry default tip points along +Y, so we rotate from +Y to forward
  vec3 up = vec3(0.0, 1.0, 0.0);

  // Handle near-parallel case
  if (abs(dot(forward, up)) > 0.999) {
    up = vec3(0.0, 0.0, 1.0);
  }

  vec3 right = normalize(cross(forward, up));
  vec3 newUp = cross(right, forward);

  // Rotation matrix: columns are right, forward, newUp
  // Maps +Y (cone tip) -> forward (flight direction)
  mat3 rotMat = mat3(
    right,       // new X
    forward,     // new Y (cone tip direction)
    newUp        // new Z
  );

  // Scale bird based on speed for visual flair
  float scale = 0.8 + 0.4 * smoothstep(0.0, 50.0, speed);

  // Transform vertex
  vec3 transformed = rotMat * (position * scale) + birdPos;

  // Normal transformation
  vNormal = normalize(rotMat * normal);
  vWorldPosition = transformed;

  // Color variation based on instance reference and speed
  float hue = reference.x * 0.3 + reference.y * 0.7;
  float speedFactor = smoothstep(0.0, 80.0, speed);

  // Warm sunset palette: orange -> magenta -> blue-violet
  vec3 colorA = vec3(1.0, 0.45, 0.15);  // warm orange
  vec3 colorB = vec3(0.7, 0.2, 0.8);    // purple
  vec3 colorC = vec3(0.2, 0.5, 1.0);    // blue
  vColor = mix(mix(colorA, colorB, hue), colorC, speedFactor * 0.5);

  gl_Position = projectionMatrix * modelViewMatrix * vec4(transformed, 1.0);
}
