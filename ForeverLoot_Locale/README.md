# ForeverLoot Locale

This companion addon owns non-English generated item, instance, and boss names. It depends on
`ForeverLoot` and registers names through `ForeverLoot.Data:AddNames`.

The core retains generated `enUS` names as its standalone fallback. The generator writes every
additional configured or scanned locale under `db/generated/locales/` in this addon. Static UI
translations can use the same companion boundary when a UI-string registry is introduced.
