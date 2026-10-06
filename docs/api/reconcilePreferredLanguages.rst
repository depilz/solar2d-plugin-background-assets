reconcilePreferredLanguages()
=============================

| **Kind:** asynchronous
| **iOS:** 27.0
| **Apple counterpart:** ``reconcilePreferredLanguagesWithCompletionHandler:``
| **See also:** :doc:`getLocallyAvailableLanguages`, :doc:`getResolvedLanguage`

Reconciles the packs' languages with the user's preferred languages.

Syntax
------

.. code-block:: lua

   backgroundAssets.reconcilePreferredLanguages()
   backgroundAssets.reconcilePreferredLanguages(listener)

Parameters
----------

- ``listener`` (listener, optional): gets the call's event (see :doc:`events`).

Event
-----

No payload.

Example
-------

.. code-block:: lua

   backgroundAssets.reconcilePreferredLanguages()
