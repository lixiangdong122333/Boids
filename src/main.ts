import * as THREE from 'three';
import { OrbitControls } from 'three/addons/controls/OrbitControls.js';
import { GPUComputationRenderer } from 'three/addons/misc/GPUComputationRenderer.js';
import GUI from 'lil-gui';

import positionFragmentShader from './shaders/positionFragment.glsl';
import velocityFragmentShader from './shaders/velocityFragment.glsl';
import birdVertexShader from './shaders/birdVertex.glsl';
import birdFragmentShader from './shaders/birdFragment.glsl';

// ─── Constants ────────────────────────────────────────────────────────
const TEXTURE_WIDTH = 512;
const TEXTURE_HEIGHT = 512;
const PARTICLE_COUNT = TEXTURE_WIDTH * TEXTURE_HEIGHT; // 65536

// ─── Params (bound to lil-gui) ───────────────────────────────────────
const params = {
    birdCount: PARTICLE_COUNT,
    separation: 25.0,
    alignment: 8.0,
    cohesion: 12.0,
    maxSpeed: 50.0,
    perceptionRadius: 120.0,
    separationRadius: 25.0,
    boundaryRadius: 350.0,
    turbulence: 15.0,
};

// ─── Three.js Scene ──────────────────────────────────────────────────
const renderer = new THREE.WebGLRenderer({ antialias: true });
renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
renderer.setSize(window.innerWidth, window.innerHeight);
renderer.setClearColor(0x020210);
document.body.appendChild(renderer.domElement);

const scene = new THREE.Scene();
scene.fog = new THREE.FogExp2(0x020210, 0.0015);

const camera = new THREE.PerspectiveCamera(
    60,
    window.innerWidth / window.innerHeight,
    1,
    2000
);
camera.position.set(0, 50, 350);
camera.lookAt(0, 0, 0);

const controls = new OrbitControls(camera, renderer.domElement);
controls.enableDamping = true;
controls.dampingFactor = 0.08;
controls.minDistance = 50;
controls.maxDistance = 1000;

// ─── GPGPU Setup ─────────────────────────────────────────────────────
const gpuCompute = new GPUComputationRenderer(
    TEXTURE_WIDTH,
    TEXTURE_HEIGHT,
    renderer
);

// Check float texture support
if (!renderer.capabilities.isWebGL2) {
    const ext = renderer.getContext().getExtension('OES_texture_float');
    if (!ext) {
        console.error('OES_texture_float not supported');
    }
}

// Create initial data textures
const dtPosition = gpuCompute.createTexture();
const dtVelocity = gpuCompute.createTexture();

// Fill with random initial data
fillPositionTexture(dtPosition);
fillVelocityTexture(dtVelocity);

// Add compute variables
const positionVariable = gpuCompute.addVariable(
    'texturePosition',
    positionFragmentShader,
    dtPosition
);

const velocityVariable = gpuCompute.addVariable(
    'textureVelocity',
    velocityFragmentShader,
    dtVelocity
);

// Set dependencies (both shaders read both textures)
gpuCompute.setVariableDependencies(positionVariable, [
    positionVariable,
    velocityVariable,
]);
gpuCompute.setVariableDependencies(velocityVariable, [
    positionVariable,
    velocityVariable,
]);

// Position shader uniforms
const posUniforms = positionVariable.material.uniforms;
posUniforms['uDelta'] = { value: 0.0 };

// Velocity shader uniforms
const velUniforms = velocityVariable.material.uniforms;
velUniforms['uDelta'] = { value: 0.0 };
velUniforms['uTime'] = { value: 0.0 };
velUniforms['uSeparationWeight'] = { value: params.separation };
velUniforms['uAlignmentWeight'] = { value: params.alignment };
velUniforms['uCohesionWeight'] = { value: params.cohesion };
velUniforms['uMaxSpeed'] = { value: params.maxSpeed };
velUniforms['uPerceptionRadius'] = { value: params.perceptionRadius };
velUniforms['uSeparationRadius'] = { value: params.separationRadius };
velUniforms['uBoundaryRadius'] = { value: params.boundaryRadius };
velUniforms['uTurbulence'] = { value: params.turbulence };

// Wrap mode for textures
positionVariable.wrapS = THREE.RepeatWrapping;
positionVariable.wrapT = THREE.RepeatWrapping;
velocityVariable.wrapS = THREE.RepeatWrapping;
velocityVariable.wrapT = THREE.RepeatWrapping;

// Init GPGPU
const gpuError = gpuCompute.init();
if (gpuError !== null) {
    console.error('GPUComputationRenderer init error:', gpuError);
}

// ─── Instanced Bird Mesh ─────────────────────────────────────────────
const birdGeometry = createBirdGeometry();
const birdMaterial = new THREE.ShaderMaterial({
    uniforms: {
        uTexturePosition: { value: null },
        uTextureVelocity: { value: null },
    },
    vertexShader: birdVertexShader,
    fragmentShader: birdFragmentShader,
    side: THREE.DoubleSide,
});

const birdMesh = new THREE.InstancedMesh(birdGeometry, birdMaterial, PARTICLE_COUNT);
birdMesh.frustumCulled = false;
scene.add(birdMesh);

