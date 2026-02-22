# Animated Album Art — Feasibility Research

## Summary

Using animated (motion) album art from Apple Music in Shfl is **not currently possible through any official, supported API**. Apple does not expose the animated artwork video URLs to third-party apps. However, iOS 26 introduces a new API (`MPMediaItemAnimatedArtwork`) for publishing animated artwork to the system lock screen — which could be useful if we can source the video ourselves.

---

## Current Shfl Implementation

- **Album art display**: `AlbumArtCard` renders a static image via `AsyncImage(url:)` from a `Song.artworkURL`
- **Artwork loading**: `ArtworkCache` fetches `MusicKit.Artwork` objects via `MusicLibraryRequest<Song>`, then generates image URLs with `artwork.url(width:height:)`
- **Color extraction**: `AlbumArtColorExtractor` pulls `backgroundColor`, `primaryTextColor`, etc. from MusicKit `Artwork` for theming
- All artwork is **static images** — no video or animation support exists today

---

## Three Avenues Explored

### 1. MusicKit `Artwork` / `Song` Properties

The MusicKit `Artwork` struct provides:
- `url(width:height:)` — static image URL
- `backgroundColor`, `primaryTextColor`, `secondaryTextColor`, etc. — colors
- `maximumWidth`, `maximumHeight` — sizing

**No properties exist for animated/motion artwork.** There is no `animatedArtwork`, `editorialVideo`, or motion-related property on `Song`, `Album`, or `Artwork` in MusicKit.

### 2. Apple Music REST API `editorialVideo`

Apple Music internally uses an `editorialVideo` attribute on albums containing:
- `motionDetailTall` — 3:4 aspect video (m3u8 URL)
- `motionDetailSquare` — 1:1 aspect video (m3u8 URL)
- `motionArtistFullscreen16x9`, `motionArtistWide16x9`, `motionArtistSquare1x1`

Each contains an HLS (m3u8) video URL that Apple renders as animated album art.

**However, Apple has explicitly stated this data is not available to third-party apps.** An Apple engineer confirmed on the Developer Forums: _"The data you are asking about is not made available by Apple Music API for third-party apps."_ The `extend=editorialVideo` parameter is ignored by the public API.

An unofficial Python tool ([bunnykek/Fetcher](https://github.com/bunnykek/Fetcher)) demonstrates accessing this data via Apple's internal `amp-api.music.apple.com` endpoint, downloading HEVC video at 2048x2732, 30fps, 10-bit color. This is **not a supported approach** — it uses an undocumented internal API that could break at any time and likely violates Apple's terms of service.

### 3. `MPMediaItemAnimatedArtwork` (iOS 26+)

New in iOS 26 (WWDC 2025), this MediaPlayer framework API allows apps to **publish** animated artwork to system surfaces (lock screen, Control Center).

**How it works:**
- Create an `MPMediaItemAnimatedArtwork` with:
  - A unique `artworkID`
  - A `previewImageRequestHandler` (returns a placeholder `CGImage` for a given size)
  - A `videoAssetFileURLRequestHandler` (returns a **local file URL** to a video)
- Set it on `MPNowPlayingInfoCenter.default().nowPlayingInfo` via:
  - `MPNowPlayingInfoProperty1x1AnimatedArtwork` (square)
  - `MPNowPlayingInfoProperty3x4AnimatedArtwork` (tall)

**Critical limitation:** This API is for **providing** your own video assets to the system. It does **not** retrieve animated artwork from Apple Music. You must supply the video file yourself. The video URL must be a local file URL — the asset needs to be downloaded before providing it.

**Also important:** `ApplicationMusicPlayer` (which Shfl uses) does **not** automatically display animated artwork on the lock screen. Apple Music's own app handles this internally, but third-party MusicKit apps must explicitly adopt `MPMediaItemAnimatedArtwork`.

---

## What Not Having Animated Artwork Available

| Approach | Feasible? | Notes |
|----------|-----------|-------|
| MusicKit `Artwork` properties | No | Only provides static image URLs and colors |
| Public Apple Music API `editorialVideo` | No | Explicitly blocked for third-party apps |
| Internal `amp-api` endpoint | Technically yes, but unsupported | Undocumented, could break, likely violates ToS |
| `MPMediaItemAnimatedArtwork` (iOS 26) | For lock screen only | Requires you to supply your own video — doesn't fetch from Apple Music |
| Wait for future MusicKit updates | Possible | Apple may expose this in a future iOS release |

---

## Recommendations

### Short Term: No Action
There is no official way to retrieve animated artwork video URLs from Apple Music for third-party apps. Pursuing the unofficial internal API approach would be fragile and risky.

### Medium Term: iOS 26 Lock Screen Support
When targeting iOS 26+, we could adopt `MPMediaItemAnimatedArtwork` for songs where we can source animated video content (e.g., if we had our own video assets, or if Apple opens the API in the future). This would only affect the **system lock screen**, not our in-app `AlbumArtCard`.

### Long Term: Monitor Apple's API Evolution
Apple may expand MusicKit to include animated artwork retrieval in a future release, especially given that:
- iOS 26 introduced `MPMediaItemAnimatedArtwork` as a publication mechanism
- The infrastructure for motion artwork exists in Apple Music
- There's clear developer demand (forum posts requesting this feature)

If/when Apple exposes animated artwork through MusicKit, the integration points in Shfl would be:
1. **`AlbumArtCard`** — Replace or augment `AsyncImage` with an `AVPlayer`-backed video view when animated art is available
2. **`Song` model** — Add an optional `animatedArtworkURL: URL?` property
3. **`ArtworkCache`** — Extend to cache/manage video assets alongside static artwork
4. **`AlbumArtColorExtractor`** — No change needed (colors come from the static `Artwork` object regardless)
5. **Lock screen** — Adopt `MPMediaItemAnimatedArtwork` to publish the video to system surfaces

---

## Sources

- [MPMediaItemAnimatedArtwork — Apple Developer Documentation](https://developer.apple.com/documentation/mediaplayer/mpmediaitemanimatedartwork)
- [Providing animated artwork for media items — Apple Developer Documentation](https://developer.apple.com/documentation/mediaplayer/providing-animated-artwork-for-media-items)
- [editorialVideo not available — Apple Developer Forums](https://developer.apple.com/forums/thread/696843)
- [9to5Mac — Third-party animated artwork on lock screen](https://9to5mac.com/2025/06/15/iphone-apple-music-lock-screen-animated-artwork-third-party-apps/)
- [bunnykek/Fetcher — Unofficial animated artwork downloader](https://github.com/bunnykek/Fetcher)
- [Create motion artwork for Apple Music — Apple Music for Artists](https://artists.apple.com/support/5544-create-motion-artwork)
