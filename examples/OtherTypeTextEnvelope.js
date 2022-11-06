/* global BROWSER_RUNTIME */

let script;
if (typeof BROWSER_RUNTIME != "undefined" && BROWSER_RUNTIME) {
  script = require("Scripts/other-type-text-envelope.plutus");
} else {
  const fs = require("fs");
  const path = require("path");
  script = fs.readFileSync(
    path.resolve(
      __dirname,
      "../../fixtures/scripts/other-type-text-envelope.plutus"
    ),
    "utf8"
  );
}
exports.otherTypeTextEnvelope = script;
