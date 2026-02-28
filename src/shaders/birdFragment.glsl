// Bird fragment shader
// Manual Lambert + rim lighting (ShaderMaterial bypasses Three.js light system)

varying vec3 vNormal;
varying vec3 vWorldPosition;
varying vec3 vColor;

void main() {
  // Directional light from upper-right
  vec3 lightDir = normalize(vec3(0.6, 0.8, 0.5));
  vec3 lightColor = vec3(1.0, 0.95, 0.9);
  float ambientStrength = 0.25;

  // Lambert diffuse
  float NdotL = max(dot(vNormal, lightDir), 0.0);
  vec3 diffuse = vColor * lightColor * NdotL;

  // Ambient
  vec3 ambient = vColor * ambientStrength;

  // Rim / back-lighting for that cinematic murmuration glow
  vec3 viewDir = normalize(cameraPosition - vWorldPosition);
  float rim = 1.0 - max(dot(viewDir, vNormal), 0.0);
  rim = pow(rim, 3.0) * 0.4;
  vec3 rimColor = vec3(0.6, 0.4, 1.0) * rim;

  // Secondary fill light from below-left
  vec3 fillDir = normalize(vec3(-0.4, -0.3, 0.6));
  float fillNdotL = max(dot(vNormal, fillDir), 0.0);
  vec3 fill = vColor * vec3(0.3, 0.4, 0.6) * fillNdotL * 0.4;

  vec3 finalColor = ambient + diffuse + rimColor + fill;

  // Subtle fog for depth
  float dist = length(vWorldPosition - cameraPosition);
  float fogFactor = smoothstep(200.0, 800.0, dist);
  vec3 fogColor = vec3(0.02, 0.02, 0.05);
  finalColor = mix(finalColor, fogColor, fogFactor);

  gl_FragColor = vec4(finalColor, 1.0);
}
