# deploy

Files that serve [site/](../site/) at <https://subarchy.subcult.tv>, modelled
on Pult's. The site is not deployed yet.

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

Deploying changes the shared Caddy on the edge host, so it is done by hand
with the owner's approval, following the Pult website deployment report in
the operations vault.
