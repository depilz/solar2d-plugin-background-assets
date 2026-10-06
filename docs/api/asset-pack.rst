Asset pack
==========

A pack is a table ``{ id, downloadSize, version, language, userInfo }``, from ``BAAssetPack``:

- ``id``: the pack id, a string;
- ``downloadSize``, ``version``: numbers;
- ``language``: the pack's language identifier; nil below iOS 27 and for a pack with no language;
- ``userInfo``: the pack's user info bytes as a Lua string, or nil.

A call that takes an ``assetPack`` expects such a table but reads only its ``id``, so ``{ id = "mypack" }`` will do.

Arrays of packs are sorted by id, then by language.
