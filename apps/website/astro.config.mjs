// @ts-check
import { defineConfig } from 'astro/config';
import sitemap from '@astrojs/sitemap';

// Pages build to /privacy.html etc. Cloudflare Pages serves them at /privacy,
// which matches the store-listed URLs (https://beyondrep.in/privacy).
export default defineConfig({
  site: 'https://beyondrep.in',
  trailingSlash: 'never',
  build: { format: 'file' },
  integrations: [sitemap({ filter: (page) => !page.endsWith('/404') })],
});
