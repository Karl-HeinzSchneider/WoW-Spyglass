import { existsSync, readdirSync, readFileSync } from "node:fs";
import { basename, resolve } from "node:path";
import { QUESTS_DIR } from "./config.js";
import { type Checker, type CuratedFile, type CuratedItemRow, type QuestRole } from "./curated.js";

/** One manually curated quest giver or turn-in contact. The map point is optional. */
export interface CuratedQuestContact {
  npc?: number;
  name?: string;
  /** [uiMapID, x, y], with x and y in 0..100. */
  map?: [number, number, number];
}

/** A reusable quest definition. Instance and list data refer to it by id. */
export interface CuratedQuest {
  /** Quest id. An unfinished definition without one is warned about and not shipped. */
  id?: number;
  /** English fallback title; the client title wins when it knows one. */
  name?: string;
  side?: string;
  /** Human class name in source data ("Warlock"); generated as the client token ("WARLOCK"). */
  class?: string;
  requiredLevel?: number;
  xp?: number;
  objective?: string;
  /** Direct prerequisites which must all be complete. */
  requires?: number[];
  /** Alternative direct prerequisites; at least one is sufficient. */
  requiresAny?: number[];
  /** Optional lead-in quests which point here but are not required. */
  breadcrumbs?: number[];
  start?: CuratedQuestContact;
  finish?: CuratedQuestContact;
  items: CuratedItemRow[];
}

export interface QuestFile {
  path: string;
  slug: string;
  data: { quests: CuratedQuest[] };
}

export const QUEST_SIDES = ["Alliance", "Horde", "Both"];
export const QUEST_CLASSES = ["Warrior", "Paladin", "Hunter", "Rogue", "Priest", "Shaman", "Mage", "Warlock", "Druid"];
export const QUEST_ROLES: QuestRole[] = ["inside", "lead-in", "turn-in", "spans"];

/** "Warlock" -> "WARLOCK", the client's class token. */
export function classToken(name: string): string {
  return name.toUpperCase().replace(/ /g, "");
}

export function loadQuests(): QuestFile[] {
  if (!existsSync(QUESTS_DIR)) return [];
  return readdirSync(QUESTS_DIR)
    .filter((entry) => entry.endsWith(".json"))
    .sort()
    .map((entry) => {
      const path = resolve(QUESTS_DIR, entry);
      return {
        path,
        slug: basename(entry, ".json"),
        data: JSON.parse(readFileSync(path, "utf-8")) as QuestFile["data"],
      };
    });
}

export function questDefinitions(files: QuestFile[]): Map<number, CuratedQuest> {
  const definitions = new Map<number, CuratedQuest>();
  for (const file of files) {
    for (const quest of file.data.quests ?? []) {
      if (quest.id !== undefined && !definitions.has(quest.id)) definitions.set(quest.id, quest);
    }
  }
  return definitions;
}

function validPoint(value: unknown): value is [number, number, number] {
  if (!Array.isArray(value) || value.length !== 3) return false;
  const [mapID, x, y] = value;
  return (
    Number.isInteger(mapID) &&
    mapID > 0 &&
    typeof x === "number" &&
    x >= 0 &&
    x <= 100 &&
    typeof y === "number" &&
    y >= 0 &&
    y <= 100
  );
}

function validateContact(
  file: QuestFile,
  questID: number,
  kind: "start" | "finish",
  contact: CuratedQuestContact | undefined,
  checker: Checker,
): void {
  if (contact === undefined) return;
  if (!contact || typeof contact !== "object" || Array.isArray(contact)) {
    checker.report(file, `quest ${questID}: \`${kind}\` must be an object`);
    return;
  }
  if (contact.npc !== undefined && (!Number.isInteger(contact.npc) || contact.npc <= 0)) {
    checker.report(file, `quest ${questID}: \`${kind}.npc\` must be a positive integer`);
  }
  if (contact.name !== undefined && (typeof contact.name !== "string" || contact.name === "")) {
    checker.report(file, `quest ${questID}: \`${kind}.name\` must be a non-empty string`);
  }
  if (contact.map !== undefined && !validPoint(contact.map)) {
    checker.report(file, `quest ${questID}: \`${kind}.map\` must be [uiMapID, x, y] with x and y in 0..100`);
  }
  if (contact.npc === undefined && contact.name === undefined && contact.map === undefined) {
    checker.report(file, `quest ${questID}: \`${kind}\` is empty`);
  }
}

