# SEO and AEO checklist

The fixes that mattered most on real landing page launches. Apply each one or mark it "not applicable" with a reason. Replace `<domain>`, `<Product>` and the other placeholders with intake answers.

## Copy and on-page

- **Title tags.** About 55 characters, main search phrase first, brand last: `Customer Communications Platform for WhatsApp | <Product>`. One unique title per page and language. No em dashes.
- **Meta descriptions.** Under 155 characters, a plain statement of what the product does and for whom.
- **Hero definition.** The first sentence in the hero says what the product is: "<Product> is a <category> for <audience>." AI tools quote the first clear definition they find. Keep the main search phrase in the H1 or that first sentence.
- **One H1 per page.** Decorative UI mockups (fake inboxes, dashboards) use `div`/`span`/`p`, never heading tags.
- **Pricing as plain text.** If a monthly/annual toggle shows prices through CSS or JS, add one visually hidden sentence per plan with clean prices: "Starter costs €39.90 per month or €399 per year, plus VAT." Use a standard `.sr-only` class.
- **No claims that go stale.** Avoid "always", "never" and exact third-party prices or rules unless you cite the source and date. Point to the vendor's current pricing page instead.
- **FAQ.** A visible FAQ that answers the questions buyers and AI tools ask: what it is, who it's for, pricing, data location, contracts, setup time. Short, self-contained answers.
- **Language parity.** Every language version has the same sections, prices, FAQ and claims.

## robots.txt

Separate groups, so the user can change the training answer later without touching the rest. Keep the training group either way: a crawler with no group of its own follows `User-agent: *`, which allows everything.

```text
# Search engines and AI answer engines are welcome to read and cite <domain>.

# AI search and answer engines
User-agent: OAI-SearchBot
User-agent: ChatGPT-User
User-agent: Claude-SearchBot
User-agent: Claude-User
User-agent: PerplexityBot
User-agent: Perplexity-User
Allow: /

# AI training crawlers: Allow: / if the user agreed at intake, Disallow: / if not
User-agent: GPTBot
User-agent: ClaudeBot
User-agent: Google-Extended
User-agent: Applebot-Extended
Allow: /

User-agent: *
Allow: /

Sitemap: https://<domain>/sitemap.xml
```

Add `Disallow:` lines to every group for folders that exist in the web root but aren't public pages, such as `/mockups/`.

## llms.txt

A Markdown file at the site root that summarizes the site for AI tools. Plain facts, no marketing tone. Structure:

```markdown
# <Product>

> <Product> is a <category> for <audience>. <One sentence on the core job.> <Who develops it, where it's hosted.>

<Two or three sentences: who uses it today, which markets, which languages the site is in.>

## What <Product> does today

- <Feature, stated as what it does>
- ...

## Pricing (<currency>, plus VAT)

- <Plan>: <price per month>, or <price per year>. <Limits>. <Setup fee rules>.
- ...

## Operator

<Product> is operated by <legal name> (<entity type>), <VAT/NIF>, <postal address>. Contact: <email>.

## Pages

- [Home](https://<domain>/): <one line>
- [Home in <language 2>](https://<domain>/<lang>/): <one line>
- [Privacy Policy](https://<domain>/privacy-policy/)
- [Terms](https://<domain>/terms/)
```

List only features that exist today, never planned ones. Update it whenever prices or features change.

## sitemap.xml

Every public page with `<lastmod>` (YYYY-MM-DD). On multilingual sites, add `xhtml:link` alternates for every language plus `x-default` on each `<url>`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9"
    xmlns:xhtml="http://www.w3.org/1999/xhtml">
    <url>
        <loc>https://<domain>/</loc>
        <lastmod>2026-01-01</lastmod>
        <xhtml:link rel="alternate" hreflang="en" href="https://<domain>/" />
        <xhtml:link rel="alternate" hreflang="pt-PT" href="https://<domain>/pt/" />
        <xhtml:link rel="alternate" hreflang="x-default" href="https://<domain>/" />
    </url>
