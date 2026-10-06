getLocallyAvailableLanguages()
==============================

| **Kind:** asynchronous
| **iOS:** 27.0
| **Apple counterpart:** ``getLocallyAvailableLanguagesWithCompletionHandler:``
| **See also:** :doc:`reconcilePreferredLanguages`

Gets the languages available locally.

Syntax
------

.. code-block:: lua

   backgroundAssets.getLocallyAvailableLanguages(listener)

Parameters
----------

- ``listener`` (listener): gets the call's event (see :doc:`events`).

Event
-----

``event.languages``: an array of language identifiers, in Apple's order.

Example
-------

.. code-block:: lua

   backgroundAssets.getLocallyAvailableLanguages(function(event)
       if not event.isError then
           print(table.concat(event.languages, ", "))
       end
   end)
