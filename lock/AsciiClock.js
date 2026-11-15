.pragma library

// Shared login/lock clock: three rows, with aligned digit bounds and centred colon.
function render(value) {
    const glyphs = {
      "0": ["█▀█", "█ █", "▀▀▀"], "1": [" █ ", " █ ", " ▀ "],
      "2": ["▀▀█", "█▀▀", "▀▀▀"], "3": ["▀▀█", " ▀█", "▀▀▀"],
      "4": ["█ █", "▀▀█", "  ▀"], "5": ["█▀▀", "▀▀█", "▀▀▀"],
      "6": ["█▀▀", "█▀█", "▀▀▀"], "7": ["▀▀█", "  █", "  ▀"],
      "8": ["█▀█", "█▀█", "▀▀▀"], "9": ["█▀█", "▀▀█", "▀▀▀"],
      ":": ["▄", "▄", " "]
    }
    return [0, 1, 2].map(row => value.split("").map(c => glyphs[c][row]).join(" ")).join("\n")
  }