</urlset>
```

Leave the 404 page and anything `noindex` out of the sitemap. Bump `lastmod` when a page's content changes.

## IndexNow

1. Generate a 32-character hex key (`openssl rand -hex 16`).
2. Save it as `/<key>.txt` in the web root, with the key as the only content.
3. After each deploy that changes content, ping each changed URL:

```bash
curl -s "https://api.indexnow.org/indexnow?url=https://<domain>/&key=<key>"
```

Document the key file and the ping command in the project README. If the project already has a deploy script, the user can add the ping there. Don't create deploy tooling yourself.

## Head tags

On every page:

- `<html lang="...">` with the real language code (`en`, `pt-PT`).
- `<meta name="viewport" content="width=device-width, initial-scale=1">`.
- `<link rel="canonical">` with the absolute production URL.
- `<meta name="robots" content="index, follow, max-image-preview:large, max-snippet:-1">` on indexable pages, and `noindex, follow` on the 404 page.
- Open Graph: `og:type`, `og:site_name`, `og:locale` (plus `og:locale:alternate`), `og:title`, `og:description`, `og:url`, `og:image` (absolute URL), `og:image:width` 1200, `og:image:height` 630, `og:image:alt`.
- Twitter: `twitter:card` = `summary_large_image`, plus title, description and image.
- Icons: a 64px PNG for `rel="icon"` and a 180px `apple-touch-icon`. Never point icons or header logos at a large source image.

## hreflang (multilingual sites only)

- Every page links to every language version and itself, plus `x-default`, as `<link rel="alternate" hreflang="...">`. Use full BCP 47 codes where the market matters (`pt-PT`, not `pt`).
- Alternates are reciprocal: if EN points to PT, PT points back to EN.
- If the site redirects by browser language, send `Vary: Accept-Language` on that response, redirect only the home page, only on GET, and only when no language cookie exists. Set the language cookie only when it changes, so cached pages stay cacheable.

## Structured data (JSON-LD)

Generate it from the same data that renders the page, so prices and FAQ answers can't drift. One `@graph` per page:

- **Organization**: `name`, `url`, `logo`, `email`, `description`, `legalName`, `vatID`, `address` (PostalAddress), `founder` if the user wants it. Use the real legal setup. Don't name a parent company unless it legally is one.
- **WebSite**: `name`, `url`, `publisher` pointing at the Organization `@id`, `inLanguage` as a list of every language.
- **WebPage**: `url`, `name`, `description`, `inLanguage`, `isPartOf` WebSite, `about` the product.
- **SoftwareApplication** (for SaaS), or Product or Service as fits: `applicationCategory` `BusinessApplication`, `operatingSystem` `Web`, `offers` with one Offer per plan and billing cycle. Each Offer has `price` as a plain decimal string, `priceCurrency`, and a `UnitPriceSpecification` with `valueAddedTaxIncluded`, `billingDuration` (`P1M`/`P1Y`) and `referenceQuantity` with `unitCode` `MON`/`ANN`.
- **FAQPage**: matches the visible FAQ word for word. Google retired FAQ rich results, so this is for AI tools and other search engines, not Google snippets.
- Legal pages: a WebPage with `dateModified`, linked to the WebSite and Organization `@id`s.

Encode with JSON_HEX_TAG or the equivalent, so `</script>` inside text can't break out. Validate the output against the schema skills' rules.

## Legal operator

EU law requires the site to name the operator, and AI tools read it as a trust signal. Put the legal name, entity type, VAT/NIF number and postal address in:

- the Privacy Policy (who the controller is) and the Terms (who the contract is with), in every language, with an updated "Last updated" date;
- the Organization JSON-LD;
- llms.txt;
- the footer, only if the user wants it there.

## Social preview images

One 1200x630 PNG per language, with the product name and the hero line. Keep it under about 300 KB. Reference it with an absolute URL in `og:image` and `twitter:image`.

## 404 page

- A branded page in the site's design with a clear "Back to home" button, plus one or two useful links such as pricing or contact.
- It returns a real `404` status, not 200, and has `noindex`.
- On multilingual sites, pick the language from the URL path, then the language cookie, then `Accept-Language`.
- It loads the same analytics and consent banner as other pages, so broken links show up in GA.
- The web server must route unknown URLs to it. Apache: `ErrorDocument 404 /404.php`. Nginx: `error_page 404 /404.php;` in the server block. On HestiaCP, nginx sits in front of Apache and serves some file types (such as `.json`) straight from disk, so Apache rules don't cover those. They need a custom nginx include such as `/home/<user>/conf/web/<domain>/nginx.ssl.conf_<name>`, then `nginx -t && systemctl reload nginx`. Give the user these server steps one at a time and wait for their output after each.

## Hide repo files

If the site is served straight from a git checkout, the docs, scripts and source folders are public unless blocked. Return 404 for anything that isn't a public page or asset: README, AGENTS.md, deploy scripts, composer and package files, `.env.example`, `includes/`, `vendor/`, `mockups/`, `.github/`, tool folders. Apache example:

```apache
RedirectMatch 404 ^/(README\.md|AGENTS\.md|deploy\.sh|composer\.json|composer\.lock|\.env\.example|\.gitignore)$
RedirectMatch 404 ^/(includes|vendor|mockups|\.github|\.agents|\.codex)(/|$)
```

Test each blocked path with `curl -I` after the user applies it.

## Redirects

One canonical host. `http://` redirects to `https://`, and `www.` redirects to the bare domain (or the reverse, matching the canonical tags), with 301s that keep the path. Check with `curl -sI` on `http://www.<domain>/some/path`.

## Agent readiness

Lighthouse has an "Agentic browsing" check. Valid, semantic HTML is what passes it:

- `<dl>` contains only `<dt>`/`<dd>` groups, each group optionally wrapped in one `<div>`. Any other child fails.
- Every form field has a `<label>`, buttons are `<button>`, links are `<a href>`, and ARIA roles match the elements.
- The main content is readable without JavaScript.
