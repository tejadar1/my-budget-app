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
    await page.getByRole('button', { name: 'Try the demo' }).waitFor({ timeout: 60000 });
    await shoot(page, `${colorScheme}-a00-welcome`);
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

  const scrollDown = async () => {
    await page.evaluate(() => {
      for (const el of document.querySelectorAll('*')) {
        const style = getComputedStyle(el);
        if (el.scrollHeight > el.clientHeight + 50 && /(auto|scroll)/.test(style.overflowY)) {
          el.scrollTop = 650;
        }
      }
    });
  };

  await step('names', async () => {
    await tab(page, 'Budget');
    await shoot(page, `${colorScheme}-0-names-setup`);
    await page.getByLabel('Your name').fill('Ron');
    await page.getByLabel('Partner’s name').fill('Ana');
    await page.getByRole('button', { name: 'Save', exact: true }).click();
  });

  await step('accounts-unclaimed', async () => {
    await tab(page, 'Accounts');
    await shoot(page, `${colorScheme}-1-accounts-whose`);
  });

  await step('assign-owners', async () => {
    const picks = ['Ron', 'Ana', 'Shared'];
    for (let i = 0; i < 12; i++) {
      const region = page.getByRole('region', { name: 'Whose accounts are these?' });
      if (!(await region.isVisible().catch(() => false))) break;
      const group = region.getByRole('radiogroup').first();
      if (!(await group.isVisible().catch(() => false))) break;
      await group.getByRole('radio', { name: picks[i % picks.length] }).click();
      await page.waitForTimeout(400);
    }
    await shoot(page, `${colorScheme}-2-accounts`);
    await scrollDown();
    await shoot(page, `${colorScheme}-3-accounts-scrolled`);
  });

  await step('budget', async () => {
    await tab(page, 'Budget');
    await page.waitForTimeout(1500);
    await shoot(page, `${colorScheme}-4-budget`);
  });
  await step('budget-scrolled', async () => {
    await scrollDown();
    await shoot(page, `${colorScheme}-5-budget-scrolled`);
  });
  await step('limits', async () => {
    await tab(page, 'Budget');
    await page.getByRole('link', { name: /Edit limits/i }).first().click();
    await shoot(page, `${colorScheme}-6-limits`);
  });
  await step('reports', async () => {
    await tab(page, 'Reports');
    await shoot(page, `${colorScheme}-7-reports`);
  });
  await step('settings', async () => {
    await tab(page, 'Settings');
    await shoot(page, `${colorScheme}-8-settings`);
  });

  // In-app navigation without a reload (React Router listens to popstate).
  const go = async route => {
    await page.evaluate(r => {
      window.history.pushState({}, '', r);
      window.dispatchEvent(new PopStateEvent('popstate'));
    }, route);
    await page.waitForTimeout(800);
  };
  const audit = async (name, fn) => step(`audit-${name}`, async () => {
    await fn();
    await shoot(page, `${colorScheme}-a-${name}`);
  });

  await audit('category', async () => {
    await tab(page, 'Budget');
    await page.getByRole('button', { name: /^Food/ }).first().click();
  });
  await audit('account', async () => {
    await tab(page, 'Accounts');
    await page.locator('button[aria-expanded]').first().click();
    await page.getByRole('link', { name: 'See transactions' }).first().click();
  });
  await audit('transaction', async () => {
    await page.getByLabel('Transaction list').getByRole('button').first().click();
  });
  const routes = [
    ['settings', '/settings'],
    ['settings-general', '/settings/general'],
    ['settings-bank-sync', '/settings/bank-sync'],
    ['settings-payees', '/settings/payees'],
    ['settings-rules', '/settings/rules'],
    ['settings-tags', '/settings/tags'],
    ['settings-advanced', '/settings/advanced'],
    ['settings-experimental', '/settings/experimental'],
    ['schedules', '/schedules'],
    ['payees', '/payees'],
    ['rules', '/rules'],
    ['bank-sync', '/bank-sync'],
    ['reports', '/reports'],
    ['notifications', '/notifications'],
  ];
  for (const [name, route] of routes) {
    await audit(name, () => go(route));
  }
  await audit('budget-menu', async () => {
    await go('/budget/limits');
    await page.getByRole('button', { name: /menu/i }).first().click();
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
