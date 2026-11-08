.pragma library
// The shell clock's wake-up: milliseconds to the next whole minute of epoch
// time, plus 50 ms slack so the tick lands after the minute changes.
// Always between 50 and 60 050, whatever the clock did (a jump back,
// a repeated hour when daylight saving ends, garbage).
function nextDelayMs(nowMs) {
  const n = Number(nowMs)
  if (!isFinite(n))
    return 60050
  const into = ((n % 60000) + 60000) % 60000
  return Math.max(50, Math.min(60050, 60000 - into + 50))
}
