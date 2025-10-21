import { defineConfig } from 'vite'
import RubyPlugin from 'vite-plugin-ruby'
import { VitePWA } from 'vite-plugin-pwa'

export default defineConfig({
  plugins: [
    RubyPlugin(),
    VitePWA({
      registerType: 'autoUpdate',
      includeAssets: ['favicon.ico', 'apple-touch-icon.png'],
      manifest: {
        name: 'Inner Uplift',
        short_name: 'InnerUplift',
        description: 'Your Progressive Web App Description',
        theme_color: '#ffffff',
        background_color: '#ffffff',
        display: 'standalone',
        scope: '/',
        start_url: '/',
        icons: [
          {
            src: '/icons/icon-192x192.png',
            sizes: '192x192',
            type: 'image/png'
          },
          {
            src: '/icons/icon-512x512.png',
            sizes: '512x512',
            type: 'image/png'
          }
        ]
      }
    })
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