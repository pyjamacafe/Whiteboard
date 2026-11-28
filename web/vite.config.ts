import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import { VitePWA } from 'vite-plugin-pwa';

const basePath = process.env.VITE_BASE_PATH || './';

export default defineConfig({
  base: basePath,
  plugins: [
    react(),
    VitePWA({
      registerType: 'autoUpdate',
      includeAssets: ['logo.png', 'icons/icon-128.png', 'icons/icon-256.png', 'icons/icon-512.png'],
      manifest: {
        name: 'Tissue Box',
        short_name: 'Tissue Box',
        description:
          'Quick vector sketching like on a café napkin — works offline on Windows, Linux, macOS, and iPad.',
        start_url: '.',
        scope: '.',
        display: 'standalone',
        orientation: 'any',
        background_color: '#ffffff',
        theme_color: '#007aff',
        categories: ['productivity', 'graphics', 'utilities'],
        icons: [
          {
            src: 'icons/icon-128.png',
            sizes: '128x128',
            type: 'image/png',
          },
          {
            src: 'icons/icon-256.png',
            sizes: '256x256',
            type: 'image/png',
          },
          {
            src: 'icons/icon-512.png',
            sizes: '512x512',
            type: 'image/png',
            purpose: 'any maskable',
          },
        ],
        file_handlers: [
          {
            action: '.',
            accept: {
              'application/json': ['.wb'],
            },
          },
        ],
      },
      workbox: {
        globPatterns: ['**/*.{js,css,html,png,svg,ico,webmanifest}'],
        maximumFileSizeToCacheInBytes: 4 * 1024 * 1024,
      },
    }),
  ],
  build: {
    outDir: 'dist',
    sourcemap: false,
    rollupOptions: {
      output: {
        manualChunks: {
          'pdf-lib': ['pdf-lib'],
        },
      },
    },
  },
});
