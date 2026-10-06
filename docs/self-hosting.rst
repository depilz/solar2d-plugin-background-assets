Self-hosting
============

This page covers serving asset packs from your own HTTPS server instead of App Store Connect. It builds on
:doc:`setup`, whose app keys and entitlements still apply, except ``BAUsesAppleHosting``.

The app
-------

Set these Info.plist keys in ``build.settings``:

- ``BAUsesAppleHosting``: ``false``;
- ``BAManifestURL``: the HTTPS URL of the download manifest on your server;
- ``BAInitialDownloadRestrictions``: a table of ``BADownloadAllowance``, ``BAEssentialDownloadAllowance`` and
  ``BADownloadDomainAllowList``, an array holding your server's host.

.. warning::

   Without ``BAInitialDownloadRestrictions``, iOS kills the app at its first Background Assets call with the message
   "BUG IN CLIENT OF BackgroundAssets: The app must contain a dictionary with a key named
   BAInitialDownloadRestrictions".

For a server at ``packs.example.com``, the settings look like this (the two allowances are an example, not a
requirement):

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
               BAUsesAppleHosting = false,
               BAManifestURL = "https://packs.example.com/download-manifest.json",
               BAInitialDownloadRestrictions =
               {
                   BADownloadAllowance = 1048576,
                   BAEssentialDownloadAllowance = 1048576,
                   BADownloadDomainAllowList = { "packs.example.com" },
               },
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

Build the self-hosting flavour, ``ManagedDownloaderExtension``, with ``--hosting self`` (see :doc:`setup` for the
other options):

.. code-block:: text

   extension/build.sh --hosting self --app-id com.example.myapp --app-group group.com.example.myapp \
     --profile BADownloader.mobileprovision --version 1.0.0 --build 1 --project ~/Projects/MyApp

The extension reads no configuration of its own.

The server
----------

Build the packs as :doc:`packs` describes, then generate the download manifest from them:

.. code-block:: text

   xcrun ba-package download-manifest create mypack.aar otherpack.aar --ios \
     --download-base-url <https base URL> --output-path download-manifest.json

In the manifest, each pack's download URL is the base URL followed by the pack's id. Serve each ``<id>.aar`` file at
the base URL as ``<id>``, with no extension, and serve ``download-manifest.json`` at the app's ``BAManifestURL``. The
server must use HTTPS with a certificate the device trusts.

A server on a local network
---------------------------

Pack downloads run outside the app, in the system's downloader extension, and do not bring up the Local Network
prompt. For a server on the device's local network, the app has to bring up the prompt itself:

- set ``NSLocalNetworkUsageDescription`` in the Info.plist to the sentence iOS shows in the prompt;
- before the first download, make a request from the app to the server so that iOS shows the prompt; a ``GET`` of the
  manifest URL is enough;
- the user allows it.

.. code-block:: lua

   network.request("https://192.168.1.10:8443/download-manifest.json", "GET", function(event) end)

.. warning::

   Without the permission, the manifest requests still succeed, but every pack download fails with NSURLError -1004.

A server on a public HTTPS host has not been tested.
