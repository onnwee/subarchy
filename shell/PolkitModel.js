.pragma library
// The polkit dialog's choices.

// Which of the identities polkit offers to authenticate as: the current
// user when it is one of them, else the first. identities are
// { string, isGroup }, as Quickshell's polkit Identity exposes them.
function pickIdentity(identities, userName) {
  const list = identities || []
  const i = userName ? list.findIndex(id => id && !id.isGroup && id.string === userName) : -1
  return i >= 0 ? i : 0
}
