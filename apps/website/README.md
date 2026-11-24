# beyondrep.in website

Static marketing and legal site for BeyondRep, built with [Astro](https://astro.build) and hosted on Cloudflare Pages.

```sh
npm ci
npm run dev           # http://localhost:4321
npm test              # unit tests for the link/SEO checker
npm run build         # writes dist/
npm run check-links   # broken local links and missing SEO tags in dist/
```

Pages live in `src/pages/`. Shared facts (contact addresses, store links, legal draft flag) are in `src/site.ts`. When the app is listed, set `appStoreUrl` / `playStoreUrl` there and the "Tell me when it launches" buttons become store buttons.

## Cloudflare Pages setup (one time, by the owner)

1. Cloudflare dashboard > Workers & Pages > Create > Pages > Connect to Git, and pick this repository.
2. Production branch `main`. Framework preset Astro. Root directory `apps/website`. Build command `npm run build`. Output directory `dist`.
3. Environment variable `NODE_VERSION` = `22.23.4` or newer.
4. Build watch paths: include `apps/website/*`, so app-only commits don't rebuild the site.
5. Custom domains: add `beyondrep.in` and `www.beyondrep.in` (with the domain's DNS on Cloudflare, HTTPS is automatic). Redirect `www` to the apex with a Redirect Rule.
6. Optional: enable Web Analytics for the project.
7. Set up `hello@` and `privacy@beyondrep.in` with Cloudflare Email Routing, since the site links to both.

Then submit `https://beyondrep.in/sitemap-index.xml` in Google Search Console and Bing Webmaster Tools.
