# deploy

Files that serve [site/](../site/) at <https://subarchy.subcult.tv>, modelled
on Pult's. The site has been live since 2026-11-13, first from commit
`994d7fc`.

| File | Does |
|---|---|
| `Dockerfile` | Copies `site/` into `nginx-unprivileged`; listens on 8080 |
| `nginx.conf` | Static files, the 404 page, security headers |
| `compose.yml` | The `subarchy-site` container on the shared `projects` network; needs `SUBARCHY_SITE_IMAGE` and `SUBARCHY_SITE_REVISION` |
| `subarchy.Caddyfile` | The route for the edge's Caddy |

Build and try it locally, from the repository root:

```sh
docker build -f deploy/Dockerfile -t subarchy-site:local .
docker run --rm -p 127.0.0.1:18792:8080 subarchy-site:local
```

Deploying is done by hand with the owner's approval: build the image on
the edge host from a `git archive` of the commit, start it with
`compose.yml`, and check that every served file matches the commit by
hash. The route in the shared Caddy is already in place, so a redeploy
only replaces the container. The operations vault has the dated report
and the rollback.
