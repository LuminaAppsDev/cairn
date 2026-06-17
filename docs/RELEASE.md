# Cairn — Release Guide

How to ship Cairn on each distribution channel. This complements
[`DEVELOPMENT.md`](DEVELOPMENT.md) (dev setup, signing config, toolchains) and
the distribution decision in [`DESIGN.md` §10.3](DESIGN.md). It does **not**
repeat the signing/keystore setup — see DEVELOPMENT.md §3.3 (Android) and §3.4
(iOS).

> **Store requirements drift.** Apple/Google/F-Droid/Nextcloud change policies
> and version requirements regularly. Treat the version numbers and form names
> here as a starting point and confirm against the linked official docs before
> each release.

---

## 0. What ships

Cairn has **two independently-released artifacts**:

| Artifact | Stack | Licence | Channels | Status |
| --- | --- | --- | --- | --- |
| **Mobile app** | Flutter (Android + iOS), `io.github.theflipside.cairn` | MIT | F-Droid, sideload, Google Play, Apple App Store | shipping (Phases 1–5) |
| **Nextcloud web app** | classic Nextcloud app (PHP + Vue) | AGPL-3.0 | Nextcloud App Store | **not built yet — Phase 7**; §6 is forward-looking |

**Distribution philosophy (DESIGN.md §10.3):** the strict, no-compromise build
ships cleanest via **F-Droid / sideload** (plus a personal/community iOS build),
which also sidesteps most of the Google Play health-policy friction. Google Play
and the Apple App Store are possible but need careful store-listing and
data-use scoping. Decide per channel. Cairn is **not** a medical device — never
use diagnostic/treatment framing in any listing.

---

## 1. Common pre-release checklist

Do this once per release, before touching any channel:

- [ ] **Quality gate green** (DESIGN.md §13): `dart format --output=none
      --set-exit-if-changed .`, `dart analyze`, `flutter test`, and the binding
      `/review` + `/security-audit`.
- [ ] **Bump the version** in [`pubspec.yaml`](../pubspec.yaml):
      `version: X.Y.Z+BUILD`. `X.Y.Z` is the user-facing `versionName`; `BUILD`
      is the integer `versionCode` (Android) / build number (iOS) — **it must
      increase on every store upload**, even a re-upload of the same `X.Y.Z`.
- [ ] **Update [`CHANGELOG.md`](../CHANGELOG.md)** and tag the commit
      (`vX.Y.Z`).
- [ ] **Permission/data-use audit** — confirm the app still requests only what
      it uses (READ-only health types; no `WRITE_*`; see DESIGN.md §2). If the
      health types changed, the store declarations (Play/Apple) must be updated.
- [ ] **Privacy policy** published on a **public, non-geofenced HTTPS URL**
      (required by Apple and Google; good practice everywhere). It must state:
      what health data is read, that it is stored only in the user's own
      Nextcloud, that Cairn (the project) stores nothing, no advertising/no
      data-mining, and how to delete data (delete the `/Cairn/` folder /
      disconnect). Keep the source as `docs/PRIVACY.md` → publish it.
- [ ] **Secrets check** — the release keystore + `key.properties` are present
      locally and **never** committed (gitignored + `.githooks/pre-commit`).
      Back up the keystore securely; losing it means you can never update the
      app under the same identity.

---

## 2. F-Droid (primary channel)

F-Droid is the cleanest home for Cairn: it's a FOSS-only repository, and Cairn
is MIT, ships **no** Google Play Services / Firebase / proprietary blobs, does
no tracking, and talks only to the **user's own** Nextcloud (so it should not
attract the `NonFreeNet` / `Tracking` anti-features). Reading Health Connect is
an on-device API call, not a proprietary dependency bundled in the APK.

There are two routes. The **official repo** gives discoverability; a
**self-hosted repo** gives full control and a faster cadence. You can do both.

### 2a. Official F-Droid repository

F-Droid **builds your app from source** on their infrastructure and signs it
with the F-Droid key (or verifies a reproducible build against your own
signature). Requirements: an OSI-approved licence (MIT ✓), a tagged source
release, and no proprietary dependencies or anti-features.

