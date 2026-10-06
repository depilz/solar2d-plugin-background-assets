Manifest
========

:doc:`getManifest` gives the manifest as a table ``{ assetPacks, primaryLanguage, availableLanguages,
resolvedLanguage, localizedAssetPacks }``, from ``BAAssetPackManifest``:

- ``assetPacks``: an array of :doc:`packs <asset-pack>`;
- ``primaryLanguage``, ``resolvedLanguage``: language identifiers, or nil;
- ``availableLanguages``: an array of language identifiers, in Apple's order;
- ``localizedAssetPacks``: an array of packs.

Fields the OS does not give are nil, or empty arrays.

Methods
-------

They map Apple's ``assetPackWithIdentifier:`` and ``localizedAssetPacksForLanguage:`` (27.0).

``manifest:assetPack(id)``
    Returns the pack of ``assetPacks`` with this id, or nil.

``manifest:localizedAssetPacksForLanguage(language)``
    Returns an array of the ``localizedAssetPacks`` in this language.
