Names and departures from Apple's API
=====================================

The plugin's calls keep Apple's names where they can. This page gives the rule that names them and lists every way the
API departs from Apple's. The "Apple counterpart" column of the table in :doc:`api` ("Calls and iOS versions") is the
full map from each Lua call to its Apple selector or property.

Names
-----

Each call takes the first keyword of Apple's Objective-C selector, in lowerCamelCase:

- selector words that only name an argument (``WithIdentifier``, ``WithCompletionHandler``) are dropped;
- the completion handler becomes a trailing ``listener``;
- later selector keywords (``requireLatestVersion``, ``searchingInAssetPackWithIdentifier``,
  ``asLocalizedForLanguage``) become fields of an optional ``options`` table.

A pack's ``identifier`` is its ``id``, Apple's Swift name for it. A property is reached through a ``get``/``set`` pair:
``resolvedLanguage`` through ``getResolvedLanguage`` and ``setResolvedLanguage``, ``delegate`` through ``setDelegate``.

Where the API departs from Apple's names and shapes is listed in `Departures from Apple's API`_.

Departures from Apple's API
---------------------------

Beside the naming rule of `Names`_, the API departs from Apple's in these ways:

1. ``pathForFile`` is new. It gives a filename and base directory that ``display.newImage`` and ``audio.loadSound``
   load, which they cannot do from a pack file's absolute path.
2. ``getCapabilities`` is new.
3. A status is a table of booleans, not a bit set.
4. Errors are tables, and the plugin has its own error domain, ``"plugin.backgroundAssets"``.
5. Listeners and events take the place of completion handlers, and ``setDelegate``'s listener gets ``"download"``
   events with a ``phase`` in place of the delegate's methods.
6. ``urlForPath`` returns a plain path, not a URL; never returns a removed pack's file; and takes an optional pack id.
7. ``contentsAtPath`` returns a Lua string, and takes none of Apple's reading options.
8. Sets become arrays sorted by pack id.
9. The unmanaged per-pack downloads and the manifest initialisers are left out.
10. ``fileForPath`` returns an open Lua file, as ``io.open`` does, in place of ``fileDescriptorForPath``'s file
    descriptor. The app closes it. When the descriptor cannot be wrapped, the plugin closes it and returns ``nil, err``.