Flutter is supported. The build recipe pulls the Flutter SDK via either a
`srclibs: - flutter@stable` entry or Flutter vendored as a git submodule; see
the official **`build-flutter.yml`** template. A typical recipe:

- `sudo`/`prebuild` to fetch + pin the Flutter SDK version,
- remove non-Android platform dirs (`ios`, `linux`, `macos`, `web`, `windows`),
- `build: flutter build apk` (or per-ABI),
- `output:` pointing at the built APK.

Steps:

1. Read **Submitting to F-Droid (Quick Start)** and the **Inclusion Policy**.
2. Make sure each release is a **git tag** with a bumped `versionCode`.
3. Open an **RFP (Request For Packaging)** issue, then a merge request adding a
   metadata file to the **`fdroiddata`** repo (`metadata/io.github.theflipside.cairn.yml`):
   licence, source/repo URLs, `Build:` block (the Flutter recipe above),
   `AutoUpdateMode`/`UpdateCheckMode: Tags`, and `CurrentVersion`/`CurrentVersionCode`.
4. F-Droid CI builds it; iterate on the MR until it builds clean; on merge it's
   published and auto-tracks new tags.
5. **(Optional) Reproducible builds** — to ship *your* signature (so sideload
   and F-Droid APKs are interchangeable), make the build reproducible: pin the
   Flutter SDK to a fixed path (`flutter config --android-sdk …`) so no absolute
   paths leak in, then add `Builds: …` with your signing fingerprint.

