getResolvedLanguage()
=====================

| **Kind:** synchronous
| **iOS:** 27.0
| **Apple counterpart:** the ``resolvedLanguage`` property
| **See also:** :doc:`setResolvedLanguage`

Returns the manager's resolved language.

Syntax
------

.. code-block:: lua

   local language, err = backgroundAssets.getResolvedLanguage()

Returns
-------

The language identifier, or nil when there is none; or ``nil, err`` with an :doc:`error table <errors>`.

Example
-------

.. code-block:: lua

   local language, err = backgroundAssets.getResolvedLanguage()
   if language then
       print("resolved language:", language)
   end
