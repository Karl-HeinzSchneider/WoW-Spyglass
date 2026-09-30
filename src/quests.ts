import { readdirSync, readFileSync } from "node:fs";
import { basename, resolve } from "node:path";
import { DUNGEON_QUESTS_DIR } from "./config.js";
import { type Checker, type CuratedFile, type CuratedItemRow } from "./curated.js";

/** A quest giver or turn-in. Coordinates use the same [uiMapID, x, y] format as dungeon entrances. */
export interface QuestEndpoint {
  npc?: string;
  npcID?: number;
  item?: number;
  location?: [number, number, number];
  description?: string;
}

/** Shared details for an NPC within one dungeon quest file. */
export type QuestNpcDetails = Pick<QuestEndpoint, "location" | "description">;

/** One quest definition, shared by every dungeon that lists its id. */
export interface CuratedQuest {
  id?: number;
  name?: string;
  side?: string;
  class?: string;
  requiredLevel?: number;
  xp?: number;
  objective?: string;
  description?: string;
  /** Direct prerequisite quest ids; each has its own definition in the quest catalog. */
  requires?: number[];
  /** Follow-up quest ids in the order they should appear after this quest. */
  followUps?: number[];
  start?: QuestEndpoint;
  turnIn?: QuestEndpoint;
  items: CuratedItemRow[];
}

export interface QuestFile {
  path: string;
  slug: string;
  npcs?: Record<string, QuestNpcDetails>;
  quests: CuratedQuest[];
}

export const QUEST_SIDES = ["Alliance", "Horde", "Both"];
export const QUEST_CLASSES = ["Warrior", "Paladin", "Hunter", "Rogue", "Priest", "Shaman", "Mage", "Warlock", "Druid"];

/** "Warlock" -> "WARLOCK", the client's class token. */
export function classToken(name: string): string {
  return name.toUpperCase().replace(/ /g, "");
}

export function loadQuests(): QuestFile[] {
  let entries: string[];
  try {
    entries = readdirSync(DUNGEON_QUESTS_DIR)
      .filter((entry) => entry.endsWith(".json"))
      .sort();
  } catch {
    return [];
  }
  return entries.map((entry) => {
    const path = resolve(DUNGEON_QUESTS_DIR, entry);
    const data = JSON.parse(readFileSync(path, "utf-8")) as {
      npcs?: Record<string, QuestNpcDetails>;
      quests: CuratedQuest[];
    };
    return { path, slug: basename(entry, ".json"), npcs: data.npcs, quests: data.quests };
  });
}

/** Quest definitions are unique; instance and boss files refer to them by id. */
export function validateQuests(files: QuestFile[], instances: CuratedFile[], checker: Checker): void {
  const byID = new Map<number, QuestFile>();
  for (const file of files) {
    if (file.npcs !== undefined) {
      if (!file.npcs || typeof file.npcs !== "object" || Array.isArray(file.npcs)) {
        checker.report(file, "`npcs` must be an object keyed by NPC name");
      } else {
        for (const [name, details] of Object.entries(file.npcs)) {
          if (!name.trim()) checker.report(file, "`npcs` cannot have an empty NPC name");
          if (!details || typeof details !== "object" || Array.isArray(details)) {
            checker.report(file, `NPC "${name}": details must be an object`);
            continue;
          }
          for (const key of Object.keys(details)) {
            if (key !== "location" && key !== "description")
              checker.report(file, `NPC "${name}": unknown field ${key}`);
          }
          if (
            details.description !== undefined &&
            (typeof details.description !== "string" || details.description === "")
          ) {
            checker.report(file, `NPC "${name}": \`description\` must be a non-empty string`);
          }
          if (details.location !== undefined && !validLocation(details.location)) {
            checker.report(file, `NPC "${name}": \`location\` must be [uiMapID, x, y] with x/y in 0..100`);
          }
        }
      }
    }
    if (!Array.isArray(file.quests)) {
      checker.report(file, "`quests` must be an array");
      continue;
    }
    for (const quest of file.quests) {
      if (!quest || typeof quest !== "object" || Array.isArray(quest)) {
        checker.report(file, "quest definition must be an object");
        continue;
      }
      if (quest.id === undefined) {
        checker.warn(file, `quest "${quest.name ?? "?"}": no \`id\`; it isn't shipped until it has one`);
        continue;
      }
      if (!Number.isInteger(quest.id) || quest.id <= 0) {
        checker.report(file, "quest without a positive integer `id`");
        continue;
      }
      if (byID.has(quest.id)) checker.report(file, `quest ${quest.id} is also defined in ${byID.get(quest.id)!.path}`);
      byID.set(quest.id, file);
      if (quest.name === undefined || quest.name === "") {
        checker.warn(file, `quest ${quest.id}: no \`name\`; the browser can only show its id`);
      }
      if (quest.side !== undefined && !QUEST_SIDES.includes(quest.side)) {
        checker.report(file, `quest ${quest.id}: \`side\` must be one of ${QUEST_SIDES.join(", ")}`);
      }
      if (quest.class !== undefined && !QUEST_CLASSES.includes(quest.class)) {
        checker.report(file, `quest ${quest.id}: \`class\` must be one of ${QUEST_CLASSES.join(", ")}`);
      }
      if (quest.requiredLevel !== undefined && (!Number.isInteger(quest.requiredLevel) || quest.requiredLevel < 1)) {
        checker.report(file, `quest ${quest.id}: \`requiredLevel\` must be a level (an integer from 1)`);
      }
      if (quest.xp !== undefined && (!Number.isInteger(quest.xp) || quest.xp < 0)) {
        checker.report(file, `quest ${quest.id}: \`xp\` must be a non-negative integer`);
      }
      for (const field of ["objective", "description"] as const) {
        if (quest[field] !== undefined && (typeof quest[field] !== "string" || quest[field] === "")) {
          checker.report(file, `quest ${quest.id}: \`${field}\` must be a non-empty string`);
        }
      }
      for (const field of ["start", "turnIn"] as const) {
        if (quest[field] !== undefined) validateEndpoint(file, quest.id, field, quest[field], checker);
      }
      for (const [field, label] of [["requires", "prerequisite"], ["followUps", "follow-up"]] as const) {
        const ids = quest[field];
        if (ids === undefined) continue;
        if (!Array.isArray(ids)) checker.report(file, `quest ${quest.id}: \`${field}\` must be an array`);
        else {
          const seen = new Set<number>();
          for (const id of ids) {
            if (!Number.isInteger(id) || id <= 0 || id === quest.id || seen.has(id)) {
              checker.report(file, `quest ${quest.id}: invalid or repeated ${label} ${id}`);
            }
            seen.add(id);
          }
        }
      }
      if (!Array.isArray(quest.items)) {
        checker.report(file, `quest ${quest.id}: \`items\` must be an array`, true);
        if (checker.fix) quest.items = [];
        else continue;
      }
      const seenItems = new Set<number>();
      for (const row of quest.items) checker.checkItemRow(file, `quest ${quest.id}`, row, seenItems);
    }
  }

  for (const file of files) {
    if (!Array.isArray(file.quests)) continue;
    for (const quest of file.quests) {
      if (!quest || typeof quest !== "object" || Array.isArray(quest)) continue;
      for (const [field, label] of [["requires", "prerequisite"], ["followUps", "follow-up"]] as const) {
        if (!Array.isArray(quest[field])) continue;
        for (const id of quest[field]) {
          if (Number.isInteger(id) && id > 0 && !byID.has(id)) {
            checker.report(file, `quest ${quest.id ?? "?"}: ${label} ${id} has no quest definition`);
          }
        }
      }
    }
  }
  for (const file of instances) {
    if (file.data.quests === undefined) continue;
    if (!Array.isArray(file.data.quests)) {
      checker.report(file, "`quests` must be an array of quest ids");
      continue;
    }
    const seen = new Set<number>();
    for (const id of file.data.quests) {
      if (!Number.isInteger(id) || id <= 0) checker.report(file, "quest reference must be a positive integer id");
      else if (!byID.has(id)) checker.report(file, `quest ${id} has no definition under data/quests/dungeons/`);
      if (seen.has(id)) checker.report(file, `quest ${id} listed twice`);
      seen.add(id);
    }
  }
}

