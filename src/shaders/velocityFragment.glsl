// Velocity compute shader — Boids algorithm
// Uses stride-sampling to avoid O(N²): samples ~300 neighbors from the texture
// Includes curl-noise turbulence for organic, shape-shifting flock dynamics

uniform float uDelta;
uniform float uTime;
uniform float uSeparationWeight;
uniform float uAlignmentWeight;
uniform float uCohesionWeight;
uniform float uMaxSpeed;
uniform float uPerceptionRadius;
uniform float uBoundaryRadius;
uniform float uSeparationRadius;
uniform float uTurbulence;

// Stride-sampling constants
const float TEXTURE_WIDTH = resolution.x;
const float TEXTURE_HEIGHT = resolution.y;
const float TOTAL_PARTICLES = TEXTURE_WIDTH * TEXTURE_HEIGHT;
const int MAX_SAMPLES = 300;

// ── Pseudo-random hash functions for GPU noise ──
vec3 hash3(vec3 p) {
  p = vec3(
    dot(p, vec3(127.1, 311.7, 74.7)),
    dot(p, vec3(269.5, 183.3, 246.1)),
    dot(p, vec3(113.5, 271.9, 124.6))
  );
  return -1.0 + 2.0 * fract(sin(p) * 43758.5453123);
}

// 3D gradient noise
float noise3D(vec3 p) {
  vec3 i = floor(p);
  vec3 f = fract(p);
  vec3 u = f * f * (3.0 - 2.0 * f);

  return mix(
    mix(mix(dot(hash3(i + vec3(0,0,0)), f - vec3(0,0,0)),
            dot(hash3(i + vec3(1,0,0)), f - vec3(1,0,0)), u.x),
        mix(dot(hash3(i + vec3(0,1,0)), f - vec3(0,1,0)),
            dot(hash3(i + vec3(1,1,0)), f - vec3(1,1,0)), u.x), u.y),
    mix(mix(dot(hash3(i + vec3(0,0,1)), f - vec3(0,0,1)),
            dot(hash3(i + vec3(1,0,1)), f - vec3(1,0,1)), u.x),
        mix(dot(hash3(i + vec3(0,1,1)), f - vec3(0,1,1)),
            dot(hash3(i + vec3(1,1,1)), f - vec3(1,1,1)), u.x), u.y),
    u.z);
}

// Curl noise: divergence-free turbulence field
vec3 curlNoise(vec3 p) {
  float e = 0.1;
  float n1, n2;

  // partial derivatives via central differences
  n1 = noise3D(p + vec3(0, e, 0));
  n2 = noise3D(p - vec3(0, e, 0));
  float a = (n1 - n2) / (2.0 * e);

  n1 = noise3D(p + vec3(0, 0, e));
  n2 = noise3D(p - vec3(0, 0, e));
  float b = (n1 - n2) / (2.0 * e);

  n1 = noise3D(p + vec3(e, 0, 0));
  n2 = noise3D(p - vec3(e, 0, 0));
  float c = (n1 - n2) / (2.0 * e);

  n1 = noise3D(p + vec3(0, 0, e));
  n2 = noise3D(p - vec3(0, 0, e));
  float d = (n1 - n2) / (2.0 * e);

  n1 = noise3D(p + vec3(0, e, 0));
  n2 = noise3D(p - vec3(0, e, 0));
  float ee = (n1 - n2) / (2.0 * e);

  n1 = noise3D(p + vec3(e, 0, 0));
  n2 = noise3D(p - vec3(e, 0, 0));
  float f = (n1 - n2) / (2.0 * e);

  return vec3(a - d, b - f, c - ee);
}

