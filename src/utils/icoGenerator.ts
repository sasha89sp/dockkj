/**
 * Generates a valid 32x32 32-bit BGRA Windows .ICO binary (BMP/DIB payload)
 * compatible with Windows Resource Compiler (rc.exe), Windows Explorer, and tray_manager.
 * Renders a crisp AeroDock rounded-squircle emblem with a glossy dock bar & three icon dots.
 */
export function generateAeroDockIcoBytes(): Uint8Array {
  const size = 32;
  const pixelBytes = size * size * 4;
  const maskRowBytes = Math.ceil(size / 32) * 4; // 4 bytes per row for 32px width
  const maskBytes = maskRowBytes * size;
  const dibHeaderSize = 40;
  const imageSize = dibHeaderSize + pixelBytes + maskBytes;

  // ICO Header (6 bytes) + 1 ICONDIRENTRY (16 bytes) + DIB image
  const totalBytes = 6 + 16 + imageSize;
  const buf = new Uint8Array(totalBytes);
  const view = new DataView(buf.buffer);

  // ICONDIR
  view.setUint16(0, 0, true); // reserved
  view.setUint16(2, 1, true); // type: 1 = ICO
  view.setUint16(4, 1, true); // count: 1 image

  // ICONDIRENTRY
  buf[6] = size; // width
  buf[7] = size; // height
  buf[8] = 0; // color count
  buf[9] = 0; // reserved
  view.setUint16(10, 1, true); // color planes
  view.setUint16(12, 32, true); // bits per pixel
  view.setUint32(14, imageSize, true); // bytes in resource
  view.setUint32(18, 22, true); // offset to DIB

  // BITMAPINFOHEADER (40 bytes at offset 22)
  const dibOffset = 22;
  view.setUint32(dibOffset + 0, dibHeaderSize, true);
  view.setInt32(dibOffset + 4, size, true); // width
  view.setInt32(dibOffset + 8, size * 2, true); // height * 2 (XOR + AND masks)
  view.setUint16(dibOffset + 12, 1, true); // planes
  view.setUint16(dibOffset + 14, 32, true); // bpp
  view.setUint32(dibOffset + 16, 0, true); // BI_RGB (uncompressed)
  view.setUint32(dibOffset + 20, pixelBytes + maskBytes, true);

  const pixelStart = dibOffset + dibHeaderSize;

  // Helper: signed distance to rounded box centered at (cx, cy)
  const sdRoundedBox = (
    x: number,
    y: number,
    cx: number,
    cy: number,
    hw: number,
    hh: number,
    r: number
  ) => {
    const qx = Math.abs(x - cx) - hw + r;
    const qy = Math.abs(y - cy) - hh + r;
    return (
      Math.hypot(Math.max(qx, 0), Math.max(qy, 0)) +
      Math.min(Math.max(qx, qy), 0) -
      r
    );
  };

  // BMP rows are stored bottom-up (y = size-1 down to 0)
  for (let row = 0; row < size; row++) {
    const y = size - 1 - row;
    for (let x = 0; x < size; x++) {
      const px = x + 0.5;
      const py = y + 0.5;

      const dOuter = sdRoundedBox(px, py, 16, 16, 14.2, 14.2, 6.8);
      let r = 0;
      let g = 0;
      let b = 0;
      let a = 0;

      if (dOuter <= 0.6) {
        // Anti-aliased outer alpha
        const outerCov = Math.max(0, Math.min(1, 0.5 - dOuter));
        // Diagonal deep cobalt -> vibrant sky gradient
        const t = (px * 0.4 + py * 0.6) / size;
        r = Math.round(14 + (2 - 14) * t);
        g = Math.round(165 + (86 - 165) * t);
        b = Math.round(233 + (195 - 233) * t);

        // Subtle top glass sheen
        if (py < 15) {
          const sheen = Math.max(0, 1 - py / 15) * 0.24;
          r = Math.min(255, Math.round(r + (255 - r) * sheen));
          g = Math.min(255, Math.round(g + (255 - g) * sheen));
          b = Math.min(255, Math.round(b + (255 - b) * sheen));
        }

        // Crisp subtle inner border
        if (dOuter > -1.3) {
          r = Math.min(255, r + 55);
          g = Math.min(255, g + 55);
          b = Math.min(255, b + 55);
        }

        // Rocket / Aero Chevron emblem in upper half
        const dx = Math.abs(px - 16);
        const chevTop = 7.2 + dx * 0.92;
        const chevBot = chevTop + 3.2;
        if (dx <= 6.8 && py >= chevTop && py <= chevBot) {
          r = 255;
          g = 255;
          b = 255;
        }

        // Dock shelf pill at bottom
        const dShelf = sdRoundedBox(px, py, 16, 22.8, 9.6, 2.8, 2.2);
        if (dShelf <= 0) {
          r = 248;
          g = 250;
          b = 252;
        }

        // Three dock dots inside shelf
        for (const dotX of [10.8, 16.0, 21.2]) {
          const distDot = Math.hypot(px - dotX, py - 22.8);
          if (distDot <= 1.35) {
            r = 15;
            g = 23;
            b = 42;
          }
        }

        a = Math.round(outerCov * 255);
      }

      const idx = pixelStart + (row * size + x) * 4;
      buf[idx + 0] = b;
      buf[idx + 1] = g;
      buf[idx + 2] = r;
      buf[idx + 3] = a;
    }
  }

  // AND mask stays all zeros (32-bit alpha channel governs transparency)
  return buf;
}
