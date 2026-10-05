Background Assets plugin for Solar2D
====================================

``plugin.backgroundAssets`` (publisher ``com.studycat``) brings Apple's managed Background Assets API (iOS 26 and
later) to Solar2D apps. An app uses it to download asset packs, groups of images, sounds and other files, after it is
installed, and to load their files.

The packs are hosted by Apple, uploaded to App Store Connect, or by you, on your own HTTPS server. The app picks one of
the two hostings in its setup (see :doc:`setup` and :doc:`self-hosting`).

The plugin loads from iOS 13. Below iOS 26 ``getCapabilities().isSupported`` is ``false`` and every other call
except ``setDelegate``, which is accepted and never calls its listener, reports the ``unsupported`` error (see
:doc:`api`). In the Solar2D Simulator it runs over a folder emulator of
Background Assets, which the app configures from Lua (see :doc:`simulator`).

.. toctree::
   :maxdepth: 1
   :caption: Guide

   quickstart
   setup
   packs
   self-hosting
   files
   simulator

.. toctree::
   :maxdepth: 1
   :caption: Reference

   api
   emulator
   naming

.. toctree::
   :maxdepth: 1
   :caption: For backend authors

   backend
