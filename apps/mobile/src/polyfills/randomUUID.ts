// crypto.randomUUID polyfill for React Native / Hermes.
//
// `react-native-get-random-values` polyfills crypto.getRandomValues but NOT
// crypto.randomUUID, which Hermes does not implement. @relay/core
// (createMessage, encodeTransfer) and the app's device-id logic all rely on
// crypto.randomUUID, so we add an RFC 4122 v4 implementation built on the
// already-polyfilled getRandomValues.
//
// Import this AFTER 'react-native-get-random-values' and before any app code.

const hex: string[] = [];
for (let i = 0; i < 256; i++) hex.push((i + 0x100).toString(16).slice(1));

function randomUUID(): `${string}-${string}-${string}-${string}-${string}` {
  const bytes = new Uint8Array(16);
  crypto.getRandomValues(bytes);

  // Per RFC 4122 v4: set version and variant bits.
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;

  return (
    hex[bytes[0]] +
    hex[bytes[1]] +
    hex[bytes[2]] +
    hex[bytes[3]] +
    '-' +
    hex[bytes[4]] +
    hex[bytes[5]] +
    '-' +
    hex[bytes[6]] +
    hex[bytes[7]] +
    '-' +
    hex[bytes[8]] +
    hex[bytes[9]] +
    '-' +
    hex[bytes[10]] +
    hex[bytes[11]] +
    hex[bytes[12]] +
    hex[bytes[13]] +
    hex[bytes[14]] +
    hex[bytes[15]]
  ) as `${string}-${string}-${string}-${string}-${string}`;
}

if (typeof globalThis.crypto === 'undefined') {
  // getRandomValues polyfill should have created this; guard just in case.
  (globalThis as { crypto?: Crypto }).crypto = {} as Crypto;
}

if (typeof globalThis.crypto.randomUUID !== 'function') {
  Object.defineProperty(globalThis.crypto, 'randomUUID', {
    value: randomUUID,
    writable: true,
    configurable: true,
  });
}
