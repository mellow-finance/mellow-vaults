const NODE_DIR = "node_modules";
const INPUT_DIR = "contracts";
const CONFIG_DIR = "docgen";
const EXCLUDE_FILE = "docgen/exclude.txt";
const OUTPUT_DIR = "docs";

const fs = require("fs");
const spawnSync = require("child_process").spawnSync;

const excludeList = lines(EXCLUDE_FILE).map((line) => INPUT_DIR + "/" + line);

function lines(pathName) {
  return fs
    .readFileSync(pathName, { encoding: "utf8" })
    .split("\r")
    .join("")
    .split("\n");
}

const args = [
  NODE_DIR + "/solidity-docgen/dist/cli.js",
  "--input=" + INPUT_DIR,
  "--output=" + OUTPUT_DIR,
  "--templates=" + CONFIG_DIR,
  "--exclude=" + excludeList.join(","),
  "--solc-module=solc",
  "--solc-settings=" +
    JSON.stringify({ optimizer: { enabled: true, runs: 200 } }),
  "--output-structure=single",
];

const result = spawnSync("node", args, {
  stdio: ["inherit", "inherit", "pipe"],
});
if (result.stderr.length > 0) throw new Error(result.stderr);

fs.renameSync(`${OUTPUT_DIR}/index.md`, `${OUTPUT_DIR}/api.md`);
