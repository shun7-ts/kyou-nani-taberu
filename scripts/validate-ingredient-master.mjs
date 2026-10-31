import { readFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const here = dirname(fileURLToPath(import.meta.url));
const dataDir = join(here, "..", "data");
const masterPath = join(dataDir, "ingredient-master-v1.json");
const schemaPath = join(dataDir, "ingredient-master.schema.json");
const coveragePath = join(dataDir, "priority-recipe-coverage-v1.json");

const [master, schema, coverage] = await Promise.all(
  [masterPath, schemaPath, coveragePath].map(async (path) =>
    JSON.parse(await readFile(path, "utf8")),
  ),
);

const errors = [];
const warnings = [];
const required = schema.$defs.ingredient.required;
const unitSet = new Set(schema.$defs.unit.enum);
const categorySet = new Set(schema.$defs.ingredient.properties.category.enum);
const storageSet = new Set(schema.$defs.ingredient.properties.defaultStorage.enum);
const stockModeSet = new Set(schema.$defs.ingredient.properties.stockMode.enum);
const statusSet = new Set(schema.$defs.ingredient.properties.status.enum);
const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const keyPattern = /^[a-z][a-z0-9_]*$/;

if (master.schemaVersion !== 1) errors.push("schemaVersion must be 1");
if (master.locale !== "ja-JP") errors.push("locale must be ja-JP");
if (!Array.isArray(master.ingredients) || master.ingredients.length === 0) {
  errors.push("ingredients must be a non-empty array");
}

const ids = new Set();
const keys = new Set();
const canonicalNames = new Set();
const recognizedNames = new Map();

for (const [index, ingredient] of master.ingredients.entries()) {
  const label = `ingredients[${index}] (${ingredient.key ?? "no-key"})`;

  for (const field of required) {
    if (!(field in ingredient)) errors.push(`${label}: missing ${field}`);
  }
  if (!uuidPattern.test(ingredient.id ?? "")) errors.push(`${label}: invalid UUID`);
  if (!keyPattern.test(ingredient.key ?? "")) errors.push(`${label}: invalid key`);

  if (ids.has(ingredient.id)) errors.push(`${label}: duplicate id ${ingredient.id}`);
  ids.add(ingredient.id);
  if (keys.has(ingredient.key)) errors.push(`${label}: duplicate key ${ingredient.key}`);
  keys.add(ingredient.key);
  if (canonicalNames.has(ingredient.canonicalName)) {
    errors.push(`${label}: duplicate canonicalName ${ingredient.canonicalName}`);
  }
  canonicalNames.add(ingredient.canonicalName);

  if (!categorySet.has(ingredient.category)) errors.push(`${label}: invalid category`);
  if (!unitSet.has(ingredient.defaultUnit)) errors.push(`${label}: invalid defaultUnit`);
  if (!Array.isArray(ingredient.allowedUnits) || ingredient.allowedUnits.length === 0) {
    errors.push(`${label}: allowedUnits must not be empty`);
  } else {
    for (const unit of ingredient.allowedUnits) {
      if (!unitSet.has(unit)) errors.push(`${label}: invalid allowed unit ${unit}`);
    }
    if (!ingredient.allowedUnits.includes(ingredient.defaultUnit)) {
      errors.push(`${label}: defaultUnit must be included in allowedUnits`);
    }
    if (new Set(ingredient.allowedUnits).size !== ingredient.allowedUnits.length) {
      errors.push(`${label}: duplicate allowedUnits`);
    }
  }
  if (!storageSet.has(ingredient.defaultStorage)) errors.push(`${label}: invalid storage`);
  if (!stockModeSet.has(ingredient.stockMode)) errors.push(`${label}: invalid stockMode`);
  if (!statusSet.has(ingredient.status)) errors.push(`${label}: invalid status`);
  if (typeof ingredient.trackInventory !== "boolean") errors.push(`${label}: invalid trackInventory`);
  if (typeof ingredient.shoppingEligible !== "boolean") errors.push(`${label}: invalid shoppingEligible`);
  if (!ingredient.trackInventory && ingredient.shoppingEligible) {
    errors.push(`${label}: untracked item cannot be shoppingEligible`);
  }
  if (!Array.isArray(ingredient.aliases)) errors.push(`${label}: aliases must be an array`);
  if (!Array.isArray(ingredient.allergens)) errors.push(`${label}: allergens must be an array`);

  for (const name of [ingredient.canonicalName, ...(ingredient.aliases ?? [])]) {
    const normalized = name.normalize("NFKC").trim().toLocaleLowerCase("ja-JP");
    const owner = recognizedNames.get(normalized);
    if (owner && owner !== ingredient.key) {
      warnings.push(`recognition name collision: "${name}" -> ${owner}, ${ingredient.key}`);
    } else {
      recognizedNames.set(normalized, ingredient.key);
    }
  }
}

if (coverage.catalogVersion !== master.catalogVersion) {
  errors.push("coverage catalogVersion does not match ingredient master");
}

const recipeKeys = new Set();
for (const recipe of coverage.recipes ?? []) {
  if (recipeKeys.has(recipe.key)) errors.push(`duplicate recipe key: ${recipe.key}`);
  recipeKeys.add(recipe.key);
  for (const ingredientKey of recipe.ingredientKeys ?? []) {
    if (!keys.has(ingredientKey)) {
      errors.push(`${recipe.title}: unknown ingredient key ${ingredientKey}`);
    }
  }
}

if ((coverage.recipes ?? []).length !== 12) {
  errors.push(`priority recipe count must be 12, got ${(coverage.recipes ?? []).length}`);
}

for (const warning of warnings) console.warn(`WARN: ${warning}`);
if (errors.length > 0) {
  for (const error of errors) console.error(`ERROR: ${error}`);
  process.exitCode = 1;
} else {
  console.log(
    `OK: ${master.ingredients.length} ingredients, ${coverage.recipes.length} priority recipes, ${recognizedNames.size} recognition names`,
  );
}
