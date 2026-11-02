# Cloudflare

For sites whose DNS runs through Cloudflare with the proxy on (orange cloud). Speed settings are in `performance.md`. The steps here happen in the user's dashboard, so they go through `mig-my-turn`.

## SSL and redirects

- **SSL/TLS > Overview**: Full (strict). The origin needs a valid certificate: a public one, or a free Cloudflare Origin Certificate installed on the server.
- **SSL/TLS > Edge Certificates**: Always Use HTTPS on, Automatic HTTPS Rewrites on, minimum TLS 1.2. Turn HSTS on only once every subdomain serves HTTPS, since browsers remember it.
- **One canonical host.** When the web server doesn't do the `www` redirect, add a Redirect Rule for requests where the hostname is `www.<domain>`: type Dynamic, expression `concat("https://<domain>", http.request.uri.path)`, status 301, with "Preserve query string" on.

## Caching

- Static files (CSS, JS, fonts, images) are cached by default. Give versioned assets a long `Cache-Control` from the origin, such as `public, max-age=31536000, immutable`.
- HTML is not cached by default, which is right for pages with forms, sessions or per-user content. For a fully static site, a Cache Rule that caches HTML with a short edge TTL is safe. Purge the cache after each deploy.
- Never cache admin, login or API paths. Add a Cache Rule that bypasses cache for them when a broader rule could catch them.

## Bots and AI crawlers

- **Security > Bots**: Bot Fight Mode can challenge legitimate crawlers. When it is on, check that Googlebot, Bingbot and the AI search bots the user allowed still get 200s. The Cloudflare logs and Search Console's URL Inspection show it.
- **AI Crawl Control** (or "Block AI bots", depending on the plan): match it to the user's intake answer, and to `robots.txt`. A dashboard rule that blocks a bot `robots.txt` allows wins, silently.
- **Security > WAF**: rate-limit the contact form's POST route when the plan allows it. Turnstile covers the form itself, as `contact-form.md` describes.

## DNS records for email

When the site sends email (the contact form through Resend), check:

- SPF and DKIM records exactly as Resend shows them, with the proxy off (grey cloud) for every mail record.
- A DMARC record: start with `v=DMARC1; p=none; rua=mailto:<address>`, and tighten to `quarantine` after a few weeks of clean reports.
