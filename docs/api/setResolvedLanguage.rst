setResolvedLanguage()
=====================

| **Kind:** synchronous
| **iOS:** 27.0
| **Apple counterpart:** the ``resolvedLanguage`` property
| **See also:** :doc:`getResolvedLanguage`

Sets the manager's resolved language; ``nil`` clears it.

Syntax
------

.. code-block:: lua

   local ok, err = backgroundAssets.setResolvedLanguage(language)

Parameters
----------

- ``language`` (string or nil): a language identifier, or ``nil`` to clear it.

Returns
-------

``true``; or ``nil, err`` with an :doc:`error table <errors>`.

Example
-------

.. code-block:: lua

   backgroundAssets.setResolvedLanguage("es")
