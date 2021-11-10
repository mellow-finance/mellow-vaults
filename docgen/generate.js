const NODE_DIR = "node_modules";
const INPUT_DIR = "contracts";
const CONFIG_DIR = "docgen";
const EXCLUDE_FILE = "docgen/exclude.txt";
const OUTPUT_DIR = "docs";
require("./helpers");

const { docgen } = require("solidity-docgen/dist/docgen.js");

const flags = {
  input: "contracts",
  output: "docs",
  templates: "/Users/alex/dev/mellow-permissionless-vaults/docgen",
  "solc-module":
    "/Users/alex/dev/mellow-permissionless-vaults/node_modules/solc/index.js",
  "solc-settings": { optimizer: { enabled: true, runs: 200 } },
  "output-structure": "contracts",
  extension: "md",
};

const fs = require("fs");
const path = require("path");

const excludeList = lines(EXCLUDE_FILE);

function lines(pathName) {
  return fs
    .readFileSync(pathName, { encoding: "utf8" })
    .split("\r")
    .join("")
    .split("\n");
}

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
docgen(flags).then(() => {
  let res = "";
  getAllFiles(docsDir).forEach((file) => {
    const data = fs.readFileSync(file);
    res += `${data}\n`;
  });

  fs.writeFileSync(path.resolve(path.join(docsDir, "api.md")), res);
});
