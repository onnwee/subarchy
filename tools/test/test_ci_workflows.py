#!/usr/bin/env python3
"""Check how the Gitea main-branch workflows share the single subarchy-kvm slot.

On 2026-11-20 the packages publish job waited behind ISO runs on the one
slot for hours, and an ISO run scheduled before its commit's packages were
published could not find new pins (#264). A main push must therefore start
one run on that label, whose ISO job waits for the publish job.
"""

from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]
WORKFLOWS = ROOT / ".gitea/workflows"


def load(name):
    """Split a workflow into its top-level sections and its jobs, as text.

    Plain text, not YAML: the Ubuntu verify jobs need not have PyYAML.
    """
    text = (WORKFLOWS / name).read_text()
    sections = dict(re.findall(r"^([a-z]\w*):\n((?:(?:[ #].*)?\n)*)", text, re.M))
    jobs = dict(re.findall(r"^  ([\w-]+):\n((?:(?:    .*)?\n)*)", sections["jobs"], re.M))
    return sections, jobs


def field(job, key):
    found = re.search(rf"^    {key}: (.*)$", job, re.M)
    return found and found.group(1)


def steps(job):
    return job.split("\n    steps:\n", 1)[1]


class MainBranchQueue(unittest.TestCase):
    def test_one_workflow_uses_the_kvm_slot_on_a_main_push(self):
        users = []
        for path in sorted(WORKFLOWS.glob("*.yml")):
            sections, jobs = load(path.name)
            kvm = [job for job in jobs.values() if field(job, "runs-on") == "subarchy-kvm"]
            if kvm and re.search(r"^    branches: \[main\]$", sections["on"], re.M):
                users.append(path.name)
        self.assertEqual(users, ["packages.yml"])

    def test_iso_runs_after_publish(self):
        _, jobs = load("packages.yml")
        net = jobs["iso-net"]
        self.assertEqual(field(net, "needs"), "publish")
        self.assertEqual(field(net, "if"), field(jobs["publish"], "if"))
        self.assertIn("tools/ci/build-iso.sh net", steps(net))
        self.assertIn("tools/ci/install-test.sh net", steps(net))

    def test_iso_workflow_keeps_tags_and_manual_runs(self):
        sections, jobs = load("iso.yml")
        self.assertEqual(sections["on"], "  push:\n    tags: ['v*']\n  workflow_dispatch:\n\n")
        self.assertIsNone(field(jobs["net"], "if"))

    def test_both_net_jobs_run_the_same_steps(self):
        # The main-push copy must not drift from the tag and manual one.
        self.assertEqual(steps(load("packages.yml")[1]["iso-net"]).rstrip(),
                         steps(load("iso.yml")[1]["net"]).rstrip())


if __name__ == "__main__":
    unittest.main()
