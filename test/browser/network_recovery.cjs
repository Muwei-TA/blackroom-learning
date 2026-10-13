// Run against an explicitly enabled, isolated Discourse with synthetic accounts.
// NODE_PATH points to the installed Playwright package; no dependencies are downloaded.
const { chromium } = require('playwright');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const base = process.env.QA_BASE_URL;
const fixturePath = process.env.QA_FIXTURE;
const out = process.env.QA_OUTPUT;
assert(base && fixturePath && out, 'Set QA_BASE_URL, QA_FIXTURE, QA_OUTPUT explicitly.');
const fixture = JSON.parse(fs.readFileSync(fixturePath));
assert(fixture.password, 'Synthetic fixture must be enabled. Never use production credentials.');
const nonce = Date.now().toString(36);
const checks = [], errors = [], requests = [];
let browser, page;
const ok = (name, detail = {}) => { checks.push({ name, passed: true, detail }); console.log('PASS', name); };
const key = body => new URLSearchParams(body).get('request_key');
const screenshot = name => page.screenshot({ path: path.join(out, `${name}.png`), fullPage: true });
const responseFor = endpoint => page.waitForResponse(r => r.url().endsWith(endpoint) && r.request().method() === 'POST');
async function clickSubmit(endpoint, button) {
  const waiting = responseFor(endpoint);
  await page.getByRole('button', { name: button, exact: true }).click();
  const response = await waiting;
  assert.equal(response.status(), 201, await response.text());
  return { body: await response.json(), payload: response.request().postData() };
}
async function interruptedSubmit(endpoint, button, form, committed) {
  let original, result;
  await page.route(`**${endpoint}`, async route => {
    original = route.request().postData();
    if (committed) {
      const response = await route.fetch({ timeout: 15000 });
      assert.equal(response.status(), 201);
      result = await response.json();
      console.log('Committed response intentionally discarded:', endpoint, result.goal?.id, result.post_url || '');
    }
    requests.push({ endpoint, committed, request_key: key(original), result });
    await route.abort('failed');
  });
  await page.getByRole('button', { name: button, exact: true }).click();
  await page.locator(`${form} .bl-error`).waitFor({ timeout: 10000 });
  await page.unroute(`**${endpoint}`);
  assert.equal(await page.getByRole('button', { name: button, exact: true }).isDisabled(), false);
  assert.equal(await page.locator(`${form} fieldset`).isDisabled(), false);
  await screenshot(`${requests.length}-network-error`);
  return { original, result };
}
async function goalFields(label) {
  await page.getByLabel('目标名称', { exact: true }).fill(label);
  await page.getByLabel('每日学习约定', { exact: true }).fill('记录纯合成学习笔记，验证真实浏览器网络中断后的恢复。');
  await page.getByLabel('需要完成的学习天数', { exact: true }).fill('3');
}
async function cancelNormally() {
  const button = page.getByRole('button', { name: '结束目标', exact: true }).first();
  if (await button.count()) {
    await button.click();
    await page.getByLabel('目标名称', { exact: true }).waitFor();
  }
}
(async () => {
  fs.mkdirSync(out, { recursive: true });
  browser = await chromium.launch({ headless: true, executablePath: process.env.QA_BROWSER_BINARY || undefined, args: ['--no-sandbox'] });
  page = await browser.newPage({ viewport: { width: 1280, height: 1000 } });
  page.on('pageerror', e => errors.push(e.message));
  page.on('dialog', dialog => dialog.accept());
  await page.goto(`${base}/login`);
  await page.locator('#login-account-name').fill(fixture.users[0].username);
  await page.locator('#login-account-password').fill(fixture.password);
  const login = responseFor('/session');
  await page.getByRole('button', { name: '登录', exact: true }).first().click();
  assert.equal((await login).status(), 200);
  await page.waitForURL(url => url.pathname !== '/login');
  await page.goto(`${base}/learning`);
  await page.locator('main.bl-learning').waitFor();
  await cancelNormally();
  const label = `网络恢复目标 ${nonce}`;
  await goalFields(label);
  let goalLoss = await interruptedSubmit('/learning/goals.json', '发布我的 Flag', '.bl-create .bl-form', true);
  assert.equal(await page.getByLabel('目标名称', { exact: true }).inputValue(), label);
  const retryGoal = await clickSubmit('/learning/goals.json', '发布我的 Flag');
  assert.equal(retryGoal.body.goal.id, goalLoss.result.goal.id);
  assert.equal(key(retryGoal.payload), key(goalLoss.original));
  ok('Committed goal response loss: error, enabled form, retained UUID and same goal', { goal_id: retryGoal.body.goal.id, request_key: key(retryGoal.payload) });
  await page.getByRole('button', { name: '去打卡', exact: true }).first().click();
  const title = `真实浏览器断网恢复 ${nonce}：学习记录`;
  const raw = `合成网络中断学习笔记 ${nonce}。保留原始内容与编号，服务器已经提交时重试不能重复创建话题。`;
  await page.getByLabel('话题标题', { exact: true }).fill(title);
  await page.getByLabel('今天的学习内容与收获', { exact: true }).fill(raw);
  const postLoss = await interruptedSubmit('/learning/checkins.json', '发布学习话题', '.bl-checkin-form', true);
  assert.equal(await page.getByLabel('话题标题', { exact: true }).inputValue(), title);
  assert.equal(await page.getByLabel('今天的学习内容与收获', { exact: true }).inputValue(), raw);
  const retryPost = await clickSubmit('/learning/checkins.json', '发布学习话题');
  assert.equal(retryPost.body.post_url, postLoss.result.post_url);
  assert.equal(key(retryPost.payload), key(postLoss.original));
  ok('Committed check-in response loss: retained content, UUID and same post', { post_url: retryPost.body.post_url, request_key: key(retryPost.payload) });
  await page.getByLabel('今天的学习内容与收获', { exact: true }).fill(`未送达合成笔记 ${nonce}。请求未到服务器时，界面应提示失败，允许相同内容和编号继续提交。`);
  await page.getByLabel('话题标题', { exact: true }).fill(`未送达后重试 ${nonce}：第二份学习记录`);
  const unsent = await interruptedSubmit('/learning/checkins.json', '发布学习话题', '.bl-checkin-form', false);
  const delivered = await clickSubmit('/learning/checkins.json', '发布学习话题');
  assert.equal(key(delivered.payload), key(unsent.original));
  ok('Unsent check-in: visible error and original UUID retry succeeds', { request_key: key(delivered.payload), post_url: delivered.body.post_url });
  await page.route('**/learning/data.json*', route => route.abort('failed'));
  await page.getByRole('button', { name: '刷新进度', exact: true }).click();
  await page.locator('main.bl-learning > .bl-error').waitFor();
  assert.equal(await page.getByRole('button', { name: '刷新进度', exact: true }).isDisabled(), false);
  await page.unroute('**/learning/data.json*');
  await page.getByRole('button', { name: '刷新进度', exact: true }).click();
  await page.locator('main.bl-learning > .bl-error').waitFor({ state: 'detached' });
  await page.waitForFunction(() => !document.querySelector('main.bl-learning nav button').disabled);
  ok('Refresh network error clears busy and can be retried');
  let cancelled;
  await page.route('**/learning/goals/*/cancel.json', async route => {
    const response = await route.fetch(); assert.equal(response.status(), 200); cancelled = true; await route.abort('failed');
  });
  await page.getByRole('button', { name: '结束目标', exact: true }).first().click();
  await page.locator('main.bl-learning > .bl-error').waitFor();
  assert(cancelled);
  assert.equal(await page.getByRole('button', { name: '结束目标', exact: true }).first().isDisabled(), false);
  await page.unroute('**/learning/goals/*/cancel.json');
  await cancelNormally();
  ok('Cancellation lost response: visible error, enabled controls, idempotent retry');
  await goalFields(`未送达目标 ${nonce}`);
  const unsentGoal = await interruptedSubmit('/learning/goals.json', '发布我的 Flag', '.bl-create .bl-form', false);
  const deliveredGoal = await clickSubmit('/learning/goals.json', '发布我的 Flag');
  assert.equal(key(deliveredGoal.payload), key(unsentGoal.original));
  ok('Unsent goal: retained UUID retry succeeds', { request_key: key(deliveredGoal.payload), goal_id: deliveredGoal.body.goal.id });
  await cancelNormally();
  await page.reload(); await page.locator('main.bl-learning').waitFor();
  const data = await (await page.request.get(`${base}/learning/data.json`)).json();
  assert.equal(data.summary.xp, 10);
  assert.match(await page.locator('.bl-summary').innerText(), /(?:^|\s)10 XP(?:\s|$)/);
  assert.equal(errors.length, 0, errors.join('\n'));
  ok('Reload preserves one daily reward; no uncaught page errors');
  await page.goto(`${base}/t/${fixture.flag_topic_id}`);
  const panel = page.locator('aside.bl-flag-panel');
  await panel.getByRole('button', { name: '刷新进度', exact: true }).waitFor();
  await page.route('**/learning/data.json*', route => route.abort('failed'));
  await panel.getByRole('button', { name: '刷新进度', exact: true }).click();
  await panel.locator('p[role=status]').waitFor();
  assert.equal(await panel.getByRole('button', { name: '刷新进度', exact: true }).isDisabled(), false);
  await page.unroute('**/learning/data.json*');
  await panel.getByRole('button', { name: '刷新进度', exact: true }).click();
  await panel.locator('p[role=status]').waitFor({ state: 'detached' });
  ok('Flag panel network failure releases busy and its refresh succeeds');
  await screenshot('final-recovered');
})().catch(async error => {
  checks.push({ name: 'Network recovery regression', passed: false, error: error.stack });
  console.error(error); process.exitCode = 1;
  if (page) { await screenshot('failure').catch(() => {}); }
}).finally(async () => {
  fs.mkdirSync(out, { recursive: true });
  fs.writeFileSync(path.join(out, 'results.json'), JSON.stringify({ checks, requests, errors }, null, 2));
  await browser?.close();
});
