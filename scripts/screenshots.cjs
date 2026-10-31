// Opens the demo budget at iPhone size and screenshots Upside's screens in
// light and dark mode, so changes can be checked against the mockups before
// a build goes to TestFlight.
//
// Usage: node scripts/screenshots.cjs <base-url> <out-dir>
const path = require('node:path');
const fs = require('node:fs');

const actualWeb = path.resolve(__dirname, '..', 'actual', 'packages', 'desktop-client');
const { chromium } = require(require.resolve('@playwright/test', { paths: [actualWeb] }));

const baseURL = process.argv[2] ?? 'http://localhost:5173';
const outDir = path.resolve(process.argv[3] ?? 'previews');
fs.mkdirSync(outDir, { recursive: true });

const log = [];
function note(line) {
  console.log(line);
  log.push(line);
}

async function shoot(page, name) {
  await page.waitForTimeout(1500); // let numbers and animations settle
  const file = path.join(outDir, `${name}.png`);
  await page.screenshot({ path: file });
  note(`saved ${name}.png`);
}

async function tab(page, name) {
  await page.getByRole('navigation', { name: 'Main' }).getByRole('link', { name, exact: true }).click();
}

async function run(colorScheme) {
  const browser = await chromium.launch();
  const context = await browser.newContext({
    viewport: { width: 390, height: 844 },
    deviceScaleFactor: 2,
    isMobile: true,
    hasTouch: true,
    colorScheme,
  });
  const page = await context.newPage();
  page.on('pageerror', e => note(`[${colorScheme}] page error: ${e.message}`));
  page.on('console', m => {
    if (m.type() === 'error') note(`[${colorScheme}] console error: ${m.text()}`);
  });

  const step = async (label, fn) => {
    try {
      await fn();
    } catch (e) {
      note(`[${colorScheme}] FAILED ${label}: ${e.message.split('\n')[0]}`);
      await page.screenshot({ path: path.join(outDir, `${colorScheme}-error-${label}.png`) }).catch(() => {});
    }
  };

  await step('open-demo', async () => {
    await page.goto(baseURL);
    await page.getByRole('button', { name: 'Try the demo' }).click({ timeout: 60000 });
    await page.waitForURL('**/budget', { timeout: 90000 });
  });

  // Upside is built around the tracking budget (limits, see what's left).
  await step('tracking', async () => {
    await tab(page, 'Settings');
    const settings = page.getByTestId('settings');
    const general = page.getByRole('navigation', { name: 'Settings' }).getByRole('link', { name: 'General', exact: true });
    if (await general.isVisible().catch(() => false)) await general.click();
    const toTracking = settings.getByRole('button', { name: /^Switch to tracking budgeting$/i });
    if (await toTracking.isVisible({ timeout: 5000 }).catch(() => false)) await toTracking.click();
  });

  await step('budget', async () => {
    await tab(page, 'Budget');
    await shoot(page, `${colorScheme}-1-budget`);
  });
  await step('budget-scrolled', async () => {
    await page.mouse.wheel(0, 700);
    await shoot(page, `${colorScheme}-2-budget-scrolled`);
  });
  await step('limits', async () => {
    await tab(page, 'Budget');
    await page.getByRole('link', { name: /Edit limits/i }).first().click();
    await shoot(page, `${colorScheme}-3-limits`);
  });
  await step('accounts', async () => {
    await tab(page, 'Accounts');
    await shoot(page, `${colorScheme}-4-accounts`);
  });
  await step('reports', async () => {
    await tab(page, 'Reports');
    await shoot(page, `${colorScheme}-5-reports`);
  });
  await step('settings', async () => {
    await tab(page, 'Settings');
    await shoot(page, `${colorScheme}-6-settings`);
  });

  await browser.close();
}

(async () => {
  for (const scheme of ['light', 'dark']) {
    await run(scheme);
  }
  fs.writeFileSync(path.join(outDir, 'log.txt'), log.join('\n') + '\n');
})().catch(e => {
  note(`fatal: ${e.stack}`);
  fs.writeFileSync(path.join(outDir, 'log.txt'), log.join('\n') + '\n');
  process.exit(1);
});
