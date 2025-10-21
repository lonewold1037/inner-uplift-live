/** @type {import('tailwindcss').Config} */
export default {
  content: [
    './app/views/**/*.html.erb',
    './app/helpers/**/*.rb',
    './app/frontend/**/*.{js,jsx,ts,tsx}',
    './app/controllers/**/*.rb'
  ],
  theme: {
    extend: {},
  },
  plugins: [],
}