# Encrypted shelter delivery — build16

The main request form saves a CloudSubmission and its optional nearby envelope in
one SQLite transaction. It uses the same immutable request UUID for both routes.
A cached HTTPS directory binds a shelter to a receiving device, account subject,
P256 signing key and Curve25519 agreement key.

A signed body contains the exact serialized submission bytes, origin/receiver
account subjects, receiving device UUID, sender agreement key and pinned receiving
signing key. P256 signs those bytes. An ephemeral X25519 shared secret is expanded
with HKDF-SHA256 and encrypts the signed body using ChaChaPoly. Authenticated data
binds the immutable wire route, lifetime and hop limit. Only hop_count changes in
transit. The encrypted text remains inside the existing v1 payload so older
carriers can preserve it as opaque data within the existing size bound.

The receiver decrypts and validates before persisting application content. Request
and signed destination receipt are committed before the transport ACK. Duplicate
requests do not generate multiple logical actions or receipts. The origin verifies
the receipt using the key pinned in its original outgoing envelope. An ordinary
plaintext receipt cannot complete one of these new encrypted requests.

Device registration is scoped by account subject and stable device UUID. This
supports account switching without changing the physical routing identity or
reassigning earlier signed request ownership. Public keys are immutable within an
enrollment. Receiver replacement requires a current revision and an authorized
coordinator's own enrolled device.

The authenticated shelter gateway verifies the exact-byte sender signature,
enrolled keys, current sender/shelter membership and receiving account/device. It
submits under the origin requester. Direct HTTP upload and gateway replay use the
same existing idempotency transaction and must not allocate supplies twice.

Offline local receipt proves destination-device persistence. Sender identity is
pending backend verification until the receiving coordinator reconnects. Inventory
approval remains online and human controlled. Cloud staff replies/history currently
return through cloud; the nearby return path carries the delivery receipt only.

Limitations: keys are app-sandbox files with0600 permissions and iOS file protection,
not hardware-bound credentials. Decrypted content remains in local SQLite. Bonjour
identity and storage ACKs are unauthenticated. Legacy chat/shelter codes are still
plaintext. There is no key-revocation/recovery system, traffic-analysis protection,
anti-spam routing, background wake guarantee or independent cryptographic audit.
Only synthetic data is appropriate for this prototype.

Evidence: `docs/evidence/nearby-20261024/`. Automated coverage includes tampering,
wrong keys, forged receipts, duplicate paths, original ownership, membership checks,
receiver revision conflicts, restart persistence and late cloud responses that must
not regress verified delivery. Native CryptoKit→Python fixture compatibility and
native simulator/Mac encounter tests are recorded separately from physical tests.
