Path calls
==========

:doc:`pathForFile`, :doc:`urlForPath`, :doc:`contentsAtPath` and :doc:`fileForPath` find a file of a local pack. They
share their arguments and the checks below. :doc:`/files` shows them in use.

Paths
-----

A path call takes a path relative to the root of the packs' shared file namespace; where a pack's files sit in that
namespace is set by the app's own pack layout (see :doc:`/packs`).

Options
-------

- ``assetPackId``: the pack the file belongs to. ``contentsAtPath`` and ``fileForPath`` pass it to Apple as
  ``searchingInAssetPackWithIdentifier``. For every path call it also turns on the pack check below.
- ``language``: a language identifier, which selects Apple's iOS 27 localized variant. Below iOS 27 it gives
  ``unsupported``.

``assetPackId`` together with ``language`` gives ``invalidArgument``: Apple's localized variants take no pack id.

Checks
------

A removed pack never reports a file. Before it returns a path, a file or contents, each path call checks:

- **the pack**, when ``options.assetPackId`` is given: a pack that is not available locally gives
  ``assetPackNotAvailable``. From iOS 26.4 the plugin asks ``assetPackIsAvailableLocally``; below that, it keeps its
  own record of the packs it removed, stored across launches: :doc:`removeAssetPack` adds the id, and a successful
  :doc:`ensureLocalAvailability` or a ``finished`` download clears it.
- **the file**: a file that is not on disk gives ``fileNotFound`` in the plugin's domain.

Timing on iOS
-------------

A path lookup started while a :doc:`removeAssetPack` is in flight waits for it to complete, up to 250 ms.

Apple's ``URLForPath`` sometimes gives ``NSCocoaErrorDomain`` 513 for a few milliseconds after a pack's state changes.
A lookup that fails with it is retried up to 4 times, within 50 ms; after that, the 513 is returned as the error.
