App setup
=========

Before Background Assets works in a device build, the app needs the right toolchain, a few Info.plist keys, two
entitlements and a downloader extension. This page sets each one up for Apple-hosted packs, and says what happens when
one is missing. Self-hosted packs need more keys: see :doc:`self-hosting`.

Toolchains
----------

- The plugin and its downloader extension are built with Solar2D 3733 and Xcode 27.0.
- The plugin's archive is meant for apps built with Solar2D 3733 and Xcode 27 (minimum iOS 15.0), and for apps built
  with Solar2D 3731 and Xcode 26.4 (minimum iOS 13.0).
- An app built with Xcode 27 (Solar2D 3733) must target iOS 15.0 or later: set ``MinimumOSVersion`` to ``"15.0"`` or
  higher. Otherwise App Store Connect rejects the app in processing, with error 90208, because the Xcode 27 SDK sets
  the executable's minimum to 15.0 whatever ``MinimumOSVersion`` says.
- The downloader extension's deployment target is iOS 26.0. The plugin's library loads from iOS 13, since it
  weak-links BackgroundAssets, and reports unsupported below iOS 26 (see :doc:`api`).
- An app with a minimum of iOS 15.0 that carries the iOS 26.0 extension passes App Store Connect processing. Whether an
  app with a lower minimum that carries the extension does has not been tested.

Info.plist keys
---------------

Set them in the ``plist`` table of ``build.settings``' ``iphone`` table:

- ``BAAppGroupID``: the app group the app and its downloader extension share;
- ``BAHasManagedAssetPacks``: ``true``;
- ``BAUsesAppleHosting``: ``true`` for Apple-hosted packs. Self-hosting sets it to ``false`` and adds more keys (see
  :doc:`self-hosting`).

Entitlements
------------

Set them in the ``entitlements`` table of ``build.settings``' ``iphone`` table. Solar2D's packager adds neither:

- ``com.apple.security.application-groups``: an array holding the app group;
- ``com.apple.developer.team-identifier``: your team id.

The app's App ID needs the App Groups capability with that app group, and its provisioning profile must carry it.

Together, for the app ``com.example.myapp`` of team ``ABCDE12345``:

.. code-block:: lua

   settings =
   {
       iphone =
       {
           plist =
           {
               MinimumOSVersion = "15.0",
               BAAppGroupID = "group.com.example.myapp",
               BAHasManagedAssetPacks = true,
               BAUsesAppleHosting = true,
           },
           entitlements =
           {
               ["com.apple.security.application-groups"] = { "group.com.example.myapp" },
               ["com.apple.developer.team-identifier"] = "ABCDE12345",
           },
       },
   }

The downloader extension
------------------------

Managed Background Assets needs a downloader extension in the app's ``Extensions/`` folder. Apple hosting uses the
``StoreDownloaderExtension`` flavour, self-hosting the ``ManagedDownloaderExtension`` one. The extension accepts every
pack the system offers it.

``extension/build.sh``, in the plugin's repository
(`depilz/solar2d-plugin-background-assets <https://github.com/depilz/solar2d-plugin-background-assets>`_), builds the
flavour you choose, signs it with the extension's own provisioning profile and writes it into your Solar2D project as
``<project>/Extensions/<suffix>.appex``. Run it before the Solar2D build: the packager copies an appex built by
``extension/build.sh`` into the app unchanged, and signs the app without ``--deep``, so the extension keeps its own
signature.

.. code-block:: text

   extension/build.sh --hosting apple|self --app-id <bundle id> --app-group <group id>
     --profile <extension .mobileprovision> --version <CFBundleShortVersionString> --build <CFBundleVersion>
     --project <Solar2D project dir> [--suffix <component>] [--identity <SHA-1>] [--display-name <name>] [--work <dir>]

