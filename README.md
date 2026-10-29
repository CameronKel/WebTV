# WebTV

A tiny Apple TV app that opens one website full screen and lets you drive it with the Siri Remote.

## Remote controls

| Remote | What it does |
| --- | --- |
| Swipe on touch surface | Move the cursor. Push against a screen edge to scroll. |
| Click | Click whatever is under the cursor. Text boxes open the on-screen keyboard. |
| D-pad / edge clicks | Scroll up, down, left, right |
| Menu / Back | Browser back. Exits the app when there's nothing to go back to. |
| Play/Pause | Go back to the home page (also retries after an error) |

## 1. Set your website

Edit `homeURL` in [Sources/Config.swift](Sources/Config.swift). You can do this on github.com with the pencil icon; no Mac needed.

The app is locked to that site (and its subdomains): links that lead to other websites do nothing. If your site signs you in through another domain, add that domain to `extraAllowedHosts` in the same file.

## 2. Build it on GitHub (free)

1. Create a new GitHub repository and upload this folder's contents (including the hidden `.github` folder).
   Public repos get unlimited free macOS build minutes; private repos get a monthly allowance that's plenty for this.
2. Every push to `main` builds the app. You can also start a build from **Actions → Build tvOS app → Run workflow**.
3. When the run finishes, download the **WebTV-ipa** artifact at the bottom of the run page and unzip it to get `WebTV.ipa`.

## 3. Install and keep it signed with atvloadly

[atvloadly](https://github.com/bitxeno/atvloadly) signs the app with your free Apple ID, installs it over Wi‑Fi, and re-signs it before the 7-day free-account expiry.

- It runs as a Docker container on **Linux** with host networking (it needs to discover the Apple TV on your network). Best on an always-on box: a Raspberry Pi, a NAS, or a home server. It can't refresh the app while the machine running it is off.
- Follow the install steps in atvloadly's README, open its web page, then pair your Apple TV:
  **Apple TV → Settings → Remotes and Devices → Remote App and Devices**, and pick it in atvloadly.
- Sign in with your Apple ID in atvloadly (use a spare Apple ID if you'd rather not use your main one), upload `WebTV.ipa`, and install.

Free Apple ID limits: apps expire after 7 days (atvloadly refreshes them for you) and you can have 3 sideloaded apps at once.

## Things to know

- tvOS has no official web view. This app uses the UIWebView that's still inside tvOS but hidden from developers. That's why it can't go on the App Store, and a future tvOS update could remove it; if that happens the app shows a message instead of a page.
- Video sites with DRM (Netflix, Disney+, etc.) won't play. Ordinary pages, dashboards, slides and most plain video should be fine.
- The app has no icon yet, so it shows a blank tile on the home screen.
