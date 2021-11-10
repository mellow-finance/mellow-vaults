const { registerHelpers } = require("solidity-docgen/dist/handlebars.js");

function inheritanceDescription(inheritance, options) {
  const filtered = inheritance.slice(1).filter((x) => !x.name.startsWith("I"));

  if (filtered.length == 0) {
    return "";
  }
  const desc = filtered
    .map((x) => `[${x.name}](#${x.name.toLowerCase()})`)
    .join(", ");
  return `*Inherits from ${desc}*\n`;
}

function shouldHaveSections(functions, events, structs, options) {
  return +!!functions.length + +!!events.length + +!!structs.length >= 2
    ? options.fn(this)
    : options.inverse(this);
}

function structType(t, options) {
  return t.replace("contract ", "");
}

registerHelpers({ inheritanceDescription, shouldHaveSections, structType });
