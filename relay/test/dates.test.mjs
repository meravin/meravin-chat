// These expectations are read straight off the reference screen recording, so
// they double as a check that the Home screen's arithmetic matches the original.
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { dayCount, daysBetween, greeting, headerDate, nextAnnual, nextMonthly } from '../api/dates.mjs'

const TODAY = '2026-07-26'
const TOGETHER_SINCE = '2026-06-22'

test('Day N matches the reference screen', () => {
  assert.equal(dayCount(TOGETHER_SINCE, TODAY), 35)
  assert.equal(dayCount(TODAY, TODAY), 1, 'the first day is Day 1')
  assert.equal(dayCount('2026-08-01', TODAY), null, 'a future start date has no count')
})

test('annual countdowns match the reference screen', () => {
  assert.deepEqual(nextAnnual('01-06', TODAY), { date: '2027-01-06', daysUntil: 164 })
  assert.deepEqual(nextAnnual('06-22', TODAY), { date: '2027-06-22', daysUntil: 331 })
})

test('the monthly anniversary matches the reference ring', () => {
  assert.deepEqual(nextMonthly(TOGETHER_SINCE, TODAY), { date: '2026-08-22', daysUntil: 27 })
})

test('a full YYYY-MM-DD is accepted for annual dates', () => {
  assert.deepEqual(nextAnnual('1999-01-06', TODAY), nextAnnual('01-06', TODAY))
})

test('an anniversary later today counts as today', () => {
  assert.deepEqual(nextAnnual('07-26', TODAY), { date: '2026-07-26', daysUntil: 0 })
})

test('the monthly anniversary skips today and finds the next one', () => {
  // Started on the 26th, and today is the 26th: the next one is a month out.
  assert.deepEqual(nextMonthly('2026-05-26', TODAY), { date: '2026-08-26', daysUntil: 31 })
})

test('short months clamp instead of overflowing', () => {
  // The 31st has no counterpart in April.
  assert.deepEqual(nextMonthly('2026-01-31', '2026-04-05'), { date: '2026-04-30', daysUntil: 25 })
})

test('day arithmetic survives a DST boundary', () => {
  // US DST starts 2026-03-08; a naive local-time subtraction returns 0.958 days.
  assert.equal(daysBetween('2026-03-07', '2026-03-09'), 2)
})

test('greeting buckets match the reference header', () => {
  const at = (h) => greeting(new Date(2026, 6, 26, h, 0, 0))
  assert.equal(at(23), 'Good evening') // reference screenshot: 11:57 PM
  assert.equal(at(9), 'Good morning')
  assert.equal(at(14), 'Good afternoon')
  assert.equal(at(3), 'Good night')
})

test('the header date reads like the reference', () => {
  assert.equal(headerDate(new Date(2026, 6, 26, 23, 57)), 'Sunday, July 26')
})