.. list-table::
   :header-rows: 1

   * - Option
     - Value
     - Default
   * - ``--hosting``
     - ``apple`` (``StoreDownloaderExtension``) or ``self`` (``ManagedDownloaderExtension``)
     - required
   * - ``--app-id``
     - the app's bundle id; the extension's is ``<app id>.<suffix>``
     - required
   * - ``--app-group``
     - the app group, the same as the app's ``BAAppGroupID``
     - required
   * - ``--profile``
     - the extension's provisioning profile
     - required
   * - ``--version``
     - the extension's ``CFBundleShortVersionString``
     - required
   * - ``--build``
     - the extension's ``CFBundleVersion``
     - required
   * - ``--project``
     - the Solar2D project folder, the one holding ``build.settings``, outside the plugin's repository
     - required
   * - ``--suffix``
     - the last component of the extension's bundle id: letters, digits and ``-``
     - ``BADownloader``
   * - ``--identity``
     - the SHA-1 of the signing certificate
     - the first valid code-signing identity whose certificate the profile carries
   * - ``--display-name``
     - the extension's ``CFBundleDisplayName``
     - the suffix
   * - ``--work``
     - a work folder outside the plugin's repository, whose parent exists
     - a temporary folder, deleted unless the build fails

The Xcode it uses is ``DEVELOPER_DIR``'s, by default ``/Applications/Xcode.app/Contents/Developer``.

For the app ``com.example.myapp``:

.. code-block:: text

   extension/build.sh --hosting apple --app-id com.example.myapp --app-group group.com.example.myapp \
     --profile BADownloader.mobileprovision --version 1.0.0 --build 1 --project ~/Projects/MyApp

writes ``~/Projects/MyApp/Extensions/BADownloader.appex``, the extension ``com.example.myapp.BADownloader``.

Exit codes:

- 0: built; it prints the path it wrote;
- 1: the build or the signing failed; when the build or the signing itself fails, the message names its log, in the
  work folder, which is kept;
- 2: a usage or precondition error, before anything is built: an option missing or wrong; the project folder without
  ``build.settings`` or inside the plugin's repository; a profile that cannot be read, has expired, has no team, is
  not for ``<team id>.<app id>.<suffix>``, lacks the app group or is an ad hoc profile; no Xcode; no signing identity.

The extension needs, in your Apple developer account:

- its own App ID, ``<app id>.<suffix>`` (``com.example.myapp.BADownloader`` by default), with the App Groups
  capability and the app's app group;
- its own Development or App Store provisioning profile for that App ID. ``extension/build.sh`` refuses an ad hoc
  profile, an expired one, one without the app group and one for another App ID, with exit code 2.

The extension must sit in ``Extensions/``, never ``PlugIns/``, and must carry a ``CFBundleDisplayName``, which
``extension/build.sh`` sets (``--display-name``).

``extension/build.sh`` also gives the extension the rest of what it needs: ``EXExtensionPointIdentifier`` set to
``com.apple.background-asset-downloader-extension`` (under ``EXAppExtensionAttributes`` in its Info.plist), and, in
its signature, the ``com.apple.security.application-groups`` entitlement with the app group, its
``application-identifier`` and ``com.apple.developer.team-identifier``. None of the setup on this page needs a
change to Solar2D.

What a missing item causes
--------------------------

.. list-table::
   :header-rows: 1

   * - Missing or wrong
     - What happens
   * - ``com.apple.developer.team-identifier`` entitlement
     - The app's own download requests never start: they stay at "Awaiting status updates…". Prefetch packs still
       arrive at install.
   * - The extension in ``PlugIns/`` in place of ``Extensions/``
     - App Store Connect rejects the upload: ITMS-91179.
   * - ``CFBundleDisplayName`` in the extension
     - App Store Connect rejects the upload: ITMS-90360.
   * - ``MinimumOSVersion`` below 15.0 in an app built with Xcode 27
     - App Store Connect rejects the app in processing: 90208.
   * - ``BAHasManagedAssetPacks``
     - ``getCapabilities().hosting`` is nil (see :doc:`api`).
   * - The extension's profile without the app group, or not for ``<app id>.<suffix>``
     - ``extension/build.sh`` exits with code 2.
   * - ``BAAppGroupID``
     - Required. Its failure was not observed.
   * - ``BAUsesAppleHosting``, for Apple hosting
     - Required. Its failure was not observed.
   * - ``com.apple.security.application-groups`` entitlement
     - Required. Its failure was not observed.
   * - The downloader extension
     - Required. Its failure was not observed.
   * - ``EXExtensionPointIdentifier`` or the app-group entitlement in the extension
     - Required; ``extension/build.sh`` sets both. Its failure was not observed.

Self-hosting has two failures of its own, a missing ``BAInitialDownloadRestrictions`` and a missing Local Network
permission: see :doc:`self-hosting`.
