const fs = require("fs");
const path = require("path");

const root = path.resolve(path.join(__dirname, ".."));
const gasFileName = path.resolve(path.join(root, "gas.txt"));
const gasRawData = fs.readFileSync(gasFileName).toString();
const lines = gasRawData.split("\n");
let filtered = [];
for (let i = 0; i < lines.length; i++) {
  if (i % 2 == 1 && i > 6) {
    let line = lines[i]
      .slice(1)
      .split("·")
      .map((x) => x.trim());
    filtered.push(line);
  }
}

function getGasData(contract, method) {
  for (const chunks of filtered) {
    if (method && chunks[0] === contract && chunks[1] === method) {
      const data = {
        avg: parseInt(chunks[4]),
        min: chunks[2] != "-" ? parseInt(chunks[2]) : undefined,
        max: chunks[3] != "-" ? parseInt(chunks[3]) : undefined,
      };
      if (!data["min"]) {
        delete data["min"];
      }
      if (!data["max"]) {
        delete data["max"];
      }
      return data;
    } else if (
      !method &&
      chunks[0] === contract &&
      (chunks[1] === "-" || !isNaN(parseInt(chunks[1])))
    ) {
      const data = {
        avg: parseInt(chunks[3]),
        min:
          method == "-"
            ? undefined
            : chunks[1] != "-"
            ? parseInt(chunks[1])
            : undefined,
        max:
          method == "-"
            ? undefined
            : chunks[2] != "-"
            ? parseInt(chunks[2])
            : undefined,
      };
      if (!data["min"]) {
        delete data["min"];
      }
      if (!data["max"]) {
        delete data["max"];
      }
      return data;
    }
  }
  return {};
}

module.exports = {
  getGasData,
};
