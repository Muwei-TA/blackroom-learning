import assert from 'node:assert/strict';
import { test } from 'node:test';
let rules;
try { rules = await import('../../assets/javascripts/discourse/lib/client-rules.js'); } catch { /* first RED run */ }
function loaded() { assert.ok(rules, 'Missing client rules implementation'); }

test('30 inclusive learning days end on the 30th day', () => {
  loaded(); assert.equal(rules.defaultEndDate('2026-10-13', 30), '2026-11-11');
});
test('one day begins and ends on the same date', () => {
  loaded(); assert.equal(rules.defaultEndDate('2026-10-13', 1), '2026-10-13');
});
test('calendar arithmetic handles leap years without local timezone drift', () => {
  loaded(); assert.equal(rules.defaultEndDate('2028-02-28', 3), '2028-03-01');
});
test('invalid dates and counts are rejected', () => {
  loaded();
  for (const [date, n] of [['2026-02-30', 3], ['2026-1-1', 3], ['2026-10-13', 0], ['2026-10-13', 1.5], ['2026-10-13', 367]]) {
    assert.equal(rules.defaultEndDate(date, n), '');
  }
});
test('calendar distinguishes checked, uncompleted and future days', () => {
  loaded();
  const days = rules.calendarDays('2026-10-12', '2026-10-14', ['2026-10-12', '2026-10-12'], '2026-10-13');
  assert.deepEqual(days.map(d => d.state), ['complete', 'open', 'future']);
  assert.equal(days.length, 3);
});
test('unbounded and reversed calendar ranges are rejected', () => {
  loaded(); assert.deepEqual(rules.calendarDays('2026-10-14', '2026-10-13', [], '2026-10-13'), []);
  assert.deepEqual(rules.calendarDays('2026-01-01', '2030-01-01', [], '2026-10-13'), []);
});
test('goal links encode the identifier', () => {
  loaded(); assert.equal(rules.goalLink(12), '/learning?goal_id=12');
  assert.throws(() => rules.goalLink('../admin'));
});
test('profile links cannot inject additional query arguments', () => {
  loaded(); assert.equal(rules.profileLink('a&admin=true'), '/learning?username=a%26admin%3Dtrue');
});
test('request tokens have UUID shape', () => {
  loaded(); assert.match(rules.requestToken(), /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/);
});
test('error extraction handles validation and network errors', () => {
  loaded();
  assert.equal(rules.errorText({ jqXHR: { responseJSON: { errors: ['日期错误', '目标无效'] } } }, '请求失败'), '日期错误；目标无效');
  assert.equal(rules.errorText({}, '请求失败'), '请求失败');
});
