import { defineConfig } from 'vite'
import RubyPlugin from 'vite-plugin-ruby'

export default defineConfig({
  plugins: [
    RubyPlugin(),
    // VitePWA disabled - using Rails PWA instead
  ],
  server: {
    host: '0.0.0.0',
    port: 3036,
    strictPort: false,
    cors: {
      origin: '*',
      credentials: true
    },
    hmr: {
      protocol: 'wss',
      host: process.env.CODESPACE_NAME 
        ? `${process.env.CODESPACE_NAME}-3036.${process.env.GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN}`
        : (process.env.VITE_RUBY_HMR_HOST || 'localhost'),
      clientPort: 443,
      port: 3036
    },
    watch: {
      usePolling: true,
      interval: 1000
    }
  }
})
