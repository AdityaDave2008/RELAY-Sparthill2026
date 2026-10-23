// Bound decoded data before passing bytes to Bedrock. Browser uploads are resized
// JPEGs; no image is persisted by this endpoint.
export function cardImage(value: unknown): Uint8Array {
  if (typeof value !== 'string' || value.length > 1_400_000 || value.length % 4 !== 0 ||
      !/^[A-Za-z0-9+/]+={0,2}$/.test(value)) throw new Error('Invalid base64 JPEG');
  const bytes = Buffer.from(value, 'base64');
  if (bytes.length > 1_048_576 || bytes.length < 12 || bytes.toString('base64') !== value ||
      bytes[0] !== 0xff || bytes[1] !== 0xd8 || bytes.at(-2) !== 0xff || bytes.at(-1) !== 0xd9) throw new Error('Invalid JPEG');
  let offset = 2;
  while (offset + 4 < bytes.length) {
    if (bytes[offset++] !== 0xff) throw new Error('Invalid JPEG marker');
    while (bytes[offset] === 0xff) offset++;
    const marker = bytes[offset++];
    if (marker === 0xda || marker === 0xd9) break;
    const size = bytes.readUInt16BE(offset);
    if (size < 2 || offset + size > bytes.length) throw new Error('Invalid JPEG segment');
    if ([0xc0, 0xc1, 0xc2].includes(marker!)) {
      if (size < 8) throw new Error('Invalid JPEG dimensions');
      const height = bytes.readUInt16BE(offset + 3), width = bytes.readUInt16BE(offset + 5);
      if (width < 1 || height < 1 || width > 1400 || height > 1400) throw new Error('Resize JPEG to at most 1400 pixels');
      return bytes;
    }
    offset += size;
  }
  throw new Error('JPEG dimensions missing');
}
