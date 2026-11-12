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

List every page and state in scope (empty, error, logged out, the landing page, each role's view) and confirm the list with the user before building.

Then look at what exists today. Screenshot each current page at 1440 and 390 with `node <skill-dir>/scripts/check.mjs <url>` (`<skill-dir>` is this skill's absolute installed path), and read the live CSS for the container or wrapper width, base font size, sidebar width and brand colours. The options keep those unless the user asks to change them. When they conflict with a design doc, show both and ask which wins.

## 2. Build the options

Build 2 or 3 options that differ in a real way (layout, hierarchy, density), not only in colour.

- One self-contained HTML file per option: `mockups/<slug>/option-a.html`, `option-b.html`. Inline the CSS, and load fonts the way the real site does. Reuse the app's real class names and components where you can, so the port is a copy, not a rewrite.
- A `mockups/<slug>/index.html` with one row per page: a "Before" screenshot of the current page, then a square thumbnail of each option, each linking to the full page, plus one line on what sets each option apart.
- Real copy in every language, with an EN | PT switch when the site has one. Portuguese copy goes through `mig-pt-pt`. Sample figures and names are invented. Never copy real customer or database data into a mockup.
- Every assumption you made without asking shows on the mockup as a visible note, so the user can answer it while looking.
- When the app serves `public/`, mockups placed there are public on any server they reach. Keep them on the branch, and out of the default branch.

## 3. Check them yourself

Run the check script on the folder:

```bash
node <skill-dir>/scripts/check.mjs mockups/<slug>
```

It loads each option at 1440 and 390 in headless Chrome, saves screenshots to `mockups/<slug>/shots/`, and exits 1 when a page scrolls sideways, naming the elements that stick out. Look at the screenshots too: fix clipped text, broken wrapping and unreadable contrast before the user sees anything. The index thumbnails can use these screenshots.

Done when the script exits 0 and every screenshot looks right at both widths.

## 4. Get a choice

Serve the folder where the user can open it. Use the address the user's own rules give for sharing local pages. Without one, bind to `127.0.0.1`. Pick a free port, run the server as a background task with the longest timeout the host allows, and tell the user when it will stop. Stop it with `fuser -k <port>/tcp`, never `pkill -f`, which can kill the agent's own shell. When the user's phone can't reach it, publish the index as an Artifact where the host has one.

Show the link to the index, a screenshot of each option at both widths, and one line on what each does best. Wait for the user to choose, combine or ask for changes.

When the run is unattended (the user is away, an overnight run), stop here. Never change app code before the user has chosen.

## 5. Record the decision

Write `docs/handoff/<YYYY-MM-DD>-<slug>-design.md` with the chosen option and its rules: palette with hex values, fonts, spacing, component patterns, copy decisions, and anything the user asked for along the way. The port step reads this file, not the conversation.

## 6. Port or hand off

Porting the approved option into Blade, a Filament theme or the project's templates is its own step, built from the design file. When the user asks to go ahead in this thread, port it here. Otherwise add it to the work order and hand over with `mig-relay`. Either way, keep the mockups out of the default branch (a tag such as `<slug>-mockups` keeps them reachable).
