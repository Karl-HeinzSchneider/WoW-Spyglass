import { type Discovered } from "./discovered.js";
import { type ListFile, type CuratedListRow } from "./lists.js";
import { shipsRecipe } from "./recipes.js";
import { type Reference } from "./reference.js";

/** Apply an in-game trainer snapshot only when its service identifies one shipped recipe. */
export function importTrainers(
  discovered: Discovered,
  ref: Reference,
  lists: ListFile[],
  spellNames: Map<string, Map<number, string>>,
): string[] {
  const lines: string[] = [];
  const crafting = new Map(lists.filter((file) => file.kind === "crafting").map((file) => [file.data.skillLine, file]));
  const recipes = [...ref.recipes.values()].filter((recipe) => shipsRecipe(recipe, ref.items));
  const seenRanks = new Map<number, number>();
  let added = 0;
  let updated = 0;
  for (const trainer of discovered.trainers.values()) {
    if (trainer.build !== ref.build) {
      lines.push(
        `trainer ${trainer.name} (${trainer.id}): build ${trainer.build ?? "unknown"} differs from ${ref.build}; skipped`,
      );
      continue;
    }
    const localized = spellNames.get(trainer.locale === "enGB" ? "enUS" : trainer.locale);
    if (!localized) {
      lines.push(`trainer ${trainer.name} (${trainer.id}): no SpellName data for ${trainer.locale}; skipped`);
      continue;
    }
    const skillNames = ref.names.get(trainer.locale)?.skillLines ?? ref.names.get("enUS")?.skillLines;
    const skillLineByName = new Map([...(skillNames ?? [])].map(([id, name]) => [name, id]));
    for (const service of trainer.services.values()) {
      const skillLineID = service.skillName ? skillLineByName.get(service.skillName) : undefined;
      if (service.skillName && skillLineID === undefined) {
        lines.push(`trainer ${trainer.name}: unknown skill ${service.skillName} for ${service.name}; skipped`);
        continue;
      }
      const matches = recipes.filter(
        (recipe) =>
          localized.get(recipe.spellID) === service.name &&
          (skillLineID === undefined || recipe.skillLineID === skillLineID),
      );
      if (matches.length !== 1) {
        if (matches.length > 1) lines.push(`trainer ${trainer.name}: ${service.name} is ambiguous; skipped`);
        continue;
      }
      const recipe = matches[0]!;
      const file = crafting.get(recipe.skillLineID);
      if (!file) continue;
      const rows = (file.data.recipes ??= []);
      const bySpell = rows.find((row) => row.spell === recipe.spellID);
      const byItem = recipe.itemID > 0 ? rows.find((row) => row.item === recipe.itemID) : undefined;
      if (byItem && byItem.spell !== undefined && byItem.spell !== recipe.spellID && !bySpell) {
        lines.push(`trainer ${trainer.name}: ${service.name} conflicts with an existing item row; skipped`);
        continue;
      }
      let row: CuratedListRow = bySpell ?? byItem ?? { spell: recipe.spellID };
      if (!bySpell && !byItem) {
        if (recipe.itemID > 0) row.item = recipe.itemID;
        rows.push(row);
        added++;
      } else {
        updated++;
      }
      row.spell = recipe.spellID;
      if (service.skillRank && service.skillRank > 0) {
        const earlier = seenRanks.get(recipe.spellID);
        if (earlier !== undefined && earlier !== service.skillRank) {
          lines.push(
            `trainer ${trainer.name}: ${service.name} has skill ${service.skillRank}, earlier scan has ${earlier}; kept earlier`,
          );
        } else {
          seenRanks.set(recipe.spellID, service.skillRank);
          row.skill = service.skillRank;
        }
      }
      if (!row.source) row.source = "Trainer";
      else if (!row.source.includes("Trainer")) row.source += "; Trainer";
    }
  }
  if (added || updated) lines.unshift(`trainer recipes: ${added} new, ${updated} updated`);
  return lines;
}
