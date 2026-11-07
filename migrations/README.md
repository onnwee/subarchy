# migrations

Upgrade migrations, run once per user by `subcult update migrate` (and by `subcult update`), in timestamp order: name them `<unix-time>.sh`. Each runs with `bash -euo pipefail`; a failure leaves it pending. Omarchy names them by Unix timestamp and has 218 in 4.5.0. A Subarchy migration series starts only once Subarchy has installed users.
