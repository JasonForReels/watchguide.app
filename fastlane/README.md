fastlane documentation
----

# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

## iOS

### ios store_media

```sh
[bundle exec] fastlane ios store_media
```

Replace the iPhone 6.9" and iPad 13" screenshots and previews for a version

Usage: fastlane store_media version:5.6 locale:en-GB (locale defaults to en-US)

### ios tv_media

```sh
[bundle exec] fastlane ios tv_media
```

Apple TV: set the tvOS version, upload its listing text and screenshots (AppStoreScreenshots/tvOS/<locale>/)

Usage: fastlane tv_media version:5.6.1

### ios listing

```sh
[bundle exec] fastlane ios listing
```

Upload the listing text in fastlane/metadata/ (description, keywords, What's New, URLs)

### ios submit

```sh
[bundle exec] fastlane ios submit
```

Attach a build to a version and submit it for App Review

Usage: fastlane submit build:10 (version defaults to STORE_VERSION)

### ios upload_previews

```sh
[bundle exec] fastlane ios upload_previews
```

Replace the App Preview videos for a version

### ios media_status

```sh
[bundle exec] fastlane ios media_status
```

Report the screenshots and previews App Store Connect holds for a version

### ios fetch_listing

```sh
[bundle exec] fastlane ios fetch_listing
```

Save the current listing text for a version into fastlane/metadata/<locale>/

### ios territory_status

```sh
[bundle exec] fastlane ios territory_status
```

Report whether the app is available in a territory (default: CHN)

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
