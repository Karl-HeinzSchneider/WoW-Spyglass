import { existsSync, readFileSync } from "node:fs";
import { dirname, relative, resolve } from "node:path";
import { requireAddons, walkFiles } from "./addons.js";
import { ROOT } from "./config.js";

const CORE = "ForeverLoot";
const addons = requireAddons();
const names = new Set(addons.map((addon) => addon.name));
const failures: string[] = [];
const dependencies = new Map<string, string[]>();

for (const addon of addons) {
  const toc = readFileSync(addon.toc, "utf-8");
  const dependencyLine = /^## (?:Dependencies|RequiredDeps):\s*(.*)$/m.exec(toc)?.[1] ?? "";
  const deps = dependencyLine
    .split(",")
    .map((value) => value.trim())
    .filter(Boolean);
  dependencies.set(
    addon.name,
    deps.filter((dependency) => names.has(dependency)),
  );

  if (addon.name.startsWith(`${CORE}_`) && !deps.includes(CORE)) {
    failures.push(`${relative(ROOT, addon.toc)}: companion addons must depend on ${CORE}`);
  }

  for (const line of toc.split(/\r?\n/)) {
    const entry = line.trim();
    if (!entry || entry.startsWith("#")) continue;
    const path = resolve(dirname(addon.toc), entry.replace(/\\/g, "/"));
    if (!existsSync(path)) failures.push(`${relative(ROOT, addon.toc)}: missing load entry ${entry}`);
  }
}

const core = addons.find((addon) => addon.name === CORE);
if (!core) failures.push(`missing required core addon ${CORE}`);
else {
  const companionNames = addons.filter((addon) => addon.name.startsWith(`${CORE}_`)).map((addon) => addon.name);
  for (const path of walkFiles(core.path).filter((file) => /\.(lua|xml|toc)$/i.test(file))) {
    const content = readFileSync(path, "utf-8");
    for (const companion of companionNames) {
      if (content.includes(companion))
        failures.push(`${relative(ROOT, path)}: core runtime references companion ${companion}`);
    }
  }
}

const visiting = new Set<string>();
const visited = new Set<string>();
const visit = (name: string, path: string[]) => {
  if (visiting.has(name)) {
    failures.push(`addon dependency cycle: ${[...path, name].join(" -> ")}`);
    return;
  }
  if (visited.has(name)) return;
  visiting.add(name);
  for (const dependency of dependencies.get(name) ?? []) visit(dependency, [...path, name]);
  visiting.delete(name);
  visited.add(name);
};
for (const addon of addons) visit(addon.name, []);

if (failures.length > 0) {
  console.error(failures.join("\n"));
  process.exit(1);
}
console.log(`Addon boundaries OK (${addons.map((addon) => addon.name).join(", ")})`);
