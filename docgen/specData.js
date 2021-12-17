const fs = require("fs");
const path = require("path");
const { start } = require("repl");

const root = path.resolve(path.join(__dirname, ".."));
const specsFileName = path.resolve(path.join(root, "spec.json"));
const specsRawData = fs.readFileSync(specsFileName).toString();
const lines = specsRawData.split("\n");
const jsonData = [];
let skip = true;
for (const line of lines) {
  if (line == "{") {
    skip = false;
  }
  if (skip) {
    continue;
  }
  if (line.startsWith("}Done")) {
    jsonData.push("}");
    break;
  }
  jsonData.push(line);
}
const data = JSON.parse(jsonData.join("\n"));

function getRawMethodSpecs(contract, method) {
  const res = [];
  const prefix = `${contract} #${method}`;
  for (const { fullTitle } of data.tests) {
    if (!fullTitle.startsWith(prefix)) {
      continue;
    }
    res.push(fullTitle.slice(prefix.length + 1));
  }
  return res;
}

function consumePrefix(prefix, data) {
  const res = [];
  const rest = [];
  for (const item of data) {
    if (!item.startsWith(prefix)) {
      rest.push(item);
      continue;
    }
    res.push(item.slice(prefix.length));
  }
  return { res, rest };
}

function getMethodSpecs(contract, method) {
  const rawSpecs = getRawMethodSpecs(contract, method);
  let propertySpecs, accessControlSpecs, edgeCasesSpecs, rest;
  ({ res: propertySpecs, rest } = consumePrefix(
    "properties @property: ",
    rawSpecs
  ));
  ({ res: accessControlSpecs, rest } = consumePrefix("access control ", rest));
  ({ res: edgeCasesSpecs, rest } = consumePrefix("edge cases ", rest));
  return {
    general: rest,
    properties: propertySpecs,
    accessControl: accessControlSpecs,
    edgeCases: edgeCasesSpecs,
  };
}

function generateSpecContents(contract, method) {
  const specData = getMethodSpecs(contract, method);
  if (!specData || specData.general.length == 0) {
    return undefined;
  }
  let res = "";
  for (const item of specData.general) {
    res += `- ✅ ${item}\n`;
  }
  res += "\n";
  if (specData.accessControl.length > 0) {
    res += "*Access control*\n";
    for (const item of specData.accessControl) {
      res += `- ✅ ${item}\n`;
    }
    res += "\n";
  }
  if (specData.properties.length > 0) {
    res += "*Properties*\n";
    for (const item of specData.properties) {
      res += `- ✅ ${item}\n`;
    }
    res += "\n";
  }
  if (specData.edgeCases.length > 0) {
    res += "*Edge cases*\n";
    for (const item of specData.edgeCases) {
      res += `- ✅ ${item}\n`;
    }
    res += "\n";
  }
  return res;
}

module.exports = {
  generateSpecContents,
};
