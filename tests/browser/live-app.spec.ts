import { test, expect } from '@playwright/test';

// Intentionally uses real AWS calls. Start the built app with a configured
// services/api/.env before running. No API responses are intercepted or mocked.
test('offline resident, live Bedrock coordinator, and translated warning', async ({ browser, baseURL }, testInfo) => {
  const residentContext = await browser.newContext({ baseURL, geolocation: { latitude: 37.33, longitude: -121.88, accuracy: 15 }, permissions: ['geolocation'] });
  const coordinatorContext = await browser.newContext({ baseURL, viewport: { width: 1440, height: 1000 } });
  const resident = await residentContext.newPage();
  const coordinator = await coordinatorContext.newPage();
  const stamp = `Browser demo ${Date.now()}`;
  const evidence: Record<string, unknown> = {};
  try {
    await resident.goto('/#/resident/new');
    await resident.evaluate(async () => { await navigator.serviceWorker.ready; });
    await resident.reload();
    await expect(resident.getByRole('heading', { name: 'Ask for help', exact: true })).toBeVisible();
    await residentContext.setOffline(true);
    await resident.getByRole('button', { name: 'Water', exact: true }).click();
    await resident.getByRole('spinbutton', { name: 'Number of people' }).fill('4');
    await resident.getByLabel('Tell us more').fill(`${stamp}. Four people at Demo Elm Hall need drinking water.`);
    await resident.getByRole('button', { name: 'Send request', exact: true }).click();
    await expect(resident).toHaveURL(/resident\/requests\//);
    await resident.reload();
    await expect(resident.getByText(stamp, { exact: false })).toBeVisible();
    const requestId = await resident.evaluate(() => {
      const saved = JSON.parse(localStorage.getItem('relay.device.v1')!);
      return saved.store.messages.find((m: { kind: string }) => m.kind === 'help_request').id as string;
    });
    evidence.requestId = requestId;
    await residentContext.setOffline(false);
    await expect(resident.getByLabel('Delivery status: Reached coordinators')).toBeVisible();
    console.info('Offline persistence and reconnect upload passed.');

    const briefResponse = coordinator.waitForResponse(r => r.url().endsWith('/v1/briefing') && r.request().method() === 'POST', { timeout: 45_000 });
    await coordinator.goto('/#/coordinator');
    const card = coordinator.locator('article.req').filter({ hasText: stamp });
    await expect(card).toBeVisible();
    await expect(card.locator('.bedrock-head')).toContainText('us.anthropic.claude-sonnet-5-5');
    const brief = await (await briefResponse).json();
    expect(brief.error).toBeUndefined();
    expect(brief.source).toBe('amazon-bedrock');
    expect(brief.awsRequestId).toBeTruthy();
    evidence.briefing = brief.awsRequestId;
    console.info('Live Bedrock extraction and situation brief passed.');
    await card.getByLabel(/What can you offer/).fill('Fictional verified source: Demo Elm Hall water desk open until 18:00 today. Drinking water is available for four people. No delivery is confirmed.');
    await card.getByLabel('Reply language').selectOption('es');
    const draftResponse = coordinator.waitForResponse(r => r.url().includes(`/${requestId}/response-draft`));
    await card.getByRole('button', { name: 'Prepare response with Bedrock', exact: true }).click();
    const draft = await (await draftResponse).json();
    expect(draft.error).toBeUndefined();
    expect(draft.draft.source).toBe('amazon-bedrock');
    expect(draft.draft.language).toBe('Spanish');
    expect(draft.draft.awsRequestId).toBeTruthy();
    evidence.replyDraft = draft.draft.awsRequestId;
    await expect(card.getByLabel('Reply', { exact: true })).toBeVisible();
    const reply = await card.getByLabel('Reply', { exact: true }).inputValue();
    await card.getByRole('button', { name: 'Approve & send', exact: true }).click();
    await resident.goto('/#/resident');
    await expect(resident.getByText(reply, { exact: true })).toBeVisible();
    console.info('Live Bedrock Spanish reply, approval, and resident delivery passed.');

    const composer = coordinator.locator('section.card').filter({ has: coordinator.getByRole('heading', { name: 'Public warning', exact: true }) });
    await composer.getByLabel('Field report (paste raw notes)').fill('Fictional coordinator verified note: Demo North Hills community desk has drinking water until 18:00 today. Residents can collect water there. Delivery is not confirmed.');
    await composer.getByRole('combobox', { name: /Send to/ }).selectOption('north-hills');
    const warningDrafts: unknown[] = [];
    const capture = async (response: import('@playwright/test').Response) => {
      if (response.url().endsWith('/v1/bulletins/draft')) warningDrafts.push(await response.json());
    };
    coordinator.on('response', capture);
    await composer.getByRole('button', { name: 'Draft with Amazon Bedrock', exact: true }).click();
    await expect(composer.getByLabel('Headline', { exact: true })).toBeVisible();
    coordinator.off('response', capture);
    expect(warningDrafts).toHaveLength(2);
    for (const output of warningDrafts as { source: string; awsRequestId: string; pictograms: string[] }[]) {
      expect(output.source).toBe('amazon-bedrock');
      expect(output.awsRequestId).toBeTruthy();
      expect(output.pictograms.length).toBeGreaterThan(0);
    }
    evidence.warningDrafts = warningDrafts;
    await composer.getByLabel('Approver name', { exact: true }).fill('Demo Coordinator');
    const published = coordinator.waitForResponse(r => r.url().endsWith('/v1/warnings') && r.request().method() === 'POST');
    await composer.getByRole('button', { name: /Approve & publish/ }).click();
    const warning = (await (await published).json()).message;
    expect(warning.translations.es.body).toBeTruthy();
    await resident.getByLabel('Language', { exact: true }).selectOption('es');
    await expect(resident.getByText(warning.translations.es.body, { exact: true })).toBeVisible();
    console.info('Live Bedrock multilingual warning and delivery passed.');
    await coordinator.screenshot({ path: testInfo.outputPath('coordinator.png'), fullPage: true });
    await coordinator.setViewportSize({ width: 390, height: 844 });
    expect(await coordinator.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(390);
    await coordinator.setViewportSize({ width: 1440, height: 1000 });
    await testInfo.attach('live-aws-evidence', { body: JSON.stringify(evidence, null, 2), contentType: 'application/json' });
  } catch (error) {
    await testInfo.attach('coordinator-state', { body: await coordinator.locator('body').innerText(), contentType: 'text/plain' });
    await coordinator.screenshot({ path: testInfo.outputPath('failure-coordinator.png'), fullPage: true });
    throw error;
  } finally {
    await residentContext.close();
    await coordinatorContext.close();
  }
});

test('Bedrock paper-card vision and approved reply return to a volunteer', async ({ browser, baseURL }, testInfo) => {
  const coordinatorContext = await browser.newContext({ baseURL });
  const coordinator = await coordinatorContext.newPage();
  const evidence: Record<string, unknown> = {};
  try {
    const fixture = await coordinatorContext.newPage();
    await fixture.setContent('<main style="font:28px Arial;padding:40px;width:800px;background:white;color:black"><h1>RELAY — FICTIONAL HELP CARD</h1><p>Needs: [X] WATER   [X] FOOD</p><p>People: 4</p><p>Location: Demo Elm Hall, blue door</p><p>Notes: Drinking water and meals needed.</p></main>');
    const photo = await fixture.locator('main').screenshot({ type: 'jpeg', quality: 85 });
    await fixture.close();
    await coordinator.goto('/#/volunteer/north-hills');
    const visionResponse = coordinator.waitForResponse(r => r.url().endsWith('/v1/cards/read'), { timeout: 45_000 });
    await coordinator.locator('input[type=file]').setInputFiles({ name: 'fictional-help-card.jpg', mimeType: 'image/jpeg', buffer: photo });
    const vision = await (await visionResponse).json();
    expect(vision.error).toBeUndefined();
    expect(vision.source).toBe('amazon-bedrock');
    expect(vision.awsRequestId).toBeTruthy();
    expect(vision.needs).toEqual(expect.arrayContaining(['water', 'food']));
    expect(vision.peopleCount).toBe(4);
    await expect(coordinator.getByLabel('Where (as written on card)')).toHaveValue(/Demo Elm Hall/i);
    await coordinator.getByLabel('Your name (volunteer)').fill('Browser Demo Volunteer');
    await coordinator.getByRole('button', { name: 'Save card', exact: true }).click();
    await expect(coordinator.getByText('Card saved and sending', { exact: true })).toBeVisible();
    evidence.cardVision = vision.awsRequestId;
    console.info('Live Bedrock paper-card vision and volunteer confirmation passed.');
    const paperId = await coordinator.evaluate(() => {
      const saved = JSON.parse(localStorage.getItem('relay.device.v1')!);
      return saved.store.messages.find((m: { originDeviceId: string }) => m.originDeviceId === 'paper:browser-demo-volunteer').id as string;
    });
    await coordinator.goto('/#/coordinator');
    const paperCard = coordinator.locator(`article.req[data-request-id="${paperId}"]`);
    await expect(paperCard).toBeVisible();
    await paperCard.getByLabel(/What can you offer/).fill('Verified fictional note: Demo Elm Hall has drinking water and meals for four people until 18:00 today. No delivery confirmed.');
    const paperDraftResponse = coordinator.waitForResponse(r => r.url().includes(`/${paperId}/response-draft`));
    await paperCard.getByRole('button', { name: 'Prepare response with Bedrock', exact: true }).click();
    const paperDraft = await (await paperDraftResponse).json();
    expect(paperDraft.draft.source).toBe('amazon-bedrock');
    const paperReply = await paperCard.getByLabel('Reply', { exact: true }).inputValue();
    await paperCard.getByRole('button', { name: 'Approve & send', exact: true }).click();
    await coordinator.goto('/#/volunteer/north-hills');
    await expect(coordinator.getByText(paperReply, { exact: true })).toBeVisible();
    console.info('Paper-card reply returned to volunteer for spoken delivery.');
    await testInfo.attach('live-aws-evidence', { body: JSON.stringify(evidence, null, 2), contentType: 'application/json' });
  } catch (error) {
    await testInfo.attach('coordinator-state', { body: await coordinator.locator('body').innerText(), contentType: 'text/plain' });
    await coordinator.screenshot({ path: testInfo.outputPath('failure-coordinator.png'), fullPage: true });
    throw error;
  } finally {
    await coordinatorContext.close();
  }
});
