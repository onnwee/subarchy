.pragma library
// Workspace slots 1..count for one output: occupied when it has windows,
// active when it is the workspace shown on this output.

function slots(workspaces, outputName, count) {
  const byId = {}
  for (const w of workspaces || [])
    if (w.id >= 1 && w.id <= count)
      byId[w.id] = w
  const out = []
  for (let id = 1; id <= count; id++) {
    const w = byId[id]
    out.push({
      id: id,
      occupied: !!w && w.windows > 0,
      active: !!w && w.active && w.monitor === outputName
    })
  }
  return out
}

function label(id) {
  return id === 10 ? "0" : String(id)
}
