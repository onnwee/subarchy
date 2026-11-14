import QtQuick
import QtTest
import "../Model.js" as Model

TestCase {
  name: "Tailscale"

  // Trimmed from `tailscale status --json` (1.104).
  readonly property string signedIn: JSON.stringify({
    Version: "1.104.7",
    BackendState: "Running",
    AuthURL: "",
    TailscaleIPs: ["100.64.0.1", "fd7a:115c:a1e0::1"],
    Self: { ID: "n1", HostName: "sputnik", DNSName: "sputnik.tail1234.ts.net.", OS: "linux", TailscaleIPs: ["100.64.0.1", "fd7a:115c:a1e0::1"], Online: true },
    CurrentTailnet: { Name: "subcult.example", MagicDNSSuffix: "tail1234.ts.net" },
    Peer: {
      "nodekey:a": { ID: "n2", HostName: "kvant", DNSName: "kvant.tail1234.ts.net.", OS: "linux", TailscaleIPs: ["100.64.0.2"], Online: true, ExitNodeOption: true, ExitNode: true, TaildropTarget: 1 },
      "nodekey:b": { ID: "n3", HostName: "Phone", DNSName: "", OS: "iOS", TailscaleIPs: ["fd7a:115c:a1e0::3", "100.64.0.3"], Online: false, TaildropTarget: 5 },
      "nodekey:c": { ID: "n4", HostName: "almaz", DNSName: "almaz.tail1234.ts.net.", OS: "linux", TailscaleIPs: ["100.64.0.4"], Online: true, TaildropTarget: 9 }
    }
  })

  readonly property string signedOut: JSON.stringify({
    BackendState: "NeedsLogin", AuthURL: "", TailscaleIPs: null,
    Self: { ID: "", HostName: "fresh", DNSName: "", TailscaleIPs: null, TaildropTarget: 0 }, Health: ["Tailscale is stopped."]
  })

  function test_parse() {
    compare(Model.parse("nope"), null)
    compare(Model.parse("{}"), null)
    const s = Model.parse(signedIn)
    verify(s.running)
    verify(!s.needsLogin)
    compare(s.tailnet, "subcult.example")
    compare(s.self.name, "sputnik")
    compare(s.self.ip, "100.64.0.1")
    compare(s.self.ipv6, "fd7a:115c:a1e0::1")
    compare(s.self.dnsName, "sputnik.tail1234.ts.net")
    compare(s.exitNode.name, "kvant")
  }

  function test_peersOnlineFirstThenByName() {
    const s = Model.parse(signedIn)
    compare(s.peers.map(p => p.name), ["almaz", "kvant", "Phone"])
    compare(Model.online(s).length, 2)
    compare(Model.online(null), [])
  }

  function test_peerFields() {
    const s = Model.parse(signedIn)
    const phone = s.peers[2]
    compare(phone.ip, "100.64.0.3", "the IPv4 address, whatever the order")
    compare(phone.name, "Phone", "the host name without a MagicDNS name")
    verify(!phone.taildrop)
    verify(s.peers[1].taildrop)
    verify(!s.peers[0].taildrop, "another user's machine takes no files")
    verify(s.peers[1].exitNodeOption)
  }

  function test_signedOut() {
    const s = Model.parse(signedOut)
    verify(s.needsLogin)
    verify(!s.running)
    compare(s.peers, [])
    compare(s.self.ip, "")
    compare(s.exitNode, null)
    compare(Model.stateText(s, false), "Signed out")
    compare(Model.tooltip(s, false), "Tailscale: Signed out")
    const withUrl = Model.parse(JSON.stringify({ BackendState: "NeedsLogin", AuthURL: "https://login.tailscale.com/a/abc" }))
    compare(withUrl.authUrl, "https://login.tailscale.com/a/abc")
  }

  // From `tailscale switch --list --json` (1.104).
  function test_accounts() {
    compare(Model.parseAccounts("nope"), [])
    compare(Model.parseAccounts(""), [])
    compare(Model.parseAccounts("{}"), [])
    compare(Model.parseAccounts("null"), [])
    const list = Model.parseAccounts(JSON.stringify([
      { id: "7921", nickname: "me@example.com", tailnet: "subcult", account: "me@example.com", selected: true },
      { id: "a3f0", nickname: "", tailnet: "work.example", account: "me@work.example", selected: false },
      { id: "", tailnet: "no id" },
      null,
      { id: "b1c2" }
    ]))
    compare(list.length, 3, "entries without an ID are dropped")
    compare(list[0], { id: "7921", tailnet: "subcult", account: "me@example.com", nickname: "me@example.com", selected: true })
    compare(list[2], { id: "b1c2", tailnet: "", account: "", nickname: "", selected: false }, "missing fields are empty")
    verify(!list[1].selected)
  }

  function test_accountLabels() {
    const list = Model.parseAccounts(JSON.stringify([
      { id: "1", tailnet: "subcult", account: "me@example.com", selected: true },
      { id: "2", tailnet: "work.example", account: "me@work.example" },
      { id: "3", tailnet: "work.example", account: "other@work.example" },
      { id: "4", nickname: "laptop" },
      { id: "5" }
    ]))
    compare(Model.accountLabel(list[0], list), "subcult")
    compare(Model.accountLabel(list[1], list), "work.example · me@work.example", "two accounts in one tailnet")
    compare(Model.accountLabel(list[2], list), "work.example · other@work.example")
    compare(Model.accountLabel(list[3], list), "laptop", "no tailnet: the nickname")
    compare(Model.accountLabel(list[4], list), "5", "nothing else: the ID")
    compare(Model.accountLabel(list[1], null), "work.example")
  }

  function test_text() {
    const s = Model.parse(signedIn)
    compare(Model.stateText(s, false), "Connected")
    compare(Model.stateText(null, true), "The Tailscale service is not running")
    compare(Model.stateText(Model.parse('{"BackendState": "Stopped"}'), false), "Off")
    compare(Model.tooltip(s, false), "Tailscale: Connected\nsputnik 100.64.0.1\n2 machines online\nExit node: kvant")
    compare(Model.tooltip(null, false), "Tailscale: unknown")
  }

  function test_commandOutput() {
    compare(Model.loginUrl("\thttps://login.tailscale.com/a/gd13d0bed525528e"), "https://login.tailscale.com/a/gd13d0bed525528e")
    compare(Model.loginUrl("To authenticate, visit:"), "")
    compare(Model.loginUrl("https://login.tailscale.com/a/abc\n"), "https://login.tailscale.com/a/abc", "the helper's output")
    verify(Model.daemonDown("failed to connect to local tailscaled; it doesn't appear to be running"))
    compare(Model.errorText("Access denied: prefs write access denied\n\nUse 'sudo tailscale down'.\nTo not require root, use 'sudo tailscale set --operator=$USER' once.\n"),
      "Access denied: prefs write access denied")
    compare(Model.errorText(""), "")
    compare(Model.errorText("\nTo authenticate, visit:\n\n\thttps://login.tailscale.com/a/abc\n\nbackend error: timed out\n"), "backend error: timed out")
  }

  // Changes go through pkexec and the root helper; nothing asks tailscaled
  // directly, which would need operator rights.
  function test_commands() {
    const s = Model.parse(signedIn)
    const helper = "/usr/lib/subcult/tailscale-helper"
    compare(Model.helperCommand("up"), ["pkexec", helper, "up"])
    compare(Model.helperCommand("login"), ["pkexec", helper, "login"])
    compare(Model.helperCommand("down"), ["pkexec", helper, "down"])
    compare(Model.switchCommand("7921"), ["pkexec", helper, "switch", "7921"])
    compare(Model.addAccountCommand(), ["pkexec", helper, "add"])
    compare(Model.exitNodeCommand(s.peers[1]), ["pkexec", helper, "exit-node", "100.64.0.2"])
    compare(Model.exitNodeCommand(null), ["pkexec", helper, "exit-node", ""])
    compare(Model.exitNodeCommand({ ip: "", ipv6: "fd7a:115c:a1e0::9", dnsName: "v6only.tail1234.ts.net" }),
      ["pkexec", helper, "exit-node", "fd7a:115c:a1e0::9"], "no IPv4: the IPv6 address, never an empty one")
    compare(Model.sendCommand(s.peers[0]), ["subcult-tailscale-send", "--name", "almaz", "100.64.0.4"])
    compare(Model.sendCommand(s.peers[2]), ["subcult-tailscale-send", "--name", "Phone", "100.64.0.3"], "by address, whatever the peer is called")
    compare(Model.sendCommand({ name: "", ip: "", ipv6: "", dnsName: "x.tail1234.ts.net" }),
      ["subcult-tailscale-send", "--name", "x.tail1234.ts.net", "x.tail1234.ts.net"])
  }
}
