const NODE_DIR = "node_modules";
const INPUT_DIR = "contracts";
const CONFIG_DIR = "docgen";
const EXCLUDE_FILE = "docgen/exclude.txt";
const OUTPUT_DIR = "docs";

const fs = require("fs");
const path = require("path");
const spawnSync = require("child_process").spawnSync;

const excludeList = lines(EXCLUDE_FILE);

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
  "--solc-module=solc",
  "--solc-settings=" +
    JSON.stringify({ optimizer: { enabled: true, runs: 200 } }),
  "--output-structure=contracts",
];

const getAllFiles = function (dirPath, arrayOfFiles) {
  files = fs.readdirSync(dirPath);

  arrayOfFiles = arrayOfFiles || [];

  files.forEach(function (file) {
    for (const rule of excludeList) {
      const fullFile = dirPath + "/" + file;
      if (fullFile.match(rule)) {
        return;
      }
    }
    if (fs.statSync(dirPath + "/" + file).isDirectory()) {
      arrayOfFiles = getAllFiles(dirPath + "/" + file, arrayOfFiles);
    } else {
      arrayOfFiles.push(path.join(dirPath, "/", file));
    }
  });

  return arrayOfFiles;
};

const docsDir = path.resolve(path.join(OUTPUT_DIR, "..", "docs"));
fs.rmSync(docsDir, { force: true, recursive: true });
const result = spawnSync("node", args, {
  stdio: ["inherit", "inherit", "pipe"],
});
if (result.stderr.length > 0) throw new Error(result.stderr);

let res = "";

getAllFiles(docsDir).forEach((file) => {
  const data = fs.readFileSync(file);
  res += `${data}\n`;
});

fs.writeFileSync(path.resolve(path.join(docsDir, "api.md")), res);
