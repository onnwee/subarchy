.pragma library
// The Tailscale widget's data (ADR 0058): `tailscale status --json`, read
// by services/Tailscale.qml. Only the fields the bar and the panel show.

// TaildropTargetStatus 1: the peer takes files from this machine.
const TAILDROP_AVAILABLE = 1

// "laptop.tail1234.ts.net." -> "laptop"; the host name when there is no
// MagicDNS name.
function shortName(dnsName, hostName) {
  const d = String(dnsName || "").replace(/\.$/, "")
  if (d !== "")
    return d.split(".")[0]
  return String(hostName || "")
}

function ipv4(ips) {
  const list = Array.isArray(ips) ? ips : []
  return list.find(ip => String(ip).indexOf(".") >= 0) || ""
}

function ipv6(ips) {
  const list = Array.isArray(ips) ? ips : []
  return list.find(ip => String(ip).indexOf(":") >= 0) || ""
}

function peer(p) {
  return {
    id: String(p.ID || p.PublicKey || ""),
    name: shortName(p.DNSName, p.HostName),
    dnsName: String(p.DNSName || "").replace(/\.$/, ""),
    ip: ipv4(p.TailscaleIPs),
    ipv6: ipv6(p.TailscaleIPs),
    os: String(p.OS || ""),
    online: p.Online === true,
    exitNode: p.ExitNode === true,
    exitNodeOption: p.ExitNodeOption === true,
    taildrop: Number(p.TaildropTarget) === TAILDROP_AVAILABLE
  }
}

// Online first, then by name.
function sortPeers(list) {
  return list.slice().sort((a, b) => Number(b.online) - Number(a.online) || a.name.localeCompare(b.name))
}

// The status, or null when the text is not one.
function parse(text) {
  let s
  try {
    s = JSON.parse(text)
  } catch (e) {
    return null
  }
  if (!s || typeof s.BackendState !== "string")
    return null
  const self = s.Self || {}
  const peers = s.Peer && typeof s.Peer === "object" ? Object.keys(s.Peer).map(k => peer(s.Peer[k])) : []
  return {
    state: s.BackendState,
    running: s.BackendState === "Running",
    needsLogin: s.BackendState === "NeedsLogin",
    authUrl: /^https:\/\//.test(String(s.AuthURL || "")) ? String(s.AuthURL) : "",
    tailnet: s.CurrentTailnet && s.CurrentTailnet.Name ? String(s.CurrentTailnet.Name) : "",
    self: {
      name: shortName(self.DNSName, self.HostName),
      dnsName: String(self.DNSName || "").replace(/\.$/, ""),
      ip: ipv4(self.TailscaleIPs),
      ipv6: ipv6(self.TailscaleIPs)
    },
    peers: sortPeers(peers),
    exitNode: peers.find(p => p.exitNode) || null
  }
}

function online(status) {
  return status ? status.peers.filter(p => p.online) : []
}

// One line for the bar's tooltip and the panel's header.
function stateText(status, daemonDown) {
  if (daemonDown)
    return "The Tailscale service is not running"
  if (!status)
    return "Tailscale"
  switch (status.state) {
  case "Running": return "Connected"
  case "Stopped": return "Off"
  case "NeedsLogin": return "Signed out"
  case "NeedsMachineAuth": return "Waiting for an admin to approve this machine"
  case "Starting": return "Connecting…"
  }
  return status.state
}

function tooltip(status, daemonDown) {
  const head = "Tailscale: " + stateText(status, daemonDown).replace(/^Tailscale$/, "unknown")
  if (!status || !status.running)
    return head
  const n = online(status).length
  return head + "\n" + status.self.name + " " + status.self.ip + "\n"
    + n + (n === 1 ? " machine" : " machines") + " online"
    + (status.exitNode ? "\nExit node: " + status.exitNode.name : "")
}

// The sign-in link in a line the helper's `login` prints, or "".
function loginUrl(line) {
  const m = /https:\/\/\S+/.exec(String(line || ""))
  return m ? m[0] : ""
}

// No tailscaled to talk to.
function daemonDown(text) {
  return /failed to connect to local tailscaled|is tailscaled running|tailscaled\.sock/i.test(String(text || ""))
}

// The first meaningful line of an error, short enough for the panel. The
// sign-in prompt and the sudo hints are not the error.
function errorText(text) {
  const lines = String(text || "").split("\n").map(l => l.trim()).filter(l => l !== "" && !/^Use 'sudo /.test(l)
    && !/^To not require root/.test(l) && !/^To authenticate, visit:/.test(l) && !/^https:\/\//.test(l))
  const l = lines.length > 0 ? lines[0] : ""
  return l.length > 140 ? l.slice(0, 139) + "…" : l
}

// How to reach a peer: its IPv4 address, else its IPv6 address, else its
// MagicDNS name. An address matches whatever the peer is called; the
// helper takes only addresses.
function address(p) {
  return p.ip || p.ipv6 || p.dnsName
}

// Changes go through the root helper under the polkit action
// tv.subcult.tailscale (no password in the active session): no account is
// tailscaled's operator (ADR 0062). Reading the status needs no rights.
const HELPER = "/usr/lib/subcult/tailscale-helper"

function helperCommand(verb, args) {
  return ["pkexec", HELPER, verb].concat(args || [])
}

// The argv that makes a peer the exit node, or clears it (peer null). The
// helper keeps the local network (router, printers, machines at home)
// reachable while other traffic goes through the exit node.
function exitNodeCommand(p) {
  return helperCommand("exit-node", [p ? address(p) : ""])
}

// The argv that sends files to a peer: by address, named in the
// notification.
function sendCommand(p) {
  return ["subcult-tailscale-send", "--name", p.name || address(p), address(p)]
}
