import { readFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const here = dirname(fileURLToPath(import.meta.url));
const dataDir = join(here, "..", "data");

async function readJson(name) {
  return JSON.parse(await readFile(join(dataDir, name), "utf8"));
}

const [master, masterSchema, recipes, recipeSchema, coverage, testCases, testSchema] =
  await Promise.all([
    readJson("ingredient-master-v1.json"),
    readJson("ingredient-master.schema.json"),
    readJson("recipe-seed-v1.json"),
    readJson("recipe-seed.schema.json"),
    readJson("priority-recipe-coverage-v1.json"),
    readJson("calculation-test-cases-v1.json"),
    readJson("calculation-test-cases.schema.json"),
  ]);

const errors = [];
const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const keyPattern = /^[a-z][a-z0-9_]*$/;
const masterByKey = new Map(master.ingredients.map((item) => [item.key, item]));
const recipeByKey = new Map(recipes.recipes.map((recipe) => [recipe.key, recipe]));
const coverageByKey = new Map(coverage.recipes.map((recipe) => [recipe.key, recipe]));
const recipeRequired = recipeSchema.$defs.recipe.required;
const recipeIngredientRequired = recipeSchema.$defs.recipeIngredient.required;
const recipeUnits = new Set(recipeSchema.$defs.unit.enum);
const masterUnits = new Set(masterSchema.$defs.unit.enum);

function sameSet(left, right) {
  if (left.size !== right.size) return false;
  return [...left].every((value) => right.has(value));
}

function closeEnough(left, right) {
  return Math.abs(left - right) < 1e-9;
}

function convert(quantity, sourceUnit, targetUnit) {
  if (sourceUnit === targetUnit) return { status: "converted", quantity };
  const conversions = new Map([
    ["kilogram:gram", 1000],
    ["gram:kilogram", 0.001],
    ["liter:milliliter", 1000],
    ["milliliter:liter", 0.001],
  ]);
  const factor = conversions.get(`${sourceUnit}:${targetUnit}`);
  if (factor === undefined) return { status: "unsupported" };
  return { status: "converted", quantity: quantity * factor };
}

function scaledIngredient(recipeKey, servings, ingredientKey) {
  const recipe = recipeByKey.get(recipeKey);
  if (!recipe) throw new Error(`unknown recipe ${recipeKey}`);
  const ingredient = recipe.ingredients.find((item) => item.ingredientKey === ingredientKey);
  if (!ingredient) throw new Error(`${recipeKey}: unknown ingredient ${ingredientKey}`);
  const factor = ingredient.scaling === "linear" ? servings / recipe.baseServings : 1;
  return { ...ingredient, scaledQuantity: ingredient.quantity * factor };
}

function evaluateAvailability(testCase) {
  const ingredient = scaledIngredient(
    testCase.recipeKey,
    testCase.servings,
    testCase.ingredientKey,
  );
  const thawing = ingredient.thawing;

  if (ingredient.inventoryMode === "ignored") return { status: "ignored", thawing };

  const validLots = testCase.lots.filter(
    (lot) => lot.expiresInDays === undefined || lot.expiresInDays === null || lot.expiresInDays >= 0,
  );

  if (ingredient.inventoryMode === "presence") {
    if (validLots.some((lot) => lot.roughState === "available" || (lot.quantity ?? 0) > 0)) {
      return { status: "available", thawing };
    }
    if (validLots.some((lot) => lot.roughState === "low")) {
      return { status: "confirmation", thawing };
    }
    return {
      status: ingredient.requirement === "optional" ? "optional_missing" : "shortage",
      thawing,
    };
  }

  const orderedLots = [...validLots].sort((left, right) => {
    const leftExpiry = left.expiresInDays ?? Number.POSITIVE_INFINITY;
    const rightExpiry = right.expiresInDays ?? Number.POSITIVE_INFINITY;
    return leftExpiry - rightExpiry || left.id.localeCompare(right.id);
  });
  let available = 0;
  let hasIncompatibleLot = false;
  const consumptionOrder = [];

  for (const lot of orderedLots) {
    if (typeof lot.quantity !== "number" || typeof lot.unit !== "string") continue;
    const converted = convert(lot.quantity, lot.unit, ingredient.unit);
    if (converted.status === "unsupported") {
      hasIncompatibleLot = true;
      continue;
    }
    if (available < ingredient.scaledQuantity) consumptionOrder.push(lot.id);
    available += converted.quantity;
  }

  const shortageQuantity = Math.max(0, ingredient.scaledQuantity - available);
  let status;
  if (shortageQuantity === 0) status = "available";
  else if (hasIncompatibleLot) status = "confirmation";
  else if (ingredient.requirement === "optional") status = "optional_missing";
  else status = "shortage";

  return {
    status,
    shortageQuantity: status === "optional_missing" ? 0 : shortageQuantity,
    unit: ingredient.unit,
    consumptionOrder,
    thawing,
  };
}

if (recipes.ingredientCatalogVersion !== master.catalogVersion) {
  errors.push("recipe ingredientCatalogVersion does not match IngredientMaster");
}
if (coverage.catalogVersion !== master.catalogVersion) {
  errors.push("coverage catalogVersion does not match IngredientMaster");
}
if (testCases.recipeCatalogVersion !== recipes.catalogVersion) {
  errors.push("test recipeCatalogVersion does not match recipe seed");
}
if (!sameSet(recipeUnits, masterUnits)) {
  errors.push("recipe and IngredientMaster unit enums differ");
}
if (testSchema.properties.availabilityCases === undefined) {
  errors.push("calculation test schema is missing availabilityCases");
}

const recipeIds = new Set();
const recipeKeys = new Set();

for (const [recipeIndex, recipe] of recipes.recipes.entries()) {
  const label = `recipes[${recipeIndex}] (${recipe.key ?? "no-key"})`;
  for (const field of recipeRequired) {
    if (!(field in recipe)) errors.push(`${label}: missing ${field}`);
  }
  if (!uuidPattern.test(recipe.id ?? "")) errors.push(`${label}: invalid UUID`);
  if (!keyPattern.test(recipe.key ?? "")) errors.push(`${label}: invalid key`);
  if (recipeIds.has(recipe.id)) errors.push(`${label}: duplicate id ${recipe.id}`);
  if (recipeKeys.has(recipe.key)) errors.push(`${label}: duplicate key ${recipe.key}`);
  recipeIds.add(recipe.id);
  recipeKeys.add(recipe.key);

  if (recipe.baseServings !== 1) errors.push(`${label}: baseServings must be 1`);
  if (!Number.isInteger(recipe.prepMinutes) || recipe.prepMinutes < 0) {
    errors.push(`${label}: invalid prepMinutes`);
  }
  if (!Number.isInteger(recipe.cookMinutes) || recipe.cookMinutes < 1) {
    errors.push(`${label}: invalid cookMinutes`);
  }
  if (recipe.imageRef !== `recipe/${recipe.key}`) {
    errors.push(`${label}: imageRef must match recipe key`);
  }

  const ingredientKeys = new Set();
  const derivedAllergens = new Set();
  for (const [ingredientIndex, ingredient] of recipe.ingredients.entries()) {
    const ingredientLabel = `${label}.ingredients[${ingredientIndex}]`;
    for (const field of recipeIngredientRequired) {
      if (!(field in ingredient)) errors.push(`${ingredientLabel}: missing ${field}`);
    }
    if (ingredientKeys.has(ingredient.ingredientKey)) {
      errors.push(`${ingredientLabel}: duplicate ingredient ${ingredient.ingredientKey}`);
    }
    ingredientKeys.add(ingredient.ingredientKey);

    const masterIngredient = masterByKey.get(ingredient.ingredientKey);
    if (!masterIngredient) {
      errors.push(`${ingredientLabel}: unknown ingredient key ${ingredient.ingredientKey}`);
      continue;
    }
    if (!recipeUnits.has(ingredient.unit)) errors.push(`${ingredientLabel}: unknown unit`);
    if (!masterIngredient.allowedUnits.includes(ingredient.unit)) {
      errors.push(`${ingredientLabel}: ${ingredient.unit} is not allowed for ${ingredient.ingredientKey}`);
    }
    const expectedInventoryMode = !masterIngredient.trackInventory
      ? "ignored"
      : masterIngredient.stockMode === "rough"
        ? "presence"
        : "exact";
    if (ingredient.inventoryMode !== expectedInventoryMode) {
      errors.push(
        `${ingredientLabel}: inventoryMode ${ingredient.inventoryMode}, expected ${expectedInventoryMode}`,
      );
    }
    for (const allergen of masterIngredient.allergens) derivedAllergens.add(allergen);
  }

  const coverageRecipe = coverageByKey.get(recipe.key);
  if (coverageRecipe && !sameSet(ingredientKeys, new Set(coverageRecipe.ingredientKeys))) {
    errors.push(`${label}: ingredient list differs from priority coverage`);
  }

  if (!sameSet(new Set(recipe.allergens), derivedAllergens)) {
    errors.push(`${label}: allergen list differs from IngredientMaster-derived list`);
  }

  const orders = recipe.steps.map((step) => step.order);
  const expectedOrders = recipe.steps.map((_, index) => index + 1);
  if (orders.some((order, index) => order !== expectedOrders[index])) {
    errors.push(`${label}: step order must be sequential from 1`);
  }
  for (const step of recipe.steps) {
    if (step.timerMinutes !== null && (!Number.isInteger(step.timerMinutes) || step.timerMinutes < 1)) {
      errors.push(`${label}: invalid timerMinutes at step ${step.order}`);
    }
  }
}

if (recipes.recipes.length < coverage.recipes.length) {
  errors.push(`recipe count ${recipes.recipes.length} is smaller than priority coverage`);
}
const mainRecipeCount = recipes.recipes.filter((recipe) => recipe.role === "main").length;
const sideRecipeCount = recipes.recipes.filter((recipe) => recipe.role === "side").length;
if (recipes.recipes.length !== 40) errors.push(`recipe count must be 40, got ${recipes.recipes.length}`);
if (mainRecipeCount !== 32) errors.push(`main recipe count must be 32, got ${mainRecipeCount}`);
if (sideRecipeCount !== 8) errors.push(`side recipe count must be 8, got ${sideRecipeCount}`);
for (const coverageKey of coverageByKey.keys()) {
  if (!recipeKeys.has(coverageKey)) errors.push(`priority coverage recipe is missing: ${coverageKey}`);
}

for (const testCase of testCases.unitConversions) {
  const actual = convert(testCase.sourceQuantity, testCase.sourceUnit, testCase.targetUnit);
  if (actual.status !== testCase.expectedStatus) {
    errors.push(`${testCase.id}: conversion status ${actual.status}, expected ${testCase.expectedStatus}`);
  }
  if (
    testCase.expectedStatus === "converted" &&
    !closeEnough(actual.quantity, testCase.expectedQuantity)
  ) {
    errors.push(`${testCase.id}: converted ${actual.quantity}, expected ${testCase.expectedQuantity}`);
  }
}

for (const testCase of testCases.scalingCases) {
  try {
    const ingredient = scaledIngredient(
      testCase.recipeKey,
      testCase.servings,
      testCase.ingredientKey,
    );
    if (!closeEnough(ingredient.scaledQuantity, testCase.expectedQuantity)) {
      errors.push(
        `${testCase.id}: scaled ${ingredient.scaledQuantity}, expected ${testCase.expectedQuantity}`,
      );
    }
    if (ingredient.unit !== testCase.expectedUnit) {
      errors.push(`${testCase.id}: unit ${ingredient.unit}, expected ${testCase.expectedUnit}`);
    }
  } catch (error) {
    errors.push(`${testCase.id}: ${error.message}`);
  }
}

for (const testCase of testCases.availabilityCases) {
  try {
    const actual = evaluateAvailability(testCase);
    for (const [field, expected] of Object.entries(testCase.expected)) {
      const value = actual[field];
      if (typeof expected === "number") {
        if (typeof value !== "number" || !closeEnough(value, expected)) {
          errors.push(`${testCase.id}: ${field} ${value}, expected ${expected}`);
        }
      } else if (Array.isArray(expected)) {
        if (JSON.stringify(value) !== JSON.stringify(expected)) {
          errors.push(
            `${testCase.id}: ${field} ${JSON.stringify(value)}, expected ${JSON.stringify(expected)}`,
          );
        }
      } else if (value !== expected) {
        errors.push(`${testCase.id}: ${field} ${value}, expected ${expected}`);
      }
    }
  } catch (error) {
    errors.push(`${testCase.id}: ${error.message}`);
  }
}

if (errors.length > 0) {
  for (const error of errors) console.error(`ERROR: ${error}`);
  process.exitCode = 1;
} else {
  const ingredientCount = recipes.recipes.reduce(
    (sum, recipe) => sum + recipe.ingredients.length,
    0,
  );
  const stepCount = recipes.recipes.reduce((sum, recipe) => sum + recipe.steps.length, 0);
  const testCount =
    testCases.unitConversions.length +
    testCases.scalingCases.length +
    testCases.availabilityCases.length;
  console.log(
    `OK: ${recipes.recipes.length} recipes (${mainRecipeCount} main, ${sideRecipeCount} side), ${ingredientCount} recipe ingredients, ${stepCount} steps, ${testCount} calculation tests`,
  );
}