void main() {
  vec2 uv = gl_FragCoord.xy / resolution.xy;

  vec3 myPos = texture2D(texturePosition, uv).xyz;
  vec3 myVel = texture2D(textureVelocity, uv).xyz;

  // Boids accumulators
  vec3 separation = vec3(0.0);
  vec3 alignment  = vec3(0.0);
  vec3 cohesion   = vec3(0.0);

  float separationCount = 0.0;
  float alignmentCount  = 0.0;
  float cohesionCount   = 0.0;

  // Stride-sampling: step through texture at intervals to sample ~MAX_SAMPLES neighbors
  float stride = max(1.0, floor(TOTAL_PARTICLES / float(MAX_SAMPLES)));

  for (int i = 0; i < MAX_SAMPLES; i++) {
    float idx = float(i) * stride;
    float px = mod(idx, TEXTURE_WIDTH);
    float py = floor(idx / TEXTURE_WIDTH);
    vec2 neighborUV = vec2((px + 0.5) / TEXTURE_WIDTH, (py + 0.5) / TEXTURE_HEIGHT);

    // Skip self
    vec2 selfPixel = gl_FragCoord.xy;
    if (abs(px - selfPixel.x) < 0.5 && abs(py - selfPixel.y) < 0.5) continue;

    vec3 neighborPos = texture2D(texturePosition, neighborUV).xyz;
    vec3 neighborVel = texture2D(textureVelocity, neighborUV).xyz;

    vec3 diff = myPos - neighborPos;
    float dist = length(diff);

    // Separation: push away from very close neighbors
    if (dist > 0.0 && dist < uSeparationRadius) {
      separation += normalize(diff) / dist;
      separationCount += 1.0;
    }

    // Alignment + Cohesion: within perception radius
    if (dist > 0.0 && dist < uPerceptionRadius) {
      alignment += neighborVel;
      alignmentCount += 1.0;

      cohesion += neighborPos;
      cohesionCount += 1.0;
    }
  }

  // ── Scale factor to compensate for sparse sampling ──
  float sampleRatio = TOTAL_PARTICLES / float(MAX_SAMPLES);

  // Average, scale, and weight the forces
  vec3 accel = vec3(0.0);

  if (separationCount > 0.0) {
    separation /= separationCount;
    float scaledSepCount = separationCount * sampleRatio;
    accel += separation * uSeparationWeight * min(scaledSepCount / 10.0, 3.0);
  }

  if (alignmentCount > 0.0) {
    alignment /= alignmentCount;
    vec3 alignSteer = alignment - myVel;
    float alignLen = length(alignSteer);
    if (alignLen > 0.001) {
      alignSteer = normalize(alignSteer);
    }
    accel += alignSteer * uAlignmentWeight;
  }

  if (cohesionCount > 0.0) {
    cohesion /= cohesionCount;
    vec3 toCenter = cohesion - myPos;
    float toCenterLen = length(toCenter);
    if (toCenterLen > 0.001) {
      float steerStrength = smoothstep(0.0, uPerceptionRadius, toCenterLen);
      toCenter = normalize(toCenter) * steerStrength;
    }
    accel += toCenter * uCohesionWeight;
  }

  // ── Curl-noise turbulence ──
  // Time-varying, divergence-free noise field creates organic swirling and shape-shifting
  // Each bird samples a different point in the noise field based on its position
  vec3 noisePos = myPos * 0.008 + uTime * 0.15;
  vec3 turbForce = curlNoise(noisePos) * uTurbulence;
  accel += turbForce;

  // ── Global centroid pull ──
  float distFromCenter = length(myPos);
  float globalPull = smoothstep(uBoundaryRadius * 0.5, uBoundaryRadius, distFromCenter);
  accel -= normalize(myPos + vec3(0.0001)) * globalPull * uCohesionWeight * 0.15;

  // ── Soft spherical boundary constraint ──
  if (distFromCenter > uBoundaryRadius * 0.7) {
    float t = (distFromCenter - uBoundaryRadius * 0.7) / (uBoundaryRadius * 0.3);
    t = clamp(t, 0.0, 1.0);
    float strength = t * t * t * uMaxSpeed * 2.0;
    accel -= normalize(myPos) * strength;
  }

  // Apply acceleration to velocity
  vec3 newVel = myVel + accel * uDelta;

  // Clamp speed
  float speed = length(newVel);
  if (speed > uMaxSpeed) {
    newVel = normalize(newVel) * uMaxSpeed;
  }
  // Enforce minimum speed to keep birds moving
  float minSpeed = uMaxSpeed * 0.2;
  if (speed < minSpeed && speed > 0.001) {
    newVel = normalize(newVel) * minSpeed;
  }

  gl_FragColor = vec4(newVel, 1.0);
}