Sources: [Submitting Quick Start](https://f-droid.org/en/docs/Submitting_to_F-Droid_Quick_Start_Guide/),
[Build Metadata Reference](https://f-droid.org/en/docs/Build_Metadata_Reference/),
[`build-flutter.yml` template](https://gitlab.com/fdroid/fdroiddata/-/blob/master/templates/build-flutter.yml),
[Reproducible Builds](https://f-droid.org/en/docs/Reproducible_Builds/).

### 2b. Self-hosted F-Droid repo

Host your own repo (e.g. on `git.fiedler.live` or any static host); users add
the repo URL/QR to their F-Droid client. You sign the APKs; full control, no
review queue.

1. `pip install fdroidserver` (or use the Docker image).
2. `fdroid init` in an empty dir (creates the repo + signing key on first run).
3. Drop your signed release APKs into `repo/`.
4. `fdroid update -c` to generate the index, then publish the `repo/` directory
   over HTTPS.
5. Share the repo URL; updates = new APK + `fdroid update`.

Source: [`fdroidserver` / Setup an F-Droid app repo](https://f-droid.org/en/docs/Setup_an_F-Droid_App_Repo/).

### Cairn F-Droid notes

- `minSdk = 26` (Health Connect). Fine for F-Droid.
- If you bump the `health` package, re-check it pulls in no non-free transitive
  dependency (would block official inclusion).
- Background sync (WorkManager) and `READ_HEALTH_DATA_IN_BACKGROUND` are fine on
  F-Droid — there's no health-data review like the stores.

---

## 3. Sideload / direct APK

The simplest strict channel: a signed APK users install directly (after
enabling "install unknown apps").

1. Ensure `android/key.properties` + keystore are in place (DEVELOPMENT.md §3.3).
2. `flutter build apk --release` (or `--split-per-abi` for smaller downloads).
3. Publish `build/app/outputs/flutter-apk/app-release.apk` on the project's
   releases page (Forgejo/GitHub) alongside the `vX.Y.Z` tag + checksums.
4. **Always sign with the same keystore** — Android refuses updates signed by a
   different key.

This is also the build to feed a self-hosted F-Droid repo (§2b).

---

## 4. Google Play Store

Possible, but read the **policy tension** below first — DESIGN.md §10.3 treats
Play as optional, not the primary channel.

### Prerequisites
- Google Play Console account (one-time **$25** registration; identity
  verification required).
- Public privacy-policy URL (§1).

### One-time setup
1. Create the app in Play Console; choose Play App Signing (Google holds the app
   signing key; you keep an upload key).
2. Fill the **store listing**, content rating, and **Data safety** form
   (declare that health data is read, stored in the user's Nextcloud, not
   shared, not sold).
3. Complete the **Health apps declaration** / **Health permissions**
   declaration: justify each `android.permission.health.*` type — *why* it's
   needed, the *user benefit*, and the *privacy/security* measures. This is
   required for every publishing request (new app **and** updates that change
   data types), and `READ_HEALTH_DATA_IN_BACKGROUND` gets specific scrutiny.

### Per release
1. `flutter build appbundle` (Play requires an `.aab`).
2. **Target API level:** since **31 Aug 2025**, new apps and updates must
   **target Android 15 (API 35)** or higher (confirm the current floor — it
   rises ~yearly). This is a recurring treadmill: each year bump
   `targetSdk` + re-test.
3. Upload to an **internal → closed → open** testing track, then promote to
   production.
4. Re-confirm the Health declaration + Data safety if anything changed.

### Cairn gotchas — the health-policy tension
Google Play restricts using health-permission data with apps that **sync health
data between platforms/devices** and restricts **headless/background** access.
Cairn's "funnel HealthKit + Health Connect into the user's own Nextcloud" +
background sync sits awkwardly with the letter of this policy. To reduce
friction: frame the listing as **personal backup/aggregation into the user's
own storage** (not a cross-device sync service for third parties), give strong
per-permission justifications, ship prominent in-app disclosure + affirmative
consent, and request the minimum permission set. If the declaration is rejected,
F-Droid/sideload remain the clean path.

Sources: [Publish your health app](https://developer.android.com/health-and-fitness/health-connect/publish),
[Android health permissions guidance/FAQ](https://support.google.com/googleplay/android-developer/answer/12991134),
[Health content & services policy](https://support.google.com/googleplay/android-developer/answer/16679511),
[Target API requirement](https://developer.android.com/google/play/requirements/target-sdk).

---

## 5. Apple App Store

### Prerequisites
- **Apple Developer Program** membership (**$99/year**).
- A **Mac with Xcode** (no way around this for building/signing iOS).
- Public privacy-policy URL (§1).

### One-time setup
1. Register the bundle id `io.github.theflipside.cairn` and enable the
   **HealthKit** capability/entitlement.
2. Create the app record in **App Store Connect**; configure signing
   (automatic, or manual with a distribution certificate + provisioning
   profile).
3. Confirm `NSHealthShareUsageDescription` is set (it is) and reads clearly —
   App Review checks the prompt copy.
4. Fill **App Privacy** ("privacy nutrition label") details and link the privacy
   policy.

### Per release
1. `flutter build ipa` (or archive in Xcode) → upload via Xcode/Transporter.
2. Distribute via **TestFlight** for beta, then submit for **App Review** →
   release.
3. Bump the build number every upload.

### HealthKit review rules (App Store Review Guidelines §1.4.1, §5.1.3)
- A **privacy policy detailing health-data use is required**.
- Health/fitness data **may not be used for advertising, marketing, or data
  mining** — only health management (or research with permission).
- **Apple Health data may not be stored in iCloud.** Cairn stores in the
  **user's own Nextcloud**, which is fine — it's *Apple's* cloud that's barred.
- No medical-device/diagnostic claims. Background delivery (`BGAppRefreshTask`)
  should be justified by the sync purpose.

Sources: [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/),
[App Privacy details](https://developer.apple.com/app-store/app-privacy-details/),
[Protecting access to health data](https://support.apple.com/guide/security/protecting-access-to-users-health-data-sec88be9900f/web).

---

## 6. Nextcloud App Store (the PHP + Vue app — Phase 7, not built yet)

Forward-looking: this is the path for the optional Nextcloud web app once it
exists (DESIGN.md §7). It's an **AGPL** classic server-side app, distributed via
[apps.nextcloud.com](https://apps.nextcloud.com/), installed by self-hosters
onto their own instance.

### App structure
- `appinfo/info.xml` declares the app id, metadata, AGPL licence, and crucially
  the **compatibility window**:
  ```xml
  <dependencies>
      <php min-version="8.1" max-version="8.4"/>
      <nextcloud min-version="30" max-version="31"/>
  </dependencies>
  ```
  Validated against the [`info.xsd`](https://apps.nextcloud.com/schema/apps/info.xsd) schema.

### One-time setup (register + signing certificate)
Nextcloud App Store releases are **cryptographically signed**:
1. Generate an app keypair (OpenSSL) — by convention under
   `~/.nextcloud/certificates/`.
2. Post the **Certificate Signing Request** to
   [`nextcloud/app-certificate-requests`](https://github.com/nextcloud/app-certificate-requests)
   (with a public email on your GitHub account so they can verify ownership).
3. Once countersigned, **register the app id** on the App Store via its REST API
   or the "Register app" web form (it asks for the certificate + a signature
   over the app id to prove you hold the private key).

### Per release
1. Build a release **tarball** of the app.
2. **Sign** it (OpenSSL signature over the tarball) — or use **`krankerl`**, a
   CLI that packages, signs, and publishes in one standardized flow (it finds
   keys in `~/.nextcloud/certificates` from the app id in `info.xml`).
3. Upload the release via the App Store **REST API** or the "Upload release" web
   form; set the download URL + the supported version range from `info.xml`.

Sources: [Nextcloud App Store developer guide](https://nextcloudappstore.readthedocs.io/en/latest/developer.html),
[Code signing](https://docs.nextcloud.com/server/stable/developer_manual/app_publishing_maintenance/code_signing.html),
[Release automation](https://docs.nextcloud.com/server/latest/developer_manual/app_publishing_maintenance/release_automation.html),
[krankerl](https://github.com/ChristophWurst/krankerl).

---

## 7. Keeping the Nextcloud app current (version-tracking maintenance)

This is the **accepted maintenance tax** of the Nextcloud path (DESIGN.md §7,
§14): an app whose `info.xml` `max-version` is below a newly-installed Nextcloud
major is **automatically disabled on upgrade** until you publish a compatible
release. Self-hosters upgrade on their own schedule, so a stale app silently
disappears for them.

**Cadence.** Nextcloud ships roughly **three major releases per year** (e.g. 30,
31, 32…). Each has a developer **"Upgrade to Nextcloud NN"** guide listing
breaking changes and removed APIs.

**Per new major — the routine:**
1. Read the **[Upgrade to Nextcloud NN](https://docs.nextcloud.com/server/latest/developer_manual/app_publishing_maintenance/app_upgrade_guide/)**
   guide for that release.
2. Spin up a dev instance on the new major (DEVELOPMENT.md §4.2) and run the
   app; fix any deprecations/removals.
3. Run **`occ app:check-code <appid>`** to catch use of private/removed APIs.
4. Bump `info.xml` `<nextcloud max-version="NN"/>` (and the `<php>` range if the
   new major moved its PHP floor).
5. Bump the app `<version>`, re-sign, and upload a new release (§6 / `krankerl`).
6. Keep a **CI matrix** building/testing the app against the supported Nextcloud
   majors so breakage surfaces before users hit it.

Because the app is **read-only over the `/Cairn/` files** and never authoritative
(DESIGN.md §7), a lapse is low-stakes: users keep their data and the mobile app;
they just lose the optional web frontend until the next compatible release.

---

## 8. Channel decision (recap)

| Channel | Effort | Health-policy friction | Recommendation |
| --- | --- | --- | --- |
| **F-Droid** (official + self-hosted) | Medium | None | **Primary** — the clean strict path |
| **Sideload / direct APK** | Low | None | Always provide |
| **Google Play** | High | High (cross-platform-sync tension) | Optional; scope listing carefully |
| **Apple App Store** | High (needs Mac + $99/yr) | Medium (HealthKit rules) | Optional; for iOS reach |
| **Nextcloud App Store** | Medium | None | Phase 7, when the web app exists |

See also: [`DESIGN.md`](DESIGN.md) §10 (privacy/compliance) and §15 (phases);
[`DEVELOPMENT.md`](DEVELOPMENT.md) for build/signing setup.