// ─── lil-gui ─────────────────────────────────────────────────────────
const gui = new GUI({ title: '🐦 Murmuration Controls' });
gui.add(params, 'birdCount', 1000, PARTICLE_COUNT, 1000).name('Bird Count').onChange(
    (v: number) => (birdMesh.count = v)
);
gui.add(params, 'separation', 0, 100, 0.5).name('Separation').onChange(
    (v: number) => (velUniforms['uSeparationWeight'].value = v)
);
gui.add(params, 'alignment', 0, 100, 0.5).name('Alignment').onChange(
    (v: number) => (velUniforms['uAlignmentWeight'].value = v)
);
gui.add(params, 'cohesion', 0, 50, 0.5).name('Cohesion').onChange(
    (v: number) => (velUniforms['uCohesionWeight'].value = v)
);
gui.add(params, 'maxSpeed', 5, 150, 1).name('Max Speed').onChange(
    (v: number) => (velUniforms['uMaxSpeed'].value = v)
);
gui.add(params, 'perceptionRadius', 5, 100, 1).name('Perception Radius').onChange(
    (v: number) => (velUniforms['uPerceptionRadius'].value = v)
);
gui.add(params, 'separationRadius', 2, 50, 0.5).name('Sep. Radius').onChange(
    (v: number) => (velUniforms['uSeparationRadius'].value = v)
);
gui.add(params, 'boundaryRadius', 50, 600, 10).name('Boundary').onChange(
    (v: number) => (velUniforms['uBoundaryRadius'].value = v)
);
gui.add(params, 'turbulence', 0, 50, 0.5).name('Turbulence').onChange(
    (v: number) => (velUniforms['uTurbulence'].value = v)
);

// ─── Animation Loop ──────────────────────────────────────────────────
const clock = new THREE.Clock();
let lastTime = 0;

function animate(): void {
    requestAnimationFrame(animate);

    const now = clock.getElapsedTime();
    let delta = now - lastTime;
    lastTime = now;

    // Clamp delta to avoid huge jumps on tab switch
    delta = Math.min(delta, 0.05);

    // Update GPGPU uniforms
    posUniforms['uDelta'].value = delta;
    velUniforms['uDelta'].value = delta;
    velUniforms['uTime'].value = now;

    // Run GPU computation
    gpuCompute.compute();

    // Pass computed textures to bird material
    const posTexture = gpuCompute.getCurrentRenderTarget(positionVariable).texture;
    const velTexture = gpuCompute.getCurrentRenderTarget(velocityVariable).texture;

    birdMaterial.uniforms['uTexturePosition'].value = posTexture;
    birdMaterial.uniforms['uTextureVelocity'].value = velTexture;

    // Update controls
    controls.update();

    // Render
    renderer.render(scene, camera);
}

animate();

// ─── Window Resize ───────────────────────────────────────────────────
window.addEventListener('resize', () => {
    camera.aspect = window.innerWidth / window.innerHeight;
    camera.updateProjectionMatrix();
    renderer.setSize(window.innerWidth, window.innerHeight);
});

// ─── Helper Functions ────────────────────────────────────────────────

function fillPositionTexture(texture: THREE.DataTexture): void {
    const data = texture.image.data as unknown as Float32Array;
    const spread = params.boundaryRadius * 0.6;

    for (let i = 0; i < data.length; i += 4) {
        // Spherical distribution
        const r = Math.random() * spread;
        const theta = Math.random() * Math.PI * 2;
        const phi = Math.acos(2 * Math.random() - 1);

        data[i + 0] = r * Math.sin(phi) * Math.cos(theta); // x
        data[i + 1] = r * Math.sin(phi) * Math.sin(theta); // y
        data[i + 2] = r * Math.cos(phi);                    // z
        data[i + 3] = 1.0; // phase/flag
    }
}

function fillVelocityTexture(texture: THREE.DataTexture): void {
    const data = texture.image.data as unknown as Float32Array;
    const initSpeed = params.maxSpeed * 0.3;

    for (let i = 0; i < data.length; i += 4) {
        // Random direction with moderate speed
        const theta = Math.random() * Math.PI * 2;
        const phi = Math.acos(2 * Math.random() - 1);

        data[i + 0] = initSpeed * Math.sin(phi) * Math.cos(theta); // vx
        data[i + 1] = initSpeed * Math.sin(phi) * Math.sin(theta); // vy
        data[i + 2] = initSpeed * Math.cos(phi);                    // vz
        data[i + 3] = 1.0;
    }
}

function createBirdGeometry(): THREE.InstancedBufferGeometry {
    // Small cone: radius 0.4, height 2.0, tip at +Y
    const cone = new THREE.ConeGeometry(0.4, 2.0, 4); // Low poly for performance
    cone.rotateX(0); // Tip already at +Y

    // Convert to InstancedBufferGeometry
    const geometry = new THREE.InstancedBufferGeometry();
    geometry.index = cone.index;
    geometry.attributes['position'] = cone.attributes['position'];
    geometry.attributes['normal'] = cone.attributes['normal'];

    // Reference attribute: UV coordinates into GPGPU texture for each instance
    const references = new Float32Array(PARTICLE_COUNT * 2);
    for (let i = 0; i < PARTICLE_COUNT; i++) {
        const x = (i % TEXTURE_WIDTH) / TEXTURE_WIDTH;
        const y = Math.floor(i / TEXTURE_WIDTH) / TEXTURE_HEIGHT;
        references[i * 2 + 0] = x + 0.5 / TEXTURE_WIDTH;   // center of pixel
        references[i * 2 + 1] = y + 0.5 / TEXTURE_HEIGHT;
    }

    geometry.setAttribute(
        'reference',
        new THREE.InstancedBufferAttribute(references, 2)
    );

    return geometry;
}
