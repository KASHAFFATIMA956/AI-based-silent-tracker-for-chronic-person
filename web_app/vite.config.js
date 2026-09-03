import react from '@vitejs/plugin-react'
import { defineConfig } from 'vite'

// Dev-server proxy — see context/decisions-log.md ("web app CORS/proxy
// decision"). The FastAPI backend has no CORS middleware (checked before
// building anything — see context/api-contracts.md/main.py — and adding
// one is a backend change out of this session's stated scope). Proxying
// every backend path through Vite's own dev server means the browser only
// ever talks to ITS OWN origin (http://localhost:5173) — no cross-origin
// request ever happens, so no CORS headers are needed at all. The proxy
// target is overridable via VITE_API_BASE_URL for a non-default backend
// port/host (mirrors mobile_app's ROZNOOR_API_BASE_URL --dart-define).
const backendTarget = process.env.VITE_API_BASE_URL || 'http://localhost:8000'

export default defineConfig({
  plugins: [react()],
  server: {
    port: 5173,
    proxy: {
      '/auth': backendTarget,
      '/patients': backendTarget,
      '/entries': backendTarget,
      '/doctors': backendTarget,
      '/alerts': backendTarget,
      '/admin': backendTarget,
      '/health': backendTarget,
    },
  },
})
