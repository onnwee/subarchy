import QtQuick
import QtTest
import "../Model.js" as Model

TestCase {
  name: "N8n"

  readonly property string body: '{"data":[{"id":"a1","name":"Backups","active":true,"updatedAt":"2026-11-08T10:00:00Z"},{"id":"b2","name":"Alerts","active":false},{"id":"c3","name":"Sync","active":true}],"nextCursor":null}'
    + '\n---subcult---\n'
    + '{"data":[{"id":"900","workflowId":"a1","status":"error","startedAt":"2026-11-08T14:00:00Z","stoppedAt":"2026-11-08T14:00:05Z"},{"id":"901","workflowId":"zz","status":"error","startedAt":"2026-11-07T10:00:00Z"}]}'

  function test_serverUrl() {
    compare(Model.serverUrl({ server: "https://n8n.example.net/" }), "https://n8n.example.net")
    compare(Model.serverUrl({ server: " http://10.0.0.200:5678 " }), "http://10.0.0.200:5678")
    compare(Model.serverUrl({ server: "https://n8n.example.net/base/" }), "https://n8n.example.net/base")
    compare(Model.serverUrl({ server: "n8n.example.net" }), "", "a scheme is required")
    compare(Model.serverUrl({ server: "https://n8n.example.net/?x=$(id)" }), "", "nothing beyond a path")
    compare(Model.serverUrl({}), "")
  }

  function test_fetchCommand() {
    const c = Model.fetchCommand("https://n8n.example.net")
    compare(c[0], "sh")
    compare(c[c.length - 1], "https://n8n.example.net")
    verify(c[2].indexOf("secret-tool lookup service subcult-n8n") >= 0)
    verify(c[2].indexOf("-K -") >= 0, "the key reaches curl through its config on stdin")
    verify(c[2].indexOf("$1/api/v1/workflows") >= 0 && c[2].indexOf("$1/api/v1/executions?status=error") >= 0)
    verify(c[2].indexOf("---subcult---") >= 0)
    verify(c[2].indexOf("-eq 22 ] && exit 5") >= 0, "an HTTP error (curl 22): wrong key or wrong URL")
  }

  function test_parse() {
    const d = Model.parse(body)
    verify(d !== null)
    compare(d.workflows.map(w => w.name), ["Backups", "Sync", "Alerts"], "active first, then by name")
    compare(d.workflows[2].active, false)
    compare(d.failed.length, 2)
    compare(d.failed[0].workflowId, "a1")
    compare(Model.parse("not json\n---subcult---\n{}"), null)
    compare(Model.parse('{"data":[]}'), null, "both documents are needed")
    compare(Model.parse('{"data":"x"}\n---subcult---\n{"data":[]}'), null)
  }

  function test_label() {
    const d = Model.parse(body)
    compare(Model.label(d), "2/3 ✗2")
    compare(Model.label({ workflows: [{ active: true }], failed: [] }), "1/1")
    compare(Model.label(null), "")
  }

  function test_names_and_errors() {
    const d = Model.parse(body)
    compare(Model.workflowName(d, "a1"), "Backups")
    compare(Model.workflowName(d, "zz"), "workflow zz")
    compare(Model.errorText(3), "No API key in the keyring")
    compare(Model.errorText(4), "The server did not answer")
    compare(Model.errorText(5), "The server answered with an error (check the key and the URL)")
    compare(Model.errorText(0), "")
    verify(Model.errorText(7).indexOf("7") > 0)
    verify(Model.storeHint().indexOf("secret-tool store") === 0)
  }

  function test_ago() {
    const now = new Date("2026-11-08T15:00:00Z")
    compare(Model.ago("2026-11-08T14:59:30Z", now), "just now")
    compare(Model.ago("2026-11-08T14:40:00Z", now), "20 min ago")
    compare(Model.ago("2026-11-08T12:00:00Z", now), "3 h ago")
    compare(Model.ago("2026-11-05T15:00:00Z", now), "3 d ago")
    compare(Model.ago("", now), "")
  }
}
