---
name: mig-mockup
description: Redesign a page or screen as 2 or 3 self-contained HTML mockups, checked at desktop and phone widths, and get approval before changing app code. Use for /mig-mockup, "redesign", "mockups", "new look", or a UI change big enough that the user should choose between options.
metadata:
  credits:
    - skill: principle-exhaust-the-design-space
      author: poteto
      url: https://github.com/cursor/plugins/blob/main/pstack/skills/principle-exhaust-the-design-space/SKILL.md
      license: MIT
    - skill: prototype
      author: Matt Pocock
      url: https://github.com/mattpocock/skills/tree/main/skills/engineering/prototype
      license: MIT
---

# mig-mockup

Approving a design from static HTML is fast and cheap. Approving it from a half-ported app is neither. So the design happens in mockups, the user picks one, and the port into app code is a separate step.

## 1. Brief

Read the project's AGENTS.md and any earlier design decisions in `docs/handoff/`. Settle, from those files or by asking in one batch:

- the page or screen, who uses it, and what they need to do there;
- brand rules: logo, colours, fonts, corner style, light or dark;
- languages, and whether the site switches EN | PT;
- what must stay as it is.

## 2. Build the options

Build 2 or 3 options that differ in a real way (layout, hierarchy, density), not only in colour.

- One self-contained HTML file per option: `mockups/<slug>/option-a.html`, `option-b.html`. Inline the CSS, and load fonts the way the real site does.
- A `mockups/<slug>/index.html` links every option and says what sets each apart.
- Real copy in every language, with an EN | PT switch when the site has one. Sample figures and names are invented. Never copy real customer or database data into a mockup.
- When the app serves `public/`, mockups placed there are public on any server they reach. Keep them on the branch, and out of the default branch.

## 3. Check them yourself

Open each option in a browser tool at 1440 and 390 pixels wide. Fix overflow, clipped text, broken wrapping and unreadable contrast before the user sees anything. When a `.test` domain's certificate blocks the browser tool, serve the folder with `python3 -m http.server 8765 --bind 127.0.0.1`.

Done when every option renders cleanly at both widths.

## 4. Get a choice

Show the options with a screenshot of each at both widths, the link to the index, and one line on what each does best. Wait for the user to choose, combine or ask for changes.

## 5. Record the decision

Write `docs/handoff/<YYYY-MM-DD>-<slug>-design.md` with the chosen option and its rules: palette with hex values, fonts, spacing, component patterns, copy decisions, and anything the user asked for along the way. The port step reads this file, not the conversation.

## 6. Hand off the port

Porting the approved option into Blade, a Filament theme or the project's templates is a separate step. Add it to the work order, keep the mockups out of the default branch (a tag such as `<slug>-mockups` keeps them reachable), and hand over with `mig-relay`.
