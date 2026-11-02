---
name: mig-seo-audit
description: Audit a public website and take it to launch quality. Covers technical and on-page SEO, structured data, hreflang, AI search, PageSpeed, Search Console, Analytics behind cookie consent, Cloudflare, and a contact form with a branded email.
disable-model-invocation: true
metadata:
  credits:
    - skill: mig-seo
      author: Miguel Tavares
      note: The launch kit this skill grew from, including its reference files.
---

# mig-seo-audit

Takes a public site or landing page to launch quality, in order: intake, audit, fixes, consent and analytics, the contact form, speed, and the steps only the user can do. Each step has a reference file in `references/`. Read it in full when you reach that step.

Scope is the public site. Logged-in apps, admin panels and portals are out. Changes ship as a PR, merged with `/mig-merge`. Steps in the user's accounts (Search Console, Analytics, Cloudflare, DNS, the mail provider) go through `mig-my-turn`.

## 1. Intake

Read the project first: its AGENTS.md, README, `git status`, the stack, the page templates, where the copy lives, and any existing analytics, forms, `robots.txt`, sitemap or structured data. Leave uncommitted work alone.

Then ask every question below that the project doesn't already answer, in one numbered batch. For the ones you answered yourself, say what you found.

1. **Site.** Production and local URLs. Which pages are public, which languages, and which is the default?
2. **Offer.** One sentence on what it is and who it's for, and the main phrase people search to find it.
3. **Pricing.** Plans, prices, currency, whether VAT is included, billing cycles. Or confirm there's no public pricing.
4. **Operator.** Legal name, entity type, VAT or NIF number and postal address, for the legal pages, the footer and the structured data. Never guess these.
5. **Search Console and Bing.** Is the domain verified? Has a sitemap been submitted?
6. **Analytics.** Does a GA4 property exist, and what is its measurement ID? Advanced Consent Mode, or strict mode where nothing loads before Accept? `analytics-consent.md` explains both.
7. **Contact form.** Is the sending domain verified at Resend (SPF, DKIM, DMARC)? Which address sends, and which inbox receives? Keys go in the server's environment, set by the user, never in chat.
8. **Cloudflare.** Is the domain behind Cloudflare? Is there a Turnstile widget for the form?
9. **AI crawlers.** Allow AI search bots only, or AI training crawlers too?
10. **Brand.** Logo, colours, fonts, for the email template, the 404 page and social images.

Done when every question is answered, or the user has said to skip it.

## 2. Audit

Run the site locally. Go through [references/audit.md](references/audit.md) for every page and language, and through [references/seo-aeo-checklist.md](references/seo-aeo-checklist.md).

Write the findings as one table ranked by severity: issue, page or file, fix. Show copy changes as before and after, in every language. Portuguese copy follows `mig-pt-pt` when it is installed.

Done when every page and every checklist item is covered, and the user has approved the fix list.

## 3. Apply the fixes

Apply the approved fixes, following `seo-aeo-checklist.md`: titles and descriptions, the opening definition, pricing as plain text, `robots.txt`, `llms.txt`, the sitemap, IndexNow, JSON-LD, hreflang, social images, the operator details, the 404 page, hidden repo files and redirects.

Done when every item is applied or marked "not applicable" with a reason, and every page still renders without errors.

## 4. Consent and Analytics

Follow [references/analytics-consent.md](references/analytics-consent.md).

Done when, on a local run:
- with no stored choice, the banner shows and no `_ga` cookies exist;
- Accept sets `_ga` cookies, and the banner stays hidden on the next page;
- Reject keeps cookies off and deletes any existing `_ga` cookies;
- the "Cookie settings" link in the footer reopens the banner.

## 5. Contact form

Follow [references/contact-form.md](references/contact-form.md) and [references/email-template.html](references/email-template.html), filled with the brand from intake. Render the email with sample data and show it to the user before committing.

Done when, locally:
- an invalid submit shows field errors without a page reload;
- a valid submit shows the success message, resets the form, and the email arrives as HTML with a plain-text part and Reply-To set to the visitor;
- with JavaScript off, the form still posts and the page shows the server's message. With Turnstile on, that is the message with the email address to write to instead.

## 6. Speed

Follow [references/performance.md](references/performance.md). Record a real performance trace before changing anything, since the PageSpeed mobile score is simulated.

Done when every item there is applied or ruled out with a reason, and the user has the before and after numbers.

## 7. Ship and hand over

1. Show a summary of the changes, then commit on a branch and open a PR with deploy notes: new env vars, server rules, and anything to purge. In T3 Code, link the PR with `link_pull_request`.
2. After the merge, walk the user through their steps with `mig-my-turn`:
   - Search Console verification, the sitemap and Bing, from [references/search-console.md](references/search-console.md);
   - Cloudflare SSL, redirects, caching, bots and mail DNS records, from [references/cloudflare.md](references/cloudflare.md);
   - Analytics data retention set to 14 months (the default is 2), and a check in Realtime after clicking Accept in a private window;
   - env vars for the mail provider and Turnstile on the server, named but never valued;
   - an IndexNow ping for the changed URLs;
   - PageSpeed Insights run two or three times, judged by the median.
3. Record lasting facts in the project's AGENTS.md: the analytics ID, the mail provider, the Cloudflare setup, and the dates of verification.
