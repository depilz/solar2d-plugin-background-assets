Asset packs
===========

This page builds asset packs with Apple's ``ba-package`` tool, uploads them to App Store Connect for Apple hosting and
tests them locally by serving them to a development build with ``ba-serve``. For packs on your own server, see
:doc:`self-hosting`.

Creating packs
--------------

A ``ba-package`` JSON manifest describes each pack:

- ``assetPackID``: the pack id (see `Pack ids`_);
- ``downloadPolicy``: one of ``essential``, ``prefetch`` or ``onDemand``. ``prefetch`` needs its
  ``installationEventTypes``, or ``ba-package`` fails;
- ``fileSelectors``: the pack's files;
- ``platforms``: ``[ "iOS" ]``.

The files of all packs share one namespace: the paths the app's path calls take (see :doc:`files`). So prefix each
pack's files with its id, as in ``mypack/image.png``, and keep them in a folder named after the pack:

.. code-block:: text

   packs/
       mypack.json
       mypack/
           image.png
           sound.wav

``packs/mypack.json``, a prefetch pack:

.. code-block:: json

   {
       "assetPackID": "mypack",
       "downloadPolicy": {
           "prefetch": {
               "installationEventTypes": [ "firstInstallation", "subsequentUpdate" ]
           }
       },
       "fileSelectors": [
           { "file": "mypack/image.png" },
           { "file": "mypack/sound.wav" }
       ],
       "platforms": [ "iOS" ]
   }

An on-demand pack's policy is ``"downloadPolicy": { "onDemand": {} }``. ``xcrun ba-package template`` prints Apple's
full template, with every policy and every kind of file selector.

``ba-package`` resolves the selectors' paths against the working directory, so build each pack into an ``.aar`` file
from the sources folder:

.. code-block:: text

   cd packs
   xcrun ba-package package mypack.json --output-path ../mypack.aar

The same sources also run in the Solar2D Simulator (see :doc:`simulator`).

Pack ids
--------

.. warning::

   App Store Connect rejects a pack id that contains an underscore, such as ``my_pack``, with
   ``-19241 PARAMETER_ERROR``, although ``ba-package``, ``ba-serve`` and a self-hosted server accept it.

Ids made of letters and digits upload. Which other characters App Store Connect accepts has not been tested.

Uploading
---------

Upload each pack to your app in App Store Connect with ``altool`` and an App Store Connect API key:

.. code-block:: text

   xcrun altool --upload-asset-pack mypack.aar --apple-id <numeric App Store Connect app id> --wait \
     --apiKey <key id> --apiIssuer <issuer id>

Then list the app's packs until the pack's state is ``READY_FOR_TESTING``:

.. code-block:: text

   xcrun altool --list-asset-packs --apple-id <numeric App Store Connect app id> --apiKey <key id> \
     --apiIssuer <issuer id>

Transporter and the App Store Connect API can also upload packs. Apple-hosted packs uploaded this way download in
TestFlight builds.

Testing locally with ba-serve
-----------------------------

``xcrun ba-serve`` serves ``.aar`` packs from your Mac to a development build, without App Store Connect. Apple's
`Testing asset packs locally <https://developer.apple.com/documentation/backgroundassets/testing-asset-packs-locally>`__
is the authority for the TLS steps below.

You need a development build of the app (signed with a Development profile) on a device with Developer Mode on
(Settings › Privacy & Security › Developer Mode).

**A TLS identity for the Mac.** The device reaches ``ba-serve`` over HTTPS at the Mac's IP address, so make a root CA
and a server identity for that address (a ``subjectAltName`` of ``IP:<address>``, ``serverAuth``, valid at most 825
days), then import the identity into the login keychain. For a Mac at ``192.168.1.10``, in a private folder:

.. code-block:: text

   IP=192.168.1.10
   openssl req -x509 -new -newkey rsa:2048 -nodes -sha256 -days 365 -keyout rootCA.key -out rootCA.pem \
     -subj "/CN=Asset Packs Test Root CA" \
     -addext "basicConstraints=critical,CA:TRUE" -addext "keyUsage=critical,keyCertSign,cRLSign"
   openssl req -new -newkey rsa:2048 -nodes -keyout server.key -out server.csr -subj "/CN=$IP"
   cat > server.ext <<EOF
   subjectAltName=IP:$IP
   extendedKeyUsage=serverAuth
   keyUsage=critical,digitalSignature,keyEncipherment
   basicConstraints=CA:FALSE
   EOF
   openssl x509 -req -in server.csr -CA rootCA.pem -CAkey rootCA.key -CAcreateserial -days 365 -sha256 \
     -extfile server.ext -out server.pem
   openssl pkcs12 -export -legacy -inkey server.key -in server.pem -certfile rootCA.pem -name "Asset Packs $IP" \
     -out server.p12
   security import server.p12 -k ~/Library/Keychains/login.keychain-db -f pkcs12

These commands were not run as given, nor checked against Apple's page; where they differ, Apple's page wins. The
tested setup made its root CA in Keychain Access. ``-legacy`` makes OpenSSL 3 write the older ``.p12`` format, for
macOS's importer.

**The device trusts the CA.** Install ``rootCA.pem`` on the device as a profile, with Apple Configurator or by
AirDropping the ``.pem``, then turn it on under Settings › General › About › Certificate Trust Settings.

**Serve the packs:**

.. code-block:: text

   xcrun ba-serve serve mypack.aar otherpack.aar --host 192.168.1.10 --port 8443 --choose-identity-automatically

**Point the device at it.** On the device, under Settings › Developer › Background Assets, set the development-override
URL to the server's address with an empty path: ``https://192.168.1.10:8443``. Then run the app.

.. note::

   - After ``ba-serve`` restarts, enter the development-override URL again. Until then the device keeps the old
     manifest, and every ``ensureLocalAvailability`` fails at once.
   - A stale ``ba-serve`` still holding the port shows as "certificate invalid" until it is killed.