/** Validates global definitions, graph edges, and every instance/boss reference. */
export function validateQuests(files: QuestFile[], instances: CuratedFile[], checker: Checker): void {
  const byID = new Map<number, { quest: CuratedQuest; file: QuestFile }>();
  for (const file of files) {
    if (!file.data || !Array.isArray(file.data.quests)) {
      checker.report(file, "`quests` must be an array");
      continue;
    }
    for (const quest of file.data.quests) {
      if (quest.id === undefined) {
        checker.warn(file, `quest "${quest.name ?? "?"}": no \`id\`; it isn't shipped until it has one`);
        continue;
      }
      if (!Number.isInteger(quest.id) || quest.id <= 0) {
        checker.report(file, "quest without a positive integer `id`");
        continue;
      }
      const previous = byID.get(quest.id);
      if (previous) checker.report(file, `quest ${quest.id} is also defined in ${previous.file.path}`);
      else byID.set(quest.id, { quest, file });

      if (quest.name === undefined || quest.name === "")
        checker.warn(file, `quest ${quest.id}: no \`name\`; the browser can only show its id`);
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
      if (quest.objective !== undefined && (typeof quest.objective !== "string" || quest.objective === "")) {
        checker.report(file, `quest ${quest.id}: \`objective\` must be a non-empty string`);
      }
      if (!Array.isArray(quest.items)) {
        checker.report(file, `quest ${quest.id}: \`items\` must be an array`, true);
        if (checker.fix) quest.items = [];
      } else {
        const seenItems = new Set<number>();
        for (const row of quest.items) checker.checkItemRow(file, `quest ${quest.id}`, row, seenItems);
      }
      validateContact(file, quest.id, "start", quest.start, checker);
      validateContact(file, quest.id, "finish", quest.finish, checker);
    }
  }

  const edges = (quest: CuratedQuest): number[] => [
    ...(Array.isArray(quest.requires) ? quest.requires : []),
    ...(Array.isArray(quest.requiresAny) ? quest.requiresAny : []),
    ...(Array.isArray(quest.breadcrumbs) ? quest.breadcrumbs : []),
  ];
  for (const [id, { quest, file }] of byID) {
    const seen = new Set<number>();
    for (const [field, ids] of [
      ["requires", quest.requires],
      ["requiresAny", quest.requiresAny],
      ["breadcrumbs", quest.breadcrumbs],
    ] as const) {
      if (ids === undefined) continue;
      if (!Array.isArray(ids)) {
        checker.report(file, `quest ${id}: \`${field}\` must be an array of quest ids`);
        continue;
      }
      for (const required of ids) {
        if (!Number.isInteger(required) || required <= 0)
          checker.report(file, `quest ${id}: \`${field}\` contains an invalid quest id`);
        else if (required === id) checker.report(file, `quest ${id} cannot require itself`);
        else if (seen.has(required)) checker.report(file, `quest ${id}: prerequisite ${required} is listed twice`);
        else if (!byID.has(required)) checker.report(file, `quest ${id}: prerequisite ${required} has no definition`);
        seen.add(required);
      }
    }
  }

  const visiting = new Set<number>();
  const visited = new Set<number>();
  const visit = (id: number, path: number[]): void => {
    if (visiting.has(id)) {
      const owner = byID.get(id);
      if (owner) checker.report(owner.file, `quest relationship cycle: ${[...path, id].join(" -> ")}`);
      return;
    }
    if (visited.has(id)) return;
    visiting.add(id);
    const quest = byID.get(id)?.quest;
    if (quest) for (const required of edges(quest)) if (byID.has(required)) visit(required, [...path, id]);
    visiting.delete(id);
    visited.add(id);
  };
  for (const id of byID.keys()) visit(id, []);

  for (const instance of instances) {
    const seen = new Set<number>();
    if (instance.data.quests !== undefined && !Array.isArray(instance.data.quests)) {
      checker.report(instance, "`quests` must be an array");
      continue;
    }
    for (const association of instance.data.quests ?? []) {
      if (!association || typeof association !== "object" || !Number.isInteger(association.id) || association.id <= 0) {
        checker.report(instance, "quest reference without a positive integer `id`");
        continue;
      }
      if (seen.has(association.id)) checker.report(instance, `quest ${association.id} listed twice`);
      seen.add(association.id);
      if (!byID.has(association.id))
        checker.report(instance, `quest ${association.id} has no definition in .contribute/data/quests`);
      if (association.role !== undefined && !QUEST_ROLES.includes(association.role)) {
        checker.report(instance, `quest ${association.id}: \`role\` must be one of ${QUEST_ROLES.join(", ")}`);
      }
    }
    for (const encounter of instance.data.encounters) {
      for (const questID of encounter.quests ?? []) {
        if (!byID.has(questID))
          checker.report(instance, `encounter ${encounter.id}: quest ${questID} has no definition`);
      }
    }
  }
}

export function serializeQuestFile(file: QuestFile): string {
  const quests = file.data.quests.map((quest) => ({
    id: quest.id,
    name: quest.name,
    side: quest.side,
    class: quest.class,
    requiredLevel: quest.requiredLevel,
    xp: quest.xp,
    objective: quest.objective,
    requires: quest.requires,
    requiresAny: quest.requiresAny,
    breadcrumbs: quest.breadcrumbs,
    start: quest.start && { npc: quest.start.npc, name: quest.start.name, map: quest.start.map },
    finish: quest.finish && { npc: quest.finish.npc, name: quest.finish.name, map: quest.finish.map },
    items: (quest.items ?? []).map((row) => ({ item: row.item, name: row.name })),
  }));
  return JSON.stringify({ quests }, null, 2) + "\n";
}