function validateEndpoint(
  file: QuestFile,
  questID: number,
  field: "start" | "turnIn",
  endpoint: QuestEndpoint,
  checker: Checker,
): void {
  if (!endpoint || typeof endpoint !== "object" || Array.isArray(endpoint)) {
    checker.report(file, `quest ${questID}: \`${field}\` must be an object`);
    return;
  }
  if (endpoint.npc !== undefined && (typeof endpoint.npc !== "string" || endpoint.npc === "")) {
    checker.report(file, `quest ${questID}: \`${field}.npc\` must be a non-empty name`);
  }
  if (endpoint.description !== undefined && (typeof endpoint.description !== "string" || endpoint.description === "")) {
    checker.report(file, `quest ${questID}: \`${field}.description\` must be a non-empty string`);
  }
  for (const key of ["npcID", "item"] as const) {
    if (endpoint[key] !== undefined && (!Number.isInteger(endpoint[key]) || endpoint[key]! <= 0)) {
      checker.report(file, `quest ${questID}: \`${field}.${key}\` must be a positive integer`);
    }
  }
  if (endpoint.location !== undefined) {
    if (!validLocation(endpoint.location)) {
      checker.report(file, `quest ${questID}: \`${field}.location\` must be [uiMapID, x, y] with x/y in 0..100`);
    }
  }
}

function validLocation(loc: unknown): loc is [number, number, number] {
  return (
    Array.isArray(loc) &&
    loc.length === 3 &&
    Number.isInteger(loc[0]) &&
    loc[0] > 0 &&
    Number.isFinite(loc[1]) &&
    loc[1] >= 0 &&
    loc[1] <= 100 &&
    Number.isFinite(loc[2]) &&
    loc[2] >= 0 &&
    loc[2] <= 100
  );
}

/** Stable field order for human-edited files and minimal `fix` diffs. */
export function serializeQuests(file: QuestFile): string {
  return (
    JSON.stringify(
      {
        npcs:
          file.npcs &&
          Object.fromEntries(
            Object.entries(file.npcs).map(([name, details]) => [
              name,
              { location: details.location, description: details.description },
            ]),
          ),
        quests: file.quests.map((q) => ({
          id: q.id,
          name: q.name,
          side: q.side,
          class: q.class,
          requiredLevel: q.requiredLevel,
          xp: q.xp,
          objective: q.objective,
          description: q.description,
          requires: q.requires,
          followUps: q.followUps,
          start: q.start && {
            npc: q.start.npc,
            npcID: q.start.npcID,
            item: q.start.item,
            location: q.start.location,
            description: q.start.description,
          },
          turnIn: q.turnIn && {
            npc: q.turnIn.npc,
            npcID: q.turnIn.npcID,
            item: q.turnIn.item,
            location: q.turnIn.location,
            description: q.turnIn.description,
          },
          items: (q.items ?? []).map((r) => ({ item: r.item, name: r.name })),
        })),
      },
      null,
      2,
    ) + "\n"
  );
}
