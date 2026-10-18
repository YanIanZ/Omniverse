import react from '@vitejs/plugin-react'
import { defineConfig } from 'vite'

// Development only: Vite proxies /api, /ws and /auth to the Vapor server.
// Start the server with: om serve --dev-origin http://127.0.0.1:5173
const target = process.env.OMNIMEMO_SERVER ?? 'http://127.0.0.1:8787'

export default defineConfig({
  plugins: [react()],
  server: {
    host: '127.0.0.1',
    port: 5173,
    strictPort: true,
    proxy: {
      '/api': { target, changeOrigin: true },
      '/auth': { target, changeOrigin: true },
      '/ws': { target, changeOrigin: true, ws: true },
    },
  },
  build: { outDir: 'dist', sourcemap: false },
})
