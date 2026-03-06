import type { Config } from 'tailwindcss';

const config: Config = {
  content: [
    './app/**/*.{js,ts,jsx,tsx,mdx}',
    './components/**/*.{js,ts,jsx,tsx,mdx}',
  ],
  theme: {
    extend: {
      colors: {
        fast: {
          bg: '#f7f7f7',
          panel: '#ffffff',
          /* Single teal only: #003A46 (requirements 6.2 Theme colours; specification Color Palette – no other shades of green/blue) */
          sidebar: '#003A46',
          'sidebar-active': '#003A46',
          text: '#212121',
          muted: '#757575',
          teal: '#003A46',
          'teal-light': '#e6ecee',
          cyan: '#003A46',
          blue: '#003A46',
          'blue-light': '#e6ecee',
          'red-light': '#feeaea',
          'orange-light': '#fff0e5',
          'purple-light': '#f0e5ff',
          'green-light': '#e6ecee',
          approved: '#003A46',
          declined: '#f44336',
          pending: '#ffc107',
          escalated: '#ff9800',
          urgent: '#f44336',
          high: '#ff9800',
          standard: '#607d8b',
          low: '#607d8b',
          caseworker: '#003A46',
          manager: '#003A46',
          admin: '#8a2be2',
        },
      },
      borderRadius: {
        'card': '8px',
        'chip': '9999px',
      },
      boxShadow: {
        'card': '0 1px 3px 0 rgba(0, 0, 0, 0.1), 0 1px 2px 0 rgba(0, 0, 0, 0.06)',
        'card-hover': '0 4px 6px -1px rgba(0, 0, 0, 0.1), 0 2px 4px -1px rgba(0, 0, 0, 0.06)',
      },
    },
  },
  plugins: [],
};

export default config;
