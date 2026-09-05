# FSCinema Menu Boards for info-beamer Hosted

Live, resilient menu-board package for the schema-version-1 FSCinema manifest. It supports `combo`, `alacarte`, and `full` screens at 3840×1080 dual-HD horizontal, 2160×3840 4K vertical, 1920×1080 HD horizontal, and 3840×2160 4K horizontal.

The service sends `If-None-Match`, accepts empty 304 responses, validates new JSON before publishing it, atomically updates player state, caches media by URL plus content version, and retains the last valid manifest when a refresh fails. Combo images use each combo's `image_url` and appear in the image area above the name, description, and price. A neutral placeholder is used when `image_url` is null or empty.

## Hosted import

1. In info-beamer Hosted, open **Packages**, choose **Import package**, and upload `fscinema-menu-board.zip` (or import the repository URL if this directory is hosted in Git).
2. Review the requested network permission. It is required for the manifest endpoint and public media URLs.
3. Create a setup from **FSCinema Menu Boards**.
4. Configure the endpoint, Wellington location ID, screen ID, bearer token, and display profile. Keep refresh at 600 seconds to match `Cache-Control: private, max-age=600, must-revalidate`.
5. Save, assign the setup to one test device, and wait for synchronization.

The token field is visually masked in Hosted but is ultimately delivered to the device in `config.json`; use a dedicated, read-only player token and rotate it if exposed. Do not use an admin/service-role credential.

## Configuration

- **Screen:** Use `combo`, `alacarte`, or `full`; this becomes the endpoint's `screen_id` query value.
- **Display profile:** Must match the intended canvas. The player letterboxes safely if the physical output differs.
- **Playback mode:** `Configured screen` renders the selected manifest normally. `Alternate combo / a la carte` uses a `full` manifest and switches between full-screen combo and à-la-carte pages; configure `screen_id=full` and typically use 1920×1080.
- **Page duration:** Number of seconds each page remains visible in alternating mode; defaults to 25 seconds.
- **Show advertisements:** Downloads and rotates active, in-date advertising media in the advertisement region. If no valid advertisement is available, the region collapses and the menu uses the available space.
- **Debug status:** Shows LIVE/STALE and the current manifest version in the upper-left corner.

The endpoint's `screen.orientation` and source dimensions are retained as data, while the explicit Hosted display profile controls the physical composition. Configure the device/TV rotation separately for portrait installations.

## Rollout

1. Verify the test device reports LIVE and the expected manifest version.
2. Confirm all menu prices and category/combo order against the source system.
3. Add one combo `image_url` in the source and verify the image appears above that combo's price card after the next refresh.
4. Disconnect networking for longer than one refresh interval and confirm the last menu remains visible (STALE when debug is enabled).
5. Reconnect, confirm recovery, then assign the setup to a small pilot group.
6. Roll out by screen type in batches. Keep the previous setup assigned to no devices but available during the observation window.

For 4K output, use hardware and an info-beamer OS version with the required 4K image/video capabilities. Validate the exact HDMI mode and rotation on the production display before broad deployment.

## Rollback

1. Reassign affected devices to the previously known-good setup in Hosted.
2. Wait for device synchronization and verify the live preview/device screenshot.
3. If the player does not switch, reboot only the affected device from Hosted and recheck.
4. Keep the failed package version and logs for diagnosis; do not overwrite the known-good package. Rotate the player token only if credentials may have been exposed.

Cached state is scoped to the setup/package instance. A newly attached setup can start with an empty cache and will display “Waiting for menu data…” until its first successful request.

## Local verification

Run `python3 -m unittest discover -s tests -v`. For visual testing, run `python3 -m http.server 8765` and open `http://127.0.0.1:8765/preview/`. The committed fixtures are the verbatim Wellington responses supplied on 2026-09-03 and contain no credentials.

The package includes Poppins Bold under the SIL Open Font License; see `OFL.txt`.

## Version 1.0.0

Initial release with schema validation, ETag revalidation, offline retention, responsive layout profiles, and combo image slots.
