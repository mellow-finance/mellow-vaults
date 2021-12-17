require("./helpers");
const fs = require("fs");
const path = require("path");

const INPUT_DIR = "contracts";
const CONFIG_DIR = "docgen";
const OUTPUT_DIR = "docs";

const root = path.resolve(path.join(__dirname, ".."));

const { docgen } = require("solidity-docgen/dist/docgen.js");
const { preprocess } = require("./preprocess.js");

const flags = {
  input: INPUT_DIR,
  output: OUTPUT_DIR,
  templates: CONFIG_DIR,
  "solc-module": `${root}/node_modules/solc/index.js`,
  "solc-settings": { optimizer: { enabled: true, runs: 200 } },
  "output-structure": "contracts",
  extension: "md",
};

const docsDir = path.resolve(path.join(OUTPUT_DIR, "..", "docs"));
fs.rmSync(docsDir, { force: true, recursive: true });
docgen(flags).then(() => {
  preprocess();
});
