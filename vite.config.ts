import { defineConfig } from 'vite';
import glsl from 'vite-plugin-glsl';

export default defineConfig({
    base: './', // Use relative paths for assets so it can be hosted anywhere (like GitHub Pages)
    plugins: [glsl()],
    server: {
        open: true,
    },
    build: {
        target: 'esnext', // Modern browsers for top WebGL/WebGPU performance
        minify: 'terser',
        terserOptions: {
            compress: {
                drop_console: true, // Remove console.logs in production
                drop_debugger: true,
            },
        },
        rollupOptions: {
            output: {
                // Manual chunks for better caching
                manualChunks: {
                    three: ['three'],
                    gui: ['lil-gui']
                }
            }
        }
    }
});
