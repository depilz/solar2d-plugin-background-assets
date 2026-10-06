App setup
=========

For Background Assets to work in a device build, the app needs the right toolchain, a few Info.plist keys, two
entitlements and a downloader extension. This page sets up each one for Apple-hosted packs and lists what happens when
one is missing. Self-hosted packs need more keys (see :doc:`self-hosting`).

Toolchains
----------

- The plugin and its downloader extension are built with Solar2D 3733 and Xcode 27.0.
- The plugin's archive is meant for apps built with Solar2D 3733 and Xcode 27 (minimum iOS 15.0) or with Solar2D 3731
  and Xcode 26.4 (minimum iOS 13.0).
- The downloader extension's deployment target is iOS 26.0. The plugin's library weak-links BackgroundAssets, so it
  loads from iOS 13 and reports unsupported below iOS 26 (see :doc:`api`).
- An app with a minimum of iOS 15.0 that carries the iOS 26.0 extension passes App Store Connect processing. An app
  with a lower minimum that carries the extension has not been tested.

.. warning::

   An app built with Xcode 27 (Solar2D 3733) must target iOS 15.0 or later: set ``MinimumOSVersion`` to ``"15.0"`` or
   higher. Otherwise App Store Connect rejects the app in processing with error 90208: the Xcode 27 SDK sets the
   executable's minimum to 15.0, whatever ``MinimumOSVersion`` says.

Info.plist keys
---------------

Set them in the ``plist`` table of ``build.settings``' ``iphone`` table:

- ``BAAppGroupID``: the app group the app and its downloader extension share;
- ``BAHasManagedAssetPacks``: ``true``;
- ``BAUsesAppleHosting``: ``true`` for Apple-hosted packs. Self-hosting sets it to ``false`` and adds more keys (see
  :doc:`self-hosting`).

Entitlements
------------

Solar2D's packager adds neither, so set them in the ``entitlements`` table of ``build.settings``' ``iphone`` table:

- ``com.apple.security.application-groups``: an array holding the app group;
- ``com.apple.developer.team-identifier``: your team id.

.. warning::

   Without the team id, the app's own download requests never start. Prefetch packs still arrive at install, so the
   gap is easy to miss.

The app's App ID needs the App Groups capability with that app group, and its provisioning profile must carry it.

Together, the settings for the app ``com.example.myapp`` of team ``ABCDE12345`` are:

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
``StoreDownloaderExtension`` flavour and self-hosting uses ``ManagedDownloaderExtension``. The extension accepts every
pack the system offers it.

``extension/build.sh``, in the plugin's repository
(`depilz/solar2d-plugin-background-assets <https://github.com/depilz/solar2d-plugin-background-assets>`_), builds the
flavour you choose, signs it with the extension's own provisioning profile and writes it into your Solar2D project as
``<project>/Extensions/<suffix>.appex``. Run it before the Solar2D build: the packager copies the appex the script builds
into the app unchanged and signs the app without ``--deep``, so the extension keeps its own signature.

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

The script uses the Xcode in ``DEVELOPER_DIR``, by default ``/Applications/Xcode.app/Contents/Developer``.

For the app ``com.example.myapp``:

.. code-block:: text

   extension/build.sh --hosting apple --app-id com.example.myapp --app-group group.com.example.myapp \
     --profile BADownloader.mobileprovision --version 1.0.0 --build 1 --project ~/Projects/MyApp

writes ``~/Projects/MyApp/Extensions/BADownloader.appex``, the extension ``com.example.myapp.BADownloader``.

Exit codes:

- 0: built; it prints the path it wrote;
- 1: the build or the signing failed. When the build or the signing step itself fails, the message names its log,
  and the work folder that holds the log is kept;
- 2: a usage or precondition error, before anything is built: a missing or wrong option; the project folder without
  ``build.settings`` or inside the plugin's repository; a profile that cannot be read, has expired, has no team, is
  not for ``<team id>.<app id>.<suffix>``, lacks the app group or is an ad hoc profile; no Xcode; no signing identity.

In your Apple developer account, the extension needs:

- its own App ID, ``<app id>.<suffix>`` (``com.example.myapp.BADownloader`` by default), with the App Groups
  capability and the app's app group;
- its own Development or App Store provisioning profile for that App ID. ``extension/build.sh`` exits with code 2 on
  an ad hoc profile, an expired one, one without the app group or one for another App ID.

The extension must sit in ``Extensions/``, never ``PlugIns/``, and must carry a ``CFBundleDisplayName``, which
``extension/build.sh`` sets (``--display-name``).

The script also gives the extension the rest of what it needs: ``EXExtensionPointIdentifier`` set to
``com.apple.background-asset-downloader-extension`` (under ``EXAppExtensionAttributes`` in its Info.plist), and, in
its signature, the ``com.apple.security.application-groups`` entitlement with the app group, its
``application-identifier`` and ``com.apple.developer.team-identifier``. None of the setup on this page requires a
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
     - ``getCapabilities().hosting`` is nil (see :doc:`api/getCapabilities`).
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

Self-hosting has two failures of its own: a missing ``BAInitialDownloadRestrictions`` and a missing Local Network
permission (see :doc:`self-hosting`).
