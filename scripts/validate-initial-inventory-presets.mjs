import { readFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const here = dirname(fileURLToPath(import.meta.url));
const dataDir = join(here, "..", "data");
const readJson = async (name) => JSON.parse(await readFile(join(dataDir, name), "utf8"));
const [master, presets, schema] = await Promise.all([
  readJson("ingredient-master-v1.json"),
  readJson("initial-inventory-presets-v1.json"),
  readJson("initial-inventory-presets.schema.json"),
]);

const errors = [];
const masterByKey = new Map(master.ingredients.map((item) => [item.key, item]));
const sectionIds = new Set();
const ingredientKeys = new Set();

if (presets.ingredientCatalogVersion !== master.catalogVersion) {
  errors.push("ingredientCatalogVersion does not match IngredientMaster");
}
if (schema.properties.sections === undefined) errors.push("preset schema is missing sections");

for (const [sectionIndex, section] of presets.sections.entries()) {
  if (sectionIds.has(section.id)) errors.push(`duplicate section id ${section.id}`);
  sectionIds.add(section.id);
  if (section.order !== sectionIndex + 1) errors.push(`${section.id}: order is not sequential`);
  if (section.groupSelectionEnabled && section.id !== "basic_seasonings") {
    errors.push(`${section.id}: only basic_seasonings may enable group selection in v1`);
  }
  for (const item of section.items) {
    if (ingredientKeys.has(item.ingredientKey)) {
      errors.push(`duplicate preset ingredient ${item.ingredientKey}`);
    }
    ingredientKeys.add(item.ingredientKey);
    const masterItem = masterByKey.get(item.ingredientKey);
    if (!masterItem) {
      errors.push(`${section.id}: unknown ingredient ${item.ingredientKey}`);
      continue;
    }
    if (masterItem.status !== "active") errors.push(`${item.ingredientKey}: master item is not active`);
    const recognizedNames = new Set([masterItem.canonicalName, ...masterItem.aliases]);
    if (!recognizedNames.has(item.label)) {
      errors.push(`${item.ingredientKey}: label "${item.label}" is not a canonical name or alias`);
    }
    if (item.initialInventoryMode !== "rough" || item.roughState !== "available") {
      errors.push(`${item.ingredientKey}: initial setup must create rough available stock`);
    }
  }
}

if (ingredientKeys.size !== 32) errors.push(`preset item count must be 32, got ${ingredientKeys.size}`);

if (errors.length > 0) {
  for (const error of errors) console.error(`ERROR: ${error}`);
  process.exitCode = 1;
} else {
  console.log(`OK: ${presets.sections.length} sections, ${ingredientKeys.size} mapped preset items`);
}
