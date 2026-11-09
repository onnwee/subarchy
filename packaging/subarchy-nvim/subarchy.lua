-- Subarchy's layer over the LazyVim starter (ADR 0045, issue #121): the
-- SUBCULT mark on the dashboard, the colour scheme that follows the active
-- theme (the `subcult` scheme the subarchy package installs), and a
-- Subarchy name. Written for Subarchy; the starter stays as it is.
local mark = {
  [[          ▄▄▄▄▄▄▄          ▄▄▄▄▄          ]],
  [[       ▄███████████▄▄ ▄▄█████▀█████▄      ]],
  [[       ██████▄ ▀▀▀▀▀  ██████   ██████     ]],
  [[        ▀▀██████▄▄    ██████    ██        ]],
  [[          ██▀▀██████▄ ██████   ▄▄█▄▄▄     ]],
  [[       █████▄  ██████ ▀█████   █████▀     ]],
  [[        ▀▀████████▀▀   ▀▀██████████▀      ]],
  [[           ▀▀▀▀▀▀▀▀▀▀▀█████████████▄▄     ]],
  [[                                          ]],
  [[         S U B C U L T  //  S U B A R C H Y]],
}

vim.g.subarchy_layer = "subarchy-nvim"

return {
  -- The colour scheme: `subcult` follows ~/.config/subcult/theme/palette.json.
  {
    "LazyVim/LazyVim",
    opts = { colorscheme = "subcult" },
  },
  -- The dashboard: the mark, then the starter's keys.
  {
    "folke/snacks.nvim",
    opts = {
      dashboard = {
        preset = { header = table.concat(mark, "\n") },
      },
    },
  },
}
