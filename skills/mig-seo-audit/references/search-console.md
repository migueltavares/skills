# Google Search Console and Bing Webmaster Tools

These steps happen in the user's accounts, so they go through `mig-my-turn`, one at a time.

## Verify the site in Google Search Console

1. At `https://search.google.com/search-console`, add a **Domain** property for the bare domain. It covers `http`, `https`, `www` and every subdomain.
2. Google shows a TXT record. Add it at the DNS host. On Cloudflare: DNS > Records > Add record, type TXT, name `@`, the value Google shows.
3. Back in Search Console, click Verify. DNS can take a few minutes to update. Check it with `dig +short TXT <domain>`.

When the user can't change DNS, a URL-prefix property verified with an HTML file or meta tag works. It covers that one host and protocol only.

## Submit the sitemap

Sitemaps > Add a new sitemap > `sitemap.xml`. The status should turn to "Success" with the expected number of discovered pages.

## Check the important pages

- **URL Inspection** for the home page and each main page: "URL is on Google", or else request indexing. Use the live test to see the page as Google renders it.
- **Pages** report: read every reason under "Why pages aren't indexed". Pages that should be indexed but aren't become findings.
- **Core Web Vitals** and **HTTPS** reports, once there is enough traffic for data.

## Use the Performance report for copy

Once the site has a few weeks of data:

- Queries with many impressions and a low click rate need a better title or description for that page.
- Queries ranking in positions 5 to 20 are the closest wins. Make sure the page that ranks answers that query clearly, near the top.

## Bing Webmaster Tools

At `https://www.bing.com/webmasters`, choose "Import from Google Search Console". It copies the verified sites and their sitemaps. Bing's index also feeds several AI assistants, so this step is worth doing. IndexNow pings, described in `seo-aeo-checklist.md`, reach Bing directly.
