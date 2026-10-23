import { test, expect, type Page } from '@playwright/test';

// Supply real QR pixels as a camera stream. This verifies the scanner and
// receipt workflow in Chrome; physical iOS/Android cameras still need a check.
async function cameraImage(page: Page, dataUrl: string) {
  await page.evaluate(async url => {
    const image = new Image();
    image.src = url;
    await image.decode();
    navigator.mediaDevices.getUserMedia = async () => {
      const canvas = document.createElement('canvas');
      canvas.width = canvas.height = 640;
      const ctx = canvas.getContext('2d')!;
      ctx.fillStyle = 'white';
      ctx.fillRect(0, 0, 640, 640);
      ctx.drawImage(image, 0, 0, 640, 640);
      const stream = canvas.captureStream(10);
      const timer = setInterval(() => ctx.drawImage(image, 0, 0, 640, 640), 100);
      stream.getVideoTracks()[0].addEventListener('ended', () => clearInterval(timer));
      return stream;
    };
  }, dataUrl);
}

test('QR transfer and receiver receipt persist between two offline phones', async ({ browser, baseURL }) => {
  const a = await browser.newContext({ baseURL });
  const b = await browser.newContext({ baseURL });
  const sender = await a.newPage(), receiver = await b.newPage();
  try {
    for (const page of [sender, receiver]) {
      await page.goto('/');
      await page.evaluate(async () => { await navigator.serviceWorker.ready; });
      await page.reload();
    }
    await a.setOffline(true);
    await b.setOffline(true);
    await sender.goto('/#/resident/new');
    await sender.getByRole('button', { name: 'Food', exact: true }).click();
    await sender.getByLabel('Tell us more').fill('Fictional offline QR request at Demo Hall.');
    await sender.getByRole('button', { name: 'Send request', exact: true }).click();
    await expect(sender).toHaveURL(/resident\/requests\//);
    await sender.getByRole('button', { name: 'Send (1)', exact: true }).click();
    const transfer = sender.getByLabel('Transfer code', { exact: true });
    await expect(transfer).toBeVisible();
    await expect.poll(() => transfer.evaluate((c: HTMLCanvasElement) => c.width)).toBe(360);
    const transferImage = await transfer.evaluate((c: HTMLCanvasElement) => c.toDataURL());

    await receiver.goto('/#/resident/requests');
    await cameraImage(receiver, transferImage);
    await receiver.getByRole('button', { name: 'Receive', exact: true }).click();
    await expect(receiver.getByText('Received 1 new message. Checked and saved.', { exact: true })).toBeVisible();
    const receipt = receiver.getByLabel('Receipt code', { exact: true });
    await expect.poll(() => receipt.evaluate((c: HTMLCanvasElement) => c.width)).toBe(360);
    const receiptImage = await receipt.evaluate((c: HTMLCanvasElement) => c.toDataURL());
    await cameraImage(sender, receiptImage);
    await sender.getByRole('button', { name: 'The other phone shows a receipt: scan it', exact: true }).click();
    await expect(sender.getByText(/1 message confirmed by phone-/)).toBeVisible();
    await expect(sender.getByLabel('Delivery status: Passed to nearby phone')).toBeVisible();
    await receiver.reload();
    const relayed = await receiver.evaluate(() => JSON.parse(localStorage.getItem('relay.device.v1')!).store.messages);
    expect(relayed).toHaveLength(1);
    expect(relayed[0].hops).toBe(1);
    expect(relayed[0].body).toContain('Fictional offline QR request at Demo Hall.');
  } finally { await a.close(); await b.close(); }
});
