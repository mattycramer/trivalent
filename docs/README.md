<p align="center">
  <a href="https://github.com/secureblue/Trivalent">
    <img src="https://github.com/secureblue/Trivalent/blob/live/trivalent.png" alt="Trivalent logo" href="https://github.com/secureblue/Trivalent" width=180 />
  </a>
</p>

<h1 align="center">Trivalent</h1>

[![build-debian](https://github.com/secureblue/Trivalent/actions/workflows/build.yml/badge.svg)](https://github.com/secureblue/Trivalent/actions/workflows/build.yml)
[![Runners by - runs-on.com](https://img.shields.io/badge/Runners-runs--on.com-blue?style=flat)](https://runs-on.com/)
[![Egress auditing by - stepsecurity.io](https://img.shields.io/badge/Egress_auditing-stepsecurity.io-7037f5)](https://stepsecurity.io)
[![OpenSSF Scorecard](https://api.scorecard.dev/projects/github.com/secureblue/Trivalent/badge)](https://scorecard.dev/viewer/?uri=github.com/secureblue/Trivalent)

A security-focused, Chromium-based browser for desktop Linux inspired by [Vanadium](https://github.com/GrapheneOS/Vanadium). This fork targets Debian x86_64.

## Scope

### In scope

* Desktop-relevant patches from Vanadium (located in vanadium_patches)
* Changes that increase hardening against known and unknown vulnerabilities
* Changes that make secondary browser features opt-in instead of opt-out (for example, making the password manager and search suggestions opt-in)
* Changes that disable opt-in metrics and data collection, so long as they have no security implications

### Out of scope

* Any changes that sacrifice security for "privacy" (for example, enabling MV2) <sup>[why?](https://developer.chrome.com/docs/extensions/develop/migrate/improve-security)</sup>
* Any novel functionality that is unrelated to security

## Installation

Upstream support is provided via [secureblue](https://github.com/secureblue/secureblue/). This fork is Debian‑only and is intended for local builds on modern Debian x86_64. Fedora/secureblue packaging is not supported here.

For Debian (x86_64) local builds based on ungoogled-chromium, see
`docs/BUILDING_DEBIAN.md`.

## Post-install

Some additional preferences are added to `chrome://settings/security`, these provide additional security and privacy controls should they be needed. An example of one toggle is the `Network Service Sandbox` (disabled by default), which is known to occasionally [clear cookies on exit](https://secureblue.dev/faq#trivalent-net-sandbox).
\
There is also a Website Dark Mode preference added to `chrome://settings/appearance`.
\
\
Additionally, the following flags are available that provide extra hardening but may cause breakage or usability issues:

* `chrome://flags/#show-punycode-domains`
* `chrome://flags/#clear-cross-origin-referrers`

Other flags are also provided for compatibility should you experience an issue related to some of the hardening enabled by default. For example, the default pop-up blocker is very strict, it may optionally be disabled `chrome://flags/#strict-popup-blocking` to improve usability.

## Content Blocking

Trivalent comes by default with content filtering enabled using chromium's internal subresource filter. The lists used for content filtering can be found in the [trivalent-subresource-filter](https://github.com/secureblue/trivalent-subresource-filter) repository.
\
If you want to contribute to the subresource filter, example suggesting a new list, visit [here](https://github.com/secureblue/trivalent-subresource-filter).

## Contributing

Follow the [contributing documentation](CONTRIBUTING.md), and make sure to respect the [CoC](CODE_OF_CONDUCT.md).
