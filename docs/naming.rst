Names and departures from Apple's API
=====================================

The plugin's calls keep Apple's names wherever possible. This page gives the naming rule and lists every way the API
departs from Apple's. Each call's page in :doc:`api` names its Apple selector or property, under "Apple
counterpart".

Names
-----

Each call is named after the first keyword of Apple's Objective-C selector, in lowerCamelCase:

- selector words that only name an argument (``WithIdentifier``, ``WithCompletionHandler``) are dropped;
- the completion handler becomes a trailing ``listener``;
- later selector keywords (``requireLatestVersion``, ``searchingInAssetPackWithIdentifier``,
  ``asLocalizedForLanguage``) become fields of an optional ``options`` table.

A pack's ``identifier`` becomes ``id``, Apple's Swift name for it. A property is accessed through a ``get``/``set`` pair:
``resolvedLanguage`` through ``getResolvedLanguage`` and ``setResolvedLanguage``, ``delegate`` through ``setDelegate``.

`Departures from Apple's API`_ lists where the API departs from Apple's names and shapes.

Departures from Apple's API
---------------------------

Apart from the naming rule in `Names`_, the API departs from Apple's in these ways:

1. ``pathForFile`` is new. It returns a filename and base directory that ``display.newImage`` and
   ``audio.loadSound`` can load, since they cannot load a pack file's absolute path.
2. ``getCapabilities`` is new.
3. A status is a table of booleans, not a bit set.
4. Errors are tables, and the plugin has its own error domain, ``"plugin.backgroundAssets"``.
5. Listeners and events replace completion handlers. In place of the delegate's methods, ``setDelegate``'s listener
   gets ``"download"`` events with a ``phase``.
6. ``urlForPath`` returns a plain path, not a URL, never returns a removed pack's file, and takes an optional pack id.
7. ``contentsAtPath`` returns a Lua string, and takes none of Apple's reading options.
8. Sets become arrays sorted by pack id.
9. The unmanaged per-pack downloads and the manifest initialisers are left out.
10. ``fileForPath`` returns an open Lua file, as ``io.open`` does, instead of ``fileDescriptorForPath``'s file
    descriptor. The app closes the file. When the descriptor cannot be wrapped, the plugin closes the descriptor and
    returns ``nil, err``.
