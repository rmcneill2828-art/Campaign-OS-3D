#!/usr/bin/env node
// Campaign OS "Claude DM" bridge.
//
// The app (ui/app.js) can't call the Anthropic API directly from the browser --
// api.anthropic.com's CORS policy rejects arbitrary origins (confirmed against the
// live API, not assumed). Instead, the browser writes a request file here via the
// File System Access API, this script picks it up and asks the local `claude` CLI
// (already authenticated on this machine) what should happen, and writes the answer
// back as a response file the browser polls for.
//
// Run from the Campaign-OS project root: node dm-bridge/watch.js

const fs = require("fs");
const os = require("os");
const path = require("path");
const { spawn } = require("child_process");

const bridgeDir = __dirname;
const requestPath = path.join(bridgeDir, "request.json");
const responsePath = path.join(bridgeDir, "response.json");
const endSessionRequestPath = path.join(bridgeDir, "end-session-request.json");
const endSessionResponsePath = path.join(bridgeDir, "end-session-response.json");

// The system prompt is written to the OS temp dir (not this project folder) because
// the project path contains a space ("Campaign OS"), and on Windows the `claude` CLI
// is a .cmd shim that can only be launched via a shell -- child_process's shell mode
// concatenates array args with a plain space rather than shell-quoting them, so any
// argv value containing a space (or worse, untrusted user text) would either break or
// be a command-injection risk. Keeping every argv value space-free sidesteps that
// entirely; the one piece of untrusted, variable-length content (the DM's command +
// state) goes over stdin instead, which never touches shell parsing at all.
const systemPromptPath = path.join(os.tmpdir(), "campaign-os-dm-bridge-system-prompt.txt");

const MONSTER_LIST = [
  "goblin", "orc", "troll", "bandit", "wolf", "hellhound",
  "skeleton", "zombie", "ghoul", "ogre", "owlbear", "worg", "giant spider", "cultist", "guard", "priest",
  // Phase 13 additions (2026-08-22) -- keep in sync with engine/encounter.js's STAT_BLOCKS
  // and monsterPattern; see that file's own comment for where these came from.
  "brown bear", "dire wolf", "bugbear", "hobgoblin", "gnoll", "specter", "imp", "veteran"
];
const CONDITION_LIST = [
  "Blinded", "Charmed", "Frightened", "Grappled", "Invisible", "Paralyzed", "Poisoned",
  "Prone", "Restrained", "Stunned", "Unconscious"
];
// The canonical 18 5e skills -- duplicated from engine/encounter.js's own copy, same
// convention as MONSTER_LIST/CONDITION_LIST being duplicated between this Node script and
// the browser-side engine file.
const SKILL_LIST = [
  "Acrobatics", "Animal Handling", "Arcana", "Athletics", "Deception", "History",
  "Insight", "Intimidation", "Investigation", "Medicine", "Nature", "Perception",
  "Performance", "Persuasion", "Religion", "Sleight of Hand", "Stealth", "Survival"
];
// The 13 SRD damage types -- duplicated from engine/encounter.js's own DAMAGE_TYPE_LIST,
// same convention as MONSTER_LIST/CONDITION_LIST/SKILL_LIST being duplicated between this
// Node script and the browser-side engine file (no bundler/shared-module mechanism here).
const DAMAGE_TYPE_LIST = [
  "acid", "bludgeoning", "cold", "fire", "force", "lightning", "necrotic",
  "piercing", "poison", "psychic", "radiant", "slashing", "thunder"
];

// A NEW action type needs updating in all THREE places below, or Claude can correctly emit
// it and it will still silently never apply: (1) its shape documented in this array (so
// Claude knows the field names), (2) a matching `case` in isValidAction() below (every
// action from Claude is filtered through this before ever reaching dmBridge.js -- an action
// type missing here is caught by `default: return false` and dropped with NO error/log,
// which is exactly what happened live with remove_token/roll_initiative/set_initiative: all
// three were documented here and Claude correctly generated them, narrating success in its
// own message field the whole time, but they were being silently discarded before ever
// being written to response.json, for every model tried (haiku AND sonnet) -- the fix had
// nothing to do with model choice or prompt wording, only this missing validation case),
// and (3) the actual `case` in engine/dmBridge.js's applyAction() that does something with
// it (already required, and separately tested -- this file is the one easy to forget).
const SYSTEM_PROMPT = [
  "You are the DM assistant for a D&D 5e virtual tabletop called Campaign OS.",
  "You receive the current encounter state and a line of DM narration or a command,",
  "and decide what mechanical actions (if any) should happen, plus a short narrative line.",
  "",
  "Respond with ONLY a single JSON object -- no markdown code fences, no commentary before or after --",
  "matching exactly this shape:",
  '{"message": "<one or two sentences of narration>", "actions": [ <zero or more actions> ]}',
  "",
  "Each action is one of:",
  `{"type": "spawn_monster", "monster": "${MONSTER_LIST.join("|")}", "count": <integer>}`,
  '{"type": "attack", "attacker": "<exact token name>", "target": "<exact token name>", "advantage": <optional true>, "disadvantage": <optional true>, "actionType": "<optional \'action\' (default), \'bonusAction\', or \'reaction\' (an opportunity attack)>"}',
  `{"type": "apply_damage", "target": "<exact token name>", "amount": <integer>, "damageType": "<optional ${DAMAGE_TYPE_LIST.join("|")}>"}`,
  '{"type": "apply_healing", "target": "<exact token name>", "amount": <integer>}',
  `{"type": "toggle_condition", "target": "<exact token name>", "condition": "${CONDITION_LIST.join("|")}"}`,
  '{"type": "set_visibility", "target": "<exact token name>", "hidden": <true or false>}',
  '{"type": "add_wall", "x1": <integer>, "y1": <integer>, "x2": <integer>, "y2": <integer>}',
  '{"type": "remove_wall_near", "x": <integer>, "y": <integer>}',
  '{"type": "move_token", "target": "<exact token name>", "x": <integer>, "y": <integer>}',
  '{"type": "next_turn"}',
  '{"type": "roll_initiative", "target": "<exact token name>"}',
  '{"type": "set_initiative", "target": "<exact token name>", "value": <integer 0-99>}',
  '{"type": "switch_map", "map": "<exact name from \'Maps available to switch to\' below>"}',
  '{"type": "saving_throw", "target": "<exact token name>", "ability": "STR|DEX|CON|INT|WIS|CHA", "dc": <integer>, "advantage": <optional true>, "disadvantage": <optional true>}',
  `{"type": "ability_check", "target": "<exact token name>", "skill": "${SKILL_LIST.join("|")}|STR|DEX|CON|INT|WIS|CHA", "dc": <integer>, "advantage": <optional true>, "disadvantage": <optional true>}`,
  `{"type": "cast_spell", "caster": "<exact token name>", "spell": "<spell name>", "level": <0 for a cantrip, else 1-9>, "target": "<optional exact token name>", "damageDice": "<optional dice like 4d6>", "damageType": "<optional ${DAMAGE_TYPE_LIST.join("|")}>", "concentration": <optional true, only for a spell that requires concentration>, "advantage": <optional true>, "disadvantage": <optional true>, "actionType": "<optional 'action' (default) or 'bonusAction', only enforced for a leveled spell>"}`,
  `{"type": "cast_area_spell", "caster": "<exact token name>", "spell": "<spell name>", "level": <1-9, area spells are never cantrips>, "targets": ["<exact token name>", "..."], "saveAbility": "STR|DEX|CON|INT|WIS|CHA", "saveDC": <integer>, "damageDice": "<dice like 8d6>", "damageType": "<optional ${DAMAGE_TYPE_LIST.join("|")}>", "halfOnSave": <optional false to negate entirely on a success instead of half -- defaults to true>, "concentration": <optional true>}`,
  '{"type": "use_resource", "target": "<exact token name>", "resource": "<exact resource name from that token\'s list below>", "amount": <optional integer, default 1>}',
  '{"type": "spend_hit_die", "target": "<exact token name>", "die": "<exact Hit Dice type from that token\'s list below, e.g. d10>", "count": <optional integer, default 1>}',
  '{"type": "drop_concentration", "target": "<exact token name>"}',
  '{"type": "remove_token", "target": "<exact token name>"}',
  '{"type": "add_token", "name": "<token name>", "tokenType": "<optional \'hero\' (default) or \'monster\'>", "hp": <optional integer, default 10>, "maxHp": <optional integer, defaults to hp>, "ac": <optional integer, default 12>, "abilityScores": <optional {"STR":<int>,"DEX":<int>,"CON":<int>,"INT":<int>,"WIS":<int>,"CHA":<int>}>}',
  '{"type": "roll_death_save", "target": "<exact token name>"}',
  '{"type": "long_rest", "target": "<exact token name>"}',
  '{"type": "short_rest", "target": "<exact token name>"}',
  '{"type": "add_exhaustion", "target": "<exact token name>", "amount": <optional integer, default 1; negative to remove levels>}',
  '{"type": "use_legendary_action", "target": "<exact token name>", "cost": <optional integer, default 1>}',
  '{"type": "use_recharge_ability", "target": "<exact token name>", "ability": "<exact recharge ability name from that token\'s list below, e.g. Fire Breath>"}',
  '{"type": "trigger_lair_action", "description": "<what the lair does this round>"}',
  "",
  "Only reference token names that appear in the provided state. If the command is pure narration",
  "with no mechanical effect (e.g. flavor text, a question, an out-of-combat description), return",
  'an empty "actions" array. Never invent a monster type outside the listed set -- narrate it instead.',
  "",
  "Use move_token when narration implies a token repositions on the grid -- closing to melee range,",
  "retreating, circling around -- using the grid size and each token's current (x, y) given below to",
  "pick a destination that's actually plausible, and stay within the grid bounds.",
  "",
  "Set advantage/disadvantage on an attack when 5e rules-as-written call for it and it ISN'T",
  "already one of the conditions listed below -- Reckless Attack, Pack Tactics with an ally",
  "adjacent to the target, a hidden attacker, etc. Don't set both; RAW they cancel out, so just",
  "omit both flags instead. A single attack action already resolves a monster's full",
  "Multiattack (e.g. a troll's Bite + two Claws) automatically -- issue one attack action per turn,",
  "not one per individual attack in its stat block.",
  "",
  "Damage types now carry real mechanical weight. attack's damage type comes from the attacker's",
  "own weapon/stat block automatically -- you don't set it. For apply_damage/cast_spell/",
  "cast_area_spell, set damageType when the source has a real, single, well-defined type (a",
  "fireball is fire, a mace is bludgeoning) so the engine can apply the target's resistance/",
  "vulnerability/immunity automatically -- each token's line below shows these when it has any",
  "(e.g. \"resist: fire\", \"vulnerable: bludgeoning\", \"immune: poison\"). Omit damageType entirely",
  "for a flat/narrative amount with no real single type, or one already blended across types in",
  "the source data (some monster bites approximate two damage types in one roll -- you'll see no",
  "damage type mentioned for those, on purpose). The engine applies the adjustment and reports it",
  "in the result message -- you don't compute the halved/doubled/zeroed amount yourself.",
  "",
  "attack and cast_spell (leveled spells only -- cantrips are exempt) now enforce a basic",
  "action economy, but ONLY once a token's own turn is actually running (next_turn has been",
  "called and it's this token's active turn) -- outside that, or for any other token, nothing",
  "is restricted, same as movement. Each consumes the token's action for the turn; a second",
  "action-consuming attack/cast_spell the same turn fails outright UNLESS the attacker has",
  "Extra Attack (its line below shows \"extra attacks: N\"), which lets attack() itself be",
  "called 1 + N times before the action is spent -- issue one attack action per swing for a",
  "Fighter/Barbarian with Extra Attack, not a single call. Set actionType: \"bonusAction\" for a",
  "genuine bonus-action use (an off-hand attack, Misty Step, Healing Word) -- it has its own",
  "separate one-per-turn budget from the action.",
  "",
  "Reactions (opportunity attacks) are supported via actionType: \"reaction\" on attack -- but",
  "this engine has no way to detect \"a token just left another's reach\" on its own (no",
  "square-by-square path tracking between two grid coordinates), so YOU decide when one is",
  "warranted, the same judgment call as roll_death_save's \"start of its turn\" timing. The",
  "signal to watch for: move_token's own result message ends with \"This may provoke an",
  "opportunity attack from <names>\" whenever the mover's move leaves an adjacent token's reach",
  "(a start-vs-end adjacency check, not a full path trace -- treat it as a strong hint, not a",
  "certainty). When that fires and it's narratively sensible (a hostile creature would actually",
  "take the opening), issue attack with attacker set to the token whose reach was left and",
  "actionType: \"reaction\" -- it always resolves as exactly ONE melee attack using that",
  "attacker's primary weapon (never their full Multiattack, even if they have one), and fails",
  "outright if they've already used their reaction since their own last turn (each token's line",
  "below won't show anything extra for this -- there's no persistent \"reaction available\"",
  "indicator the way legendary actions or hit dice get one, so rely on whether you've already",
  "issued a reaction for that token this round). A reaction can be taken on ANY creature's turn",
  "except the reactor's own, unlike action/bonusAction which only restrict on the actor's own",
  "turn -- don't gate it on whose turn it currently is.",
  "",
  "Conditions now carry real mechanical weight, applied automatically by the engine -- you set",
  "them with toggle_condition, but you do NOT need to also set advantage/disadvantage for these:",
  "an attacker who is Blinded, Restrained, Prone, or Poisoned rolls its own attacks at",
  "disadvantage; an attacker who is Invisible rolls at advantage. Attacking a target that is",
  "Blinded, Restrained, Prone, Stunned, Paralyzed, or Unconscious is automatically at advantage",
  "(Blinded is bidirectional -- disadvantage on its own attacks AND advantage to whoever attacks",
  "it); attacking an Invisible target is automatically at disadvantage. A hit against a Paralyzed or",
  "Unconscious target from an adjacent attacker is automatically a critical hit even without a",
  "natural 20. Stunned, Paralyzed, and Unconscious automatically fail any STR or DEX saving_throw",
  "with no roll; Restrained imposes disadvantage on DEX saves specifically. Grappled and",
  "Restrained both reduce a token's speed to 0 for move_token. Charmed and Frightened are tracked",
  "but have no automated effect -- their RAW consequences (can't attack the charmer, disadvantage",
  "while the fear source is visible) need to be handled narratively/by hand.",
  "",
  "Call next_turn whenever narration signals moving on to the next creature's turn or a new round",
  "in formal combat (the DM says \"next turn\"/\"moving on\", or you've fully resolved one token's",
  "actions for its turn). move_token only enforces a token's speed once turn order is running AND",
  "it's that specific token's active turn -- before turn order starts, or for any other token,",
  "movement is unrestricted, so don't worry about distance for narration outside formal combat.",
  "Each token's line below shows its speed and how much movement it has left this turn.",
  "",
  "Use roll_initiative at the start of combat to have the engine roll 1d20 + a token's real DEX",
  "modifier and set its initiative automatically -- issue one per combatant (heroes and monsters",
  "alike) in the same response when a fight breaks out. Use set_initiative instead for a flat",
  "assignment with no roll -- a player reporting their own physical d20 total, or correcting/",
  "tie-breaking an already-set value. Neither of these determines turn ORDER by itself; that's",
  "still next_turn cycling through tokens once initiative values are set.",
  "",
  "Use switch_map when narration moves the scene to a different prepared map -- e.g. \"the party",
  "leaves the cellar and heads outside.\" The map name must exactly match one of the names listed",
  "in \"Maps available to switch to\" below. If the destination isn't listed, it hasn't been",
  "prepared yet -- narrate the transition in prose instead and let the DM load that map first,",
  "rather than inventing a switch_map action for a map that doesn't exist.",
  "",
  "Use saving_throw when narration calls for a save -- a trap, a spell effect, a fear aura, a",
  "poison. You only decide the ability and DC; the engine rolls the die and adds the target's",
  "real ability modifier (or a stated save bonus from their sheet, which can include feats/",
  "multiclass bumps a flat formula wouldn't capture) automatically -- each token's line below",
  "shows its ability scores when known. Important: you do NOT see the die roll's outcome before",
  "deciding the rest of THIS response's actions -- saving_throw only resolves and logs pass/fail,",
  "it never applies a follow-up effect itself. For \"half damage on a success, full on a failure\"",
  "-style effects, issue the saving_throw action alone this turn and let the DM's next command",
  "(after seeing the logged result) tell you the actual damage/condition to apply. Exhaustion",
  "level 3+ and Restrained (on a DEX save specifically) already impose disadvantage",
  "automatically -- only set the advantage/disadvantage fields for a SEPARATE, situational",
  "reason the narration itself calls for (a Bless-like buff, cover, a class feature); if both",
  "end up true they correctly cancel out to a normal roll, so don't worry about double-counting",
  "an automatic source.",
  "",
  "Use ability_check for a non-save roll -- Perception to notice something, Stealth to sneak,",
  "Persuasion to talk someone down, Athletics to force a door, etc. Set skill to one of the 18",
  "named skills, or a bare ability (STR/DEX/CON/INT/WIS/CHA) for an unnamed check with no",
  "specific skill. Same one-shot-batch limitation as saving_throw: it only resolves and logs",
  "pass/fail, so a follow-up consequence (finding the hidden door, the guard believing the lie)",
  "is a separate later action/narration once you've seen the result. Exhaustion level 1+ and",
  "Poisoned already impose disadvantage automatically -- same advantage/disadvantage fields and",
  "cancel-out rule as saving_throw above, for a separate situational reason only.",
  "",
  "Use cast_spell whenever a token casts a spell. Set level to 0 for a cantrip -- it never",
  "consumes a slot; otherwise use the spell's real level, which consumes one of that caster's",
  "slots at that level automatically (each token's line below shows its slots when known). If",
  "it has none left at that level, the cast simply fails and nothing else happens -- check the",
  "slots shown before choosing a level higher than what's actually available. Only set",
  "target/damageDice for a spell that makes an attack roll (Fire Bolt, Guiding Bolt, etc.) --",
  "the engine rolls to hit using the caster's own stated spell attack bonus, shown below when",
  "known, same as saving_throw uses the target's own stated modifier. A spell that instead",
  "calls for a saving throw with NO damage of its own (Hold Person, Hideous Laughter -- an",
  "effect, not damage) has no target/damageDice here -- issue cast_spell alone to spend the",
  "slot, then a separate saving_throw action per target this same response using the caster's",
  "stated spell save DC (also shown below), and a toggle_condition once you've seen the",
  "result. A spell with neither an attack roll nor a save (buffs, utility) just needs",
  "cast_spell by itself.",
  "",
  "Use cast_area_spell instead of cast_spell for a spell that deals the SAME damage to",
  "multiple targets with a save for half (Fireball, Burning Hands, Lightning Bolt, etc.) --",
  "list every affected token in targets, set saveAbility/saveDC to the spell's own save, and",
  "damageDice to the spell's damage. This resolves the whole thing in one action: one damage",
  "roll for the area, one save per target (full damage on a failure, half -- rounded down --",
  "on a success), each logged individually. Set halfOnSave to false only for the rare effect",
  "that negates entirely on a success instead of halving. Do NOT use cast_spell + separate",
  "saving_throw actions for this case -- you'd have to decide the damage before seeing any",
  "target's save result, which the one-shot-batch limitation below doesn't allow; cast_area_spell",
  "sidesteps that by resolving the half/full decision inside the engine itself.",
  "",
  "Use use_resource whenever a token spends a limited class resource -- Rage, Wild Shape, Ki",
  "Points, Superiority Dice, Channel Divinity, Bardic Inspiration, etc. -- shown in that",
  "token's own \"resources\" list below; match the name exactly as listed there. It only spends",
  "the charge and logs how many are left, the same composable way cast_spell only spends a",
  "slot -- any actual effect (an attack, a saving throw, healing) still needs its own separate",
  "action in this same response. If a token has no resources listed at all, or doesn't list the",
  "one narration calls for, don't invent one -- narrate around it instead rather than guessing",
  "at a name or count that isn't actually shown.",
  "",
  "Use spend_hit_die when a token spends Hit Dice to heal (during a short rest, or any other",
  "time 5e RAW lets a creature do this) -- shown in that token's own \"hit dice\" list below",
  "(e.g. \"d10 3/4\"), keyed by die type since a multiclassed token can track more than one.",
  "Set die to the exact type shown, count to how many to spend (default 1). This rolls that",
  "many dice plus the token's CON modifier per die and heals the total automatically -- you",
  "don't compute the healing yourself. If a token has none of that die type left, or none",
  "tracked at all, don't invent it -- narrate around it instead.",
  "",
  "Set concentration: true on cast_spell only for a spell that actually requires concentration",
  "(you know which spells do from 5e rules -- most buffs/debuffs and many ongoing-damage spells",
  "do, most instant-effect spells don't). Casting another concentration spell automatically",
  "ends whatever that caster was already concentrating on -- the engine handles this, you don't",
  "need a separate drop_concentration for it. You also don't need to manage concentration",
  "checks yourself: any damage a concentrating token takes automatically rolls a CON save (or",
  "ends outright with no save if it drops to 0 HP) as part of apply_damage/attack/cast_spell's",
  "own resolution, and the result is logged for you to react to on a later command -- the same",
  "one-shot-batch reason saving_throw's outcome isn't visible to you yet either. Each token's",
  "line below shows \"concentrating on <spell>\" when applicable. Use drop_concentration only",
  "when a caster voluntarily stops on purpose (not as a reaction to a failed save -- the engine",
  "already handles that case).",
  "",
  "When the DM's command says \"remove\"/\"delete\" a specific named token, always issue a",
  "remove_token action for it -- never just narrate that it's gone. It deletes the token",
  "outright (a summoned creature expiring, cleaning up a mistaken spawn). Narration alone",
  "implying a token died is different -- use apply_damage/attack instead so it stays on the",
  "map, visibly dead, which is usually what that actually means.",
  "",
  "When the DM's command introduces a new named hero/ally/NPC that isn't in the current state",
  "and isn't a listed SRD monster, issue add_token for it (tokenType \"hero\" unless it's",
  "clearly a monster-type creature) rather than just narrating their presence -- otherwise",
  "nothing they do afterward (an attack naming them, a saving throw) can resolve, since",
  "findTokenByName has nothing to find. For a real SRD monster, use spawn_monster instead --",
  "it gets an accurate stat block add_token's own generic defaults can't provide.",
  "",
  "Death saves are also mostly automatic. A token dropping from above 0 to exactly 0 HP (from",
  "attack, apply_damage, or cast_spell) starts them on its own -- you don't set anything up.",
  "Further damage to a token already at 0 HP is an automatic failed death save (two if it was a",
  "critical hit), not a roll, and is also handled for you as part of whatever action dealt that",
  "damage. What you DO need to do: call roll_death_save for a token that is down (its line below",
  "says \"dying\") once its turn comes up, unless it's already \"stable\" -- that's the one place",
  "this needs an explicit action, since the engine has no way to know whose turn it is on its",
  "own. A natural 20 revives it at 1 HP, three successes stabilizes it (no more rolls needed",
  "until it takes damage again), three failures kills it -- react to whichever happened using",
  "the result logged, the same as any other roll you don't see the outcome of in advance.",
  "",
  "Use long_rest/short_rest when narration says a token (or the whole party -- issue one",
  "action per token) rests. long_rest fully heals HP, restores every spell slot and every",
  "resource to max, restores half (rounded down, minimum one) of every Hit Dice pool, and removes one level",
  "of exhaustion -- but skips the HP/revival part for a token already flagged \"dead\" (that",
  "needs an actual revival, not a rest). short_rest restores only resources tagged as",
  "short-rest recovery (shown per-resource below, e.g. \"Second Wind 0/1 (short)\") -- it never",
  "touches HP, spell slots (almost nothing but Warlock Pact Magic recovers those on a short",
  "rest, which isn't specially handled either), or Hit Dice automatically; if narration says a",
  "character spends Hit Dice during the short rest, issue a separate spend_hit_die action for",
  "that -- how many (if any) to spend is the player's choice each time, not automatic. Don't",
  "invent a rest for a token that isn't part of the current scene. long_rest doesn't need a",
  "separate add_exhaustion for its exhaustion reduction either.",
  "",
  "Use add_exhaustion when narration causes a token to gain exhaustion (a forced march, extreme",
  "cold/heat without protection, certain spells/effects) or lose it (Greater Restoration) --",
  "amount defaults to 1, use a negative number to remove levels. Each token's line below shows",
  "its exhaustion level when above 0. The engine automatically applies disadvantage on attack",
  "rolls and saving throws at level 3+, and halves (level 2+) or zeroes (level 5+) movement",
  "speed -- you don't need to set advantage/disadvantage yourself for that, it happens as part",
  "of attack/saving_throw/move_token's own resolution. Level 6 kills the token outright, no",
  "save. Disadvantage on ability checks (level 1) and a halved HP maximum (level 4) are NOT",
  "modeled -- this engine has no ability-check mechanic at all, and halving/restoring maxHp",
  "isn't automated; call those out narratively or handle them as a DM ruling instead of",
  "expecting an action for either.",
  "",
  "Use use_legendary_action for a legendary monster (its line below shows \"legendary actions",
  "N/M\" when it has any) spending one at the end of another creature's turn -- cost defaults",
  "to 1, set it higher only for an action that RAW costs more (e.g. 2 or 3). Like",
  "use_resource, you don't need a target to have any listed at all if it doesn't -- don't",
  "invent legendary actions for a token that has none. Legendary actions regain to full",
  "automatically at the start of that token's own turn (via next_turn), so you never need to",
  "restore them yourself. This engine has no notion of whose turn just ended beyond next_turn's",
  "own result, so the timing judgment (\"is this actually the end of someone else's turn?\") is",
  "yours to make from the narration/next_turn sequence, the same as roll_death_save's timing.",
  "",
  "Some monsters automatically heal or recharge an ability at the start of their own turn --",
  "next_turn handles both on its own (logged as its own line, alongside next_turn's usual",
  "\"Round N -- X's turn\" line): a token with regeneration heals automatically (no action",
  "needed from you), and a token with recharge abilities (its line below shows e.g. \"Fire",
  "Breath (not available)\") rolls to recharge each one still spent. Use use_recharge_ability",
  "only to SPEND one that's currently available -- set ability to its exact name from that",
  "token's list. Like use_resource/use_legendary_action, it only spends it; the actual effect",
  "(Fire Breath's damage/save) still needs its own separate action in this same response --",
  "cast_area_spell is the natural fit for an area breath weapon. Don't invent a recharge",
  "ability for a token that doesn't list one.",
  "",
  "Use trigger_lair_action when the scene is in a legendary creature's lair and narration",
  "reaches initiative count 20 for the round (typically right after the highest-initiative",
  "creature's turn, before anyone else acts) -- describe what the lair does this round in",
  "`description`. It only fires once per round; a second call the same round is refused, so",
  "don't retry it if that happens -- wait for next_turn to actually advance the round. Any real",
  "effect the lair action causes (damage, a saving throw, a condition) still needs its own",
  "separate action in the same response, same compose-only pattern as cast_spell/use_resource.",
  "",
  "Use set_visibility to hide a token from the DM's read-only player window (a second screen the",
  "table can see) entirely -- a secret monster, an ambush not yet sprung, an NPC the party hasn't",
  "met yet -- or to reveal one once it should be seen. A token's line below says \"hidden from",
  "players\" when it currently is, so check that before deciding whether to toggle it. This only",
  "affects the player window's map and initiative list -- it does NOT retroactively (or",
  "prospectively) scrub the hidden token's name out of narration or the combat log, so avoid",
  "naming a hidden token in your own `message` text if the point is to keep it a surprise.",
  "",
  "Use add_wall/remove_wall_near only for a real, narrated change to the map's geometry -- a",
  "section of wall collapsing, a secret door swinging open, rubble sealing a passage. These are",
  "map-prep tools the DM normally uses directly (a Walls toggle + click-drag), not something to",
  "reach for casually. Wall coordinates are grid VERTICES (corners between cells), NOT the same",
  "1-indexed cell coordinates tokens use for x/y -- vertex (0,0) is the map's top-left corner and",
  "vertex (columns,rows) is its bottom-right, so a wall spanning the full left edge of a 12x8 grid",
  "is x1=0,y1=0 to x2=0,y2=8. The line below shows how many walls a map already has -- 0 means",
  "line of sight/fog of war aren't active for it at all (no restriction exists until at least one",
  "wall is drawn); don't add a wall just to \"turn on\" that system unless the narration actually",
  "calls for a real obstruction existing there. remove_wall_near takes a point close to the wall",
  "you mean, not exact endpoints -- it finds and removes whichever wall is nearest.",
  "",
  "You may also receive campaign context (a prior session's recap, an NPC's notes) before the",
  "current state. Use it to keep names, places, and plot details consistent with the real campaign --",
  "but it never overrides the actual token state above, which is always the current truth."
].join("\n");

fs.writeFileSync(systemPromptPath, SYSTEM_PROMPT, "utf8");

// A request file left over from a previous run of the watcher (the app crashed, the DM
// closed the terminal mid-command, a stray click before DND_REPO_PATH was set) would
// otherwise get reprocessed on every restart, since lastProcessedId resets to null and
// the file's `id` looks "new" to a fresh process. That's surprising at best (an old combat
// command replaying against however the encounter looks now) and wasteful at worst (a real
// Claude Code call for End Session/Create Character, potentially writing to the campaign
// repo, firing again with stale/insufficient data). Reading whatever's already on disk at
// startup and treating its id as already-handled closes that gap -- only a genuinely new
// write (a fresh id) after the watcher is up will ever be processed.
function primeLastProcessedId(filePath) {
  try {
    const request = JSON.parse(fs.readFileSync(filePath, "utf8"));
    return request.id || null;
  } catch {
    return null;
  }
}

let lastProcessedId = primeLastProcessedId(requestPath);

function isValidAction(action) {
  if (!action || typeof action !== "object") return false;
  switch (action.type) {
    case "spawn_monster":
      return MONSTER_LIST.includes(String(action.monster || "").toLowerCase())
        && Number.isFinite(action.count) && action.count > 0;
    case "attack":
      return typeof action.attacker === "string" && typeof action.target === "string"
        && (action.advantage === undefined || typeof action.advantage === "boolean")
        && (action.disadvantage === undefined || typeof action.disadvantage === "boolean")
        && (action.actionType === undefined || action.actionType === "action" || action.actionType === "bonusAction" || action.actionType === "reaction");
    case "apply_damage":
      return typeof action.target === "string" && Number.isFinite(action.amount) && action.amount > 0
        && (action.damageType === undefined || DAMAGE_TYPE_LIST.includes(String(action.damageType).toLowerCase()));
    case "apply_healing":
      return typeof action.target === "string" && Number.isFinite(action.amount) && action.amount > 0;
    case "toggle_condition":
      return typeof action.target === "string" && CONDITION_LIST.includes(action.condition);
    case "set_visibility":
      return typeof action.target === "string" && typeof action.hidden === "boolean";
    case "add_wall":
      return Number.isFinite(action.x1) && Number.isFinite(action.y1)
        && Number.isFinite(action.x2) && Number.isFinite(action.y2);
    case "remove_wall_near":
      return Number.isFinite(action.x) && Number.isFinite(action.y);
    case "move_token":
      return typeof action.target === "string" && Number.isFinite(action.x) && Number.isFinite(action.y);
    case "next_turn":
      return true;
    case "roll_initiative":
      return typeof action.target === "string";
    case "set_initiative":
      return typeof action.target === "string" && Number.isFinite(action.value);
    case "switch_map":
      return typeof action.map === "string" && action.map.trim().length > 0;
    case "saving_throw":
      return typeof action.target === "string" && typeof action.ability === "string" && Number.isFinite(action.dc);
    case "ability_check":
      return typeof action.target === "string" && typeof action.skill === "string" && Number.isFinite(action.dc);
    case "cast_spell":
      return typeof action.caster === "string" && typeof action.spell === "string"
        && Number.isFinite(action.level) && action.level >= 0 && action.level <= 9
        && (action.target === undefined || typeof action.target === "string")
        && (action.damageDice === undefined || typeof action.damageDice === "string")
        && (action.damageType === undefined || DAMAGE_TYPE_LIST.includes(String(action.damageType).toLowerCase()))
        && (action.concentration === undefined || typeof action.concentration === "boolean")
        && (action.advantage === undefined || typeof action.advantage === "boolean")
        && (action.disadvantage === undefined || typeof action.disadvantage === "boolean")
        && (action.actionType === undefined || action.actionType === "action" || action.actionType === "bonusAction");
    case "cast_area_spell":
      return typeof action.caster === "string" && typeof action.spell === "string"
        && Number.isFinite(action.level) && action.level >= 1 && action.level <= 9
        && Array.isArray(action.targets) && action.targets.length > 0
        && action.targets.every((name) => typeof name === "string")
        && typeof action.saveAbility === "string" && Number.isFinite(action.saveDC)
        && typeof action.damageDice === "string"
        && (action.damageType === undefined || DAMAGE_TYPE_LIST.includes(String(action.damageType).toLowerCase()))
        && (action.halfOnSave === undefined || typeof action.halfOnSave === "boolean")
        && (action.concentration === undefined || typeof action.concentration === "boolean");
    case "use_resource":
      return typeof action.target === "string" && typeof action.resource === "string"
        && (action.amount === undefined || (Number.isFinite(action.amount) && action.amount > 0));
    case "spend_hit_die":
      return typeof action.target === "string" && typeof action.die === "string"
        && (action.count === undefined || (Number.isFinite(action.count) && action.count > 0));
    case "drop_concentration":
    case "remove_token":
    case "roll_death_save":
    case "long_rest":
    case "short_rest":
      return typeof action.target === "string";
    case "add_token":
      return typeof action.name === "string" && action.name.trim().length > 0
        && (action.tokenType === undefined || action.tokenType === "hero" || action.tokenType === "monster")
        && (action.hp === undefined || Number.isFinite(action.hp))
        && (action.maxHp === undefined || Number.isFinite(action.maxHp))
        && (action.ac === undefined || Number.isFinite(action.ac))
        && (action.abilityScores === undefined || (typeof action.abilityScores === "object" && action.abilityScores !== null));
    case "add_exhaustion":
      return typeof action.target === "string" && (action.amount === undefined || Number.isFinite(action.amount));
    case "use_legendary_action":
      return typeof action.target === "string" && (action.cost === undefined || (Number.isFinite(action.cost) && action.cost > 0));
    case "use_recharge_ability":
      return typeof action.target === "string" && typeof action.ability === "string";
    case "trigger_lair_action":
      return typeof action.description === "string" && action.description.trim().length > 0;
    default:
      return false;
  }
}

function extractJson(text) {
  if (typeof text !== "string") return null;
  const fenced = text.match(/```(?:json)?\s*([\s\S]*?)```/);
  const candidate = fenced ? fenced[1] : text;
  try {
    return JSON.parse(candidate.trim());
  } catch {
    return null;
  }
}

function buildPrompt(request) {
  const state = request.state || {};
  const tokens = Array.isArray(state.tokens) ? state.tokens : [];
  const lines = [];

  if (request.context && request.context.text) {
    lines.push(
      `Relevant campaign context ("${request.context.title}"):`,
      request.context.text,
      ""
    );
  }

  const grid = state.grid || {};
  const availableMaps = Array.isArray(state.availableMaps) ? state.availableMaps : [];
  lines.push(
    `Current map: ${state.mapName || "(none)"}`,
    `Grid size: ${grid.columns || 12} columns x ${grid.rows || 8} rows (1-based, top-left is 1,1).`,
    `Walls on this map: ${Number.isFinite(state.wallCount) ? state.wallCount : 0} (0 means line of sight/fog of war aren't active for it at all).`,
    state.activeToken
      ? `Turn order: running -- round ${state.round || 1}, ${state.activeToken}'s turn.`
      : "Turn order: not running -- use next_turn to start it once formal combat begins.",
    state.lairActionUsedThisRound
      ? "This round's lair action has already triggered -- wait for next_turn to advance the round before another."
      : "This round's lair action has not triggered yet.",
    availableMaps.length
      ? `Maps available to switch to: ${availableMaps.join(", ")}.`
      : "No other prepared maps to switch to right now.",
    "Tokens on the map:"
  );
  if (tokens.length === 0) {
    lines.push("(none)");
  } else {
    tokens.forEach((t) => {
      const conditions = Array.isArray(t.conditions) && t.conditions.length
        ? `, conditions: ${t.conditions.join(", ")}`
        : "";
      const speed = Number.isFinite(t.speed) ? t.speed : 30;
      const movementLeft = Number.isFinite(t.movementLeft) ? t.movementLeft : speed;
      const scores = t.abilityScores || {};
      const knownAbilities = ["STR", "DEX", "CON", "INT", "WIS", "CHA"].filter((key) => Number.isFinite(scores[key]));
      const abilities = knownAbilities.length
        ? `, abilities ${knownAbilities.map((key) => `${key} ${scores[key]}`).join(" ")}`
        : "";
      const spellcasting = t.spellcasting || {};
      const spellcastingParts = [];
      if (Number.isFinite(spellcasting.saveDC)) spellcastingParts.push(`DC ${spellcasting.saveDC}`);
      if (Number.isFinite(spellcasting.attackBonus)) spellcastingParts.push(`atk +${spellcasting.attackBonus}`);
      const spellcastingText = spellcastingParts.length ? `, spellcasting ${spellcastingParts.join(" ")}` : "";
      const slots = t.spellSlots || {};
      const slotLevels = Object.keys(slots)
        .map(Number)
        .filter((level) => slots[level] && Number.isFinite(slots[level].current) && Number.isFinite(slots[level].max))
        .sort((a, b) => a - b);
      const slotsText = slotLevels.length
        ? `, slots ${slotLevels.map((level) => `${slots[level].current}/${slots[level].max} L${level}`).join(" ")}`
        : "";
      const resources = t.resources || {};
      const resourceNames = Object.keys(resources)
        .filter((name) => resources[name] && Number.isFinite(resources[name].current) && Number.isFinite(resources[name].max));
      const resourcesText = resourceNames.length
        ? `, resources ${resourceNames.map((name) => `${name} ${resources[name].current}/${resources[name].max} (${resources[name].recovery === "short" ? "short" : "long"})`).join(", ")}`
        : "";
      const concentrationText = t.concentratingOn?.spell ? `, concentrating on ${t.concentratingOn.spell}` : "";
      const exhaustionText = Number.isFinite(t.exhaustion) && t.exhaustion > 0 ? `, exhaustion ${t.exhaustion}` : "";
      let deathStatusText = "";
      if (t.dead) deathStatusText = ", dead";
      else if (t.dying?.stable) deathStatusText = ", stable at 0 HP";
      else if (t.dying) deathStatusText = `, dying (${t.dying.successes} successes, ${t.dying.failures} failures)`;
      const legendaryActionsText = t.legendaryActions && Number.isFinite(t.legendaryActions.current) && Number.isFinite(t.legendaryActions.max)
        ? `, legendary actions ${t.legendaryActions.current}/${t.legendaryActions.max}`
        : "";
      const resistText = Array.isArray(t.damageResistances) && t.damageResistances.length ? `, resist: ${t.damageResistances.join(", ")}` : "";
      const vulnText = Array.isArray(t.damageVulnerabilities) && t.damageVulnerabilities.length ? `, vulnerable: ${t.damageVulnerabilities.join(", ")}` : "";
      const immuneText = Array.isArray(t.damageImmunities) && t.damageImmunities.length ? `, immune: ${t.damageImmunities.join(", ")}` : "";
      const visibilityText = t.hiddenFromPlayers ? ", hidden from players" : "";
      const visionRangeText = Number.isFinite(t.visionRange) ? `, vision range ${t.visionRange} ft` : "";
      lines.push(`- ${t.name} (${t.type}) at (${t.x}, ${t.y}): ${t.hp}/${t.maxHp} HP, AC ${t.ac}, speed ${speed} ft (${movementLeft} ft left this turn)${conditions}${abilities}${spellcastingText}${slotsText}${resourcesText}${concentrationText}${deathStatusText}${exhaustionText}${legendaryActionsText}${resistText}${vulnText}${immuneText}${visibilityText}${visionRangeText}`);
    });
  }
  lines.push("", `DM narration/command: "${request.command}"`);
  return lines.join("\n");
}

// This project lives under OneDrive (see ARCHITECTURE.md/README.md), where sync or an
// AV scan can transiently lock a response file (EBUSY/EPERM/EAGAIN) for a moment right
// when we try to write it. Previously that failure was only ever logged to the console;
// the actual caller (engine-server's waitForBridgeResponse, or the 2D app's own polling
// loop) never learns why and just sees its own blind timeout with no pointer to the real
// cause. Retrying a few times with a short backoff turns that transient lock into a
// normal write instead of a silently lost request.
const RESPONSE_WRITE_RETRY_DELAYS_MS = [200, 500, 1000];
const TRANSIENT_WRITE_ERROR_CODES = new Set(["EBUSY", "EPERM", "EACCES", "EAGAIN"]);

function writeJsonResponseFile(filePath, response, successMessage, failureLabel, attempt = 0) {
  fs.writeFile(filePath, JSON.stringify(response, null, 2), (err) => {
    if (!err) {
      console.log(successMessage);
      return;
    }
    if (TRANSIENT_WRITE_ERROR_CODES.has(err.code) && attempt < RESPONSE_WRITE_RETRY_DELAYS_MS.length) {
      const delay = RESPONSE_WRITE_RETRY_DELAYS_MS[attempt];
      console.warn(`[dm-bridge] ${failureLabel} write failed (${err.code}), retrying in ${delay}ms...`);
      setTimeout(() => writeJsonResponseFile(filePath, response, successMessage, failureLabel, attempt + 1), delay);
      return;
    }
    console.error(`[dm-bridge] failed to write ${failureLabel} after ${attempt} retr${attempt === 1 ? "y" : "ies"}:`, err.message);
  });
}

function writeResponse(id, payload) {
  const response = { id, respondedAt: new Date().toISOString(), ...payload };
  writeJsonResponseFile(responsePath, response, `[dm-bridge] responded to ${id}: ${payload.message}`, "response.json");
}

// Every argv element here is fixed and space-free (flag names, "json", "haiku", a
// comma-joined tool list, and the temp-dir system-prompt path) -- required because
// child_process's Windows shell mode does not escape array args, only concatenates
// them (see the comment on systemPromptPath above). The one piece of untrusted,
// variable-length input -- the DM's command and current encounter state -- is written
// to the child's stdin instead, never appearing on the command line at all.
function runClaude(prompt, onDone) {
  const model = process.env.DM_BRIDGE_MODEL || "haiku";
  const args = [
    "-p",
    "--output-format", "json",
    "--system-prompt-file", systemPromptPath,
    "--model", model,
    "--disallowedTools", "Bash,Edit,Write,Read,Glob,Grep,WebSearch,WebFetch,NotebookEdit,Agent,Task",
    "--max-budget-usd", "0.50"
  ];

  const child = spawn("claude", args, {
    shell: process.platform === "win32",
    windowsHide: true
  });

  let stdout = "";
  let stderr = "";
  let settled = false;
  const finish = (err, out, errOut) => {
    if (settled) return;
    settled = true;
    onDone(err, out, errOut);
  };
  child.stdout.on("data", (chunk) => { stdout += chunk; });
  child.stderr.on("data", (chunk) => { stderr += chunk; });
  child.on("error", (err) => finish(err, "", ""));
  child.on("close", (code, signal) => {
    // A well-formed JSON envelope on stdout is not proof the call actually succeeded --
    // the process can be killed (OOM, a timeout elsewhere, a manual kill) right after
    // flushing it but before exiting cleanly. Treat a nonzero exit code or a signal the
    // same as the "error" event above: a failed call, not a silent success.
    if (code !== 0 || signal) {
      finish(new Error(`claude CLI exited with ${signal ? `signal ${signal}` : `code ${code}`}`), stdout, stderr);
      return;
    }
    finish(null, stdout, stderr);
  });

  child.stdin.write(prompt);
  child.stdin.end();
}

function handleRequest(request) {
  console.log(`[dm-bridge] processing ${request.id}: "${request.command}"`);
  const prompt = buildPrompt(request);

  runClaude(prompt, (err, stdout, stderr) => {
    if (err) {
      console.error("[dm-bridge] claude invocation failed:", stderr || err.message);
      writeResponse(request.id, { message: "The DM assistant hit an error and couldn't respond.", actions: [] });
      return;
    }

    let parsed;
    try {
      parsed = JSON.parse(stdout);
    } catch {
      console.error("[dm-bridge] could not parse claude CLI output as JSON:", stdout.slice(0, 300));
      writeResponse(request.id, { message: "The DM assistant's response wasn't valid JSON.", actions: [] });
      return;
    }

    if (parsed.is_error) {
      writeResponse(request.id, { message: `The DM assistant reported an error: ${parsed.result}`, actions: [] });
      return;
    }

    const inner = extractJson(parsed.result);
    if (!inner) {
      writeResponse(request.id, { message: String(parsed.result || "").slice(0, 500) || "No response.", actions: [] });
      return;
    }

    writeResponse(request.id, {
      message: typeof inner.message === "string" ? inner.message : "",
      actions: Array.isArray(inner.actions) ? inner.actions.filter(isValidAction) : []
    });
  });
}

function poll() {
  fs.readFile(requestPath, "utf8", (err, data) => {
    if (!err) {
      try {
        const request = JSON.parse(data);
        if (request.id && request.id !== lastProcessedId) {
          lastProcessedId = request.id;
          handleRequest(request);
        }
      } catch {
        // partial write mid-poll -- try again next tick
      }
    }
    setTimeout(poll, 1500);
  });
}

// --- End Session write-back -------------------------------------------------------
//
// Unlike the combat-narration flow above (which deliberately disallows every tool and
// demands a single strict JSON reply), this is a real, multi-step Claude Code call
// with actual Read/Write/Edit access to the DnD campaign repo -- it reads the current
// session-log.md and world-state.md, drafts an update in the campaign's existing
// narrative style, and writes it directly. It never runs Bash and is never given a
// reason to touch git: nothing is committed or pushed here, on purpose. The DM
// reviews the resulting diff in the campaign repo and commits it themselves, same as
// any other edit to that repo.

const END_SESSION_SYSTEM_PROMPT = [
  "You are helping a Dungeon Master fold the results of a combat/roleplay session run in a",
  "virtual tabletop app (Campaign OS) back into their campaign's markdown records.",
  "",
  "Your working directory is the root of the campaign repository. Steps:",
  "1. Read active.md to find the active campaign's slug and folder (campaigns/<slug>/).",
  "2. Read that campaign's session-log.md. Find the highest existing \"## Session N\" heading",
  "   and determine the next session number.",
  "3. Using the provided transcript and final token states, write a new \"## Session N -- <date>\"",
  "   section at the END of session-log.md, in the SAME narrative prose style as the existing",
  "   entries -- named beats, character voice, thematic callbacks, not a mechanical log dump.",
  "   Use today's date if no better date is implied by the transcript.",
  "4. Read that campaign's world-state.md. Update only what actually changed: party",
  "   location/HP/conditions, the quest log, NPC statuses, location statuses. Leave unrelated",
  "   sections untouched. world-state.md is a living tracker of ACTIVE threads only --",
  "   full blow-by-blow history belongs in session-log.md, not here.",
  "5. Do not modify character sheet files unless the transcript clearly implies a permanent",
  "   change (e.g. a level-up, a name/identity reveal) -- ordinary HP loss during the session",
  "   is not permanent once the party rests, so do not update character HP fields for that alone.",
  "6. Do not run git commands and do not attempt to commit or push anything -- file edits only.",
  "",
  "When finished, reply with a short plain-text summary (2-4 sentences) of exactly which files",
  "you changed and what you added -- this is shown directly to the DM, not parsed as JSON."
].join("\n");

const endSessionSystemPromptPath = path.join(os.tmpdir(), "campaign-os-dm-bridge-end-session-system-prompt.txt");
fs.writeFileSync(endSessionSystemPromptPath, END_SESSION_SYSTEM_PROMPT, "utf8");

let lastProcessedEndSessionId = primeLastProcessedId(endSessionRequestPath);

function buildEndSessionPrompt(request) {
  const state = request.finalState || {};
  const tokens = Array.isArray(state.tokens) ? state.tokens : [];
  const lines = [
    "Session transcript (chronological):",
    ...((request.transcript || []).map((line) => `- ${line}`)),
    "",
    `Final map: ${state.mapName || "(none)"}`,
    "Final token states:"
  ];
  if (tokens.length === 0) {
    lines.push("(none)");
  } else {
    tokens.forEach((t) => {
      const conditions = Array.isArray(t.conditions) && t.conditions.length ? `, conditions: ${t.conditions.join(", ")}` : "";
      lines.push(`- ${t.name} (${t.type}, on ${t.mapName || "unknown map"}): ${t.hp}/${t.maxHp} HP, AC ${t.ac}${conditions}`);
    });
  }
  if (request.contextTitle) {
    lines.push("", `DM had "${request.contextTitle}" attached as context during this session.`);
  }
  return lines.join("\n");
}

function writeEndSessionResponse(id, ok, message) {
  const response = { id, ok, message, respondedAt: new Date().toISOString() };
  writeJsonResponseFile(
    endSessionResponsePath,
    response,
    `[dm-bridge] end-session ${id} ${ok ? "succeeded" : "failed"}: ${message}`,
    "end-session-response.json"
  );
}

function handleEndSessionRequest(request) {
  console.log(`[dm-bridge] processing end-session ${request.id}`);
  const dndRepoPath = process.env.DND_REPO_PATH;
  if (!dndRepoPath) {
    writeEndSessionResponse(request.id, false,
      "DND_REPO_PATH isn't set. Stop the watcher, set it to your campaign repo's path (e.g. " +
      "DND_REPO_PATH=/path/to/DND/Campaign node dm-bridge/watch.js), and try again.");
    return;
  }
  if (!fs.existsSync(dndRepoPath)) {
    writeEndSessionResponse(request.id, false, `DND_REPO_PATH is set to "${dndRepoPath}", but that path doesn't exist.`);
    return;
  }

  const prompt = buildEndSessionPrompt(request);
  const model = process.env.DM_BRIDGE_MODEL || "haiku";
  const args = [
    "-p",
    "--output-format", "json",
    "--system-prompt-file", endSessionSystemPromptPath,
    "--model", model,
    "--allowedTools", "Read,Write,Edit",
    "--permission-mode", "acceptEdits",
    "--max-budget-usd", "2.00"
  ];

  const child = spawn("claude", args, {
    cwd: dndRepoPath,
    shell: process.platform === "win32",
    windowsHide: true
  });

  let stdout = "";
  let stderr = "";
  child.stdout.on("data", (chunk) => { stdout += chunk; });
  child.stderr.on("data", (chunk) => { stderr += chunk; });
  child.on("error", (err) => {
    writeEndSessionResponse(request.id, false, `Couldn't start claude: ${err.message}`);
  });
  child.on("close", () => {
    let parsed;
    try {
      parsed = JSON.parse(stdout);
    } catch {
      console.error("[dm-bridge] could not parse end-session claude output as JSON:", stdout.slice(0, 300));
      writeEndSessionResponse(request.id, false, "Claude's response wasn't valid JSON -- check the watcher's console output.");
      return;
    }
    if (parsed.is_error) {
      writeEndSessionResponse(request.id, false, `Claude reported an error: ${parsed.result}`);
      return;
    }
    writeEndSessionResponse(request.id, true, String(parsed.result || "Done, but Claude didn't summarize what changed."));
  });

  child.stdin.write(prompt);
  child.stdin.end();
}

function pollEndSession() {
  fs.readFile(endSessionRequestPath, "utf8", (err, data) => {
    if (!err) {
      try {
        const request = JSON.parse(data);
        if (request.id && request.id !== lastProcessedEndSessionId) {
          lastProcessedEndSessionId = request.id;
          handleEndSessionRequest(request);
        }
      } catch {
        // partial write mid-poll -- try again next tick
      }
    }
    setTimeout(pollEndSession, 1500);
  });
}

// --- Create Character write-back ----------------------------------------------------
//
// Deterministic, not an LLM call: the browser (ui/app.js, via engine/characterCreator.js)
// already computed the full sheet markdown and just needs it written into the campaign
// repo's characters/ folder. No Claude subprocess, no cost, near-instant. Still gated by
// DND_REPO_PATH like End Session, and never overwrites an existing file -- if the name
// collides, the DM picks a different one rather than silently clobbering a real sheet.
// The requested file name is run through path.basename() before use so a malformed or
// malicious fileName value can't escape the characters/ directory.

const createCharacterRequestPath = path.join(bridgeDir, "create-character-request.json");
const createCharacterResponsePath = path.join(bridgeDir, "create-character-response.json");
let lastProcessedCreateCharacterId = primeLastProcessedId(createCharacterRequestPath);

function writeCreateCharacterResponse(id, ok, message) {
  const response = { id, ok, message, respondedAt: new Date().toISOString() };
  writeJsonResponseFile(
    createCharacterResponsePath,
    response,
    `[dm-bridge] create-character ${id} ${ok ? "succeeded" : "failed"}: ${message}`,
    "create-character-response.json"
  );
}

function handleCreateCharacterRequest(request) {
  console.log(`[dm-bridge] processing create-character ${request.id}`);
  const dndRepoPath = process.env.DND_REPO_PATH;
  if (!dndRepoPath) {
    writeCreateCharacterResponse(request.id, false,
      "DND_REPO_PATH isn't set. Stop the watcher, set it to your campaign repo's path (e.g. " +
      "DND_REPO_PATH=/path/to/DND/Campaign node dm-bridge/watch.js), and try again.");
    return;
  }
  if (!fs.existsSync(dndRepoPath)) {
    writeCreateCharacterResponse(request.id, false, `DND_REPO_PATH is set to "${dndRepoPath}", but that path doesn't exist.`);
    return;
  }

  const fileName = path.basename(String(request.fileName || "").trim()) || "Character.md";
  if (!fileName.toLowerCase().endsWith(".md")) {
    writeCreateCharacterResponse(request.id, false, "Character file name must end in .md.");
    return;
  }

  const charactersDir = path.join(dndRepoPath, "characters");
  fs.mkdirSync(charactersDir, { recursive: true });
  const targetPath = path.join(charactersDir, fileName);

  if (fs.existsSync(targetPath)) {
    writeCreateCharacterResponse(request.id, false,
      `A character file named "${fileName}" already exists -- pick a different name.`);
    return;
  }

  try {
    fs.writeFileSync(targetPath, String(request.markdown || ""), "utf8");
  } catch (err) {
    writeCreateCharacterResponse(request.id, false, `Couldn't write the character file: ${err.message}`);
    return;
  }

  writeCreateCharacterResponse(request.id, true, `Created characters/${fileName} in the campaign repo.`);
}

function pollCreateCharacter() {
  fs.readFile(createCharacterRequestPath, "utf8", (err, data) => {
    if (!err) {
      try {
        const request = JSON.parse(data);
        if (request.id && request.id !== lastProcessedCreateCharacterId) {
          lastProcessedCreateCharacterId = request.id;
          handleCreateCharacterRequest(request);
        }
      } catch {
        // partial write mid-poll -- try again next tick
      }
    }
    setTimeout(pollCreateCharacter, 1500);
  });
}

// Player-editable character sheets (Phase 10, 2026-08-22) -- character.html's own,
// independent DM-bridge connection writes here. Deliberately narrow: only the single
// `**HP:** current / max` line under a sheet's `## Combat` heading is ever touched.
// Everything else on a real sheet (backstory, ability scores, and critically the
// `## Current Status` section) is DM/Claude-authored freeform prose that mixes simple
// trackers with irreplaceable narrative content line-by-line (session milestones, ongoing
// character arcs) -- see a real sheet like characters/Darkhawk Blondin.md's Current Status
// for why a blind regex patch has no safe way to touch that section without real risk of
// corrupting or displacing story content. The `**HP:**` line under Combat is the one
// field that's genuinely safe: present, consistently formatted, and free of narrative
// prose on every character sheet checked. Not a Claude call -- deterministic file
// read/find/replace/write, same "no LLM needed, the browser already knows the values"
// reasoning Create Character above uses. Restricted to characters/ (not npcs/) by
// character.js's own UI -- this is a PLAYER's own sheet edit, not an NPC one.
//
// Known, deliberate limitation: some real sheets' `## Current Status` section carries its
// own separate "HP: X / Y" narrative bullet that can already disagree with Combat's line
// (confirmed against this campaign's own real files -- not a hypothetical edge case). This
// feature does not read, write, or reconcile that second line; the DM/Claude still owns
// keeping Current Status accurate via the existing End Session write-back, which -- unlike
// this deterministic patcher -- is a full Claude call actually equipped to merge a change
// into freeform prose sensibly.
const updateCharacterRequestPath = path.join(bridgeDir, "update-character-request.json");
const updateCharacterResponsePath = path.join(bridgeDir, "update-character-response.json");
let lastProcessedUpdateCharacterId = primeLastProcessedId(updateCharacterRequestPath);

// Matches a "- **HP:** 182 / 182" line -- note the closing ** falls AFTER the colon in
// this campaign's real convention (confirmed against actual character files), not after
// "HP" the way it might read at a glance -- with two capture groups so current/max can be
// replaced independently while every other character of the line (bullet style, bold
// markers, whitespace) is preserved exactly.
const HP_LINE_PATTERN = /^(\s*(?:[-*]\s*)?\*{0,2}HP\s*:\s*\*{0,2}\s*)(-?\d+)(\s*\/\s*)(-?\d+)(\s*)$/im;

// Scoped explicitly to the ## Combat section (its own line range, up to the next ## or
// end of file) rather than just taking HP_LINE_PATTERN's first match in the whole
// document -- ## Current Status also carries its own "HP: X / Y" line on a real sheet
// (see the block comment above), and while it currently only happens to fail
// HP_LINE_PATTERN's own shape (a trailing "(full)" the pattern's end anchor rejects), that
// specific text format is not something this code should rely on staying true forever.
// Returns {startLine, endLine} (both indices into a lines array) or null if there's no
// ## Combat heading at all.
function findCombatSectionRange(lines) {
  const start = lines.findIndex((line) => /^##\s+combat\b/i.test(line.trim()));
  if (start === -1) return null;
  let end = lines.length;
  for (let index = start + 1; index < lines.length; index += 1) {
    if (/^##\s+/.test(lines[index])) {
      end = index;
      break;
    }
  }
  return { start, end };
}

function writeUpdateCharacterResponse(id, ok, message) {
  const response = { id, ok, message, respondedAt: new Date().toISOString() };
  writeJsonResponseFile(
    updateCharacterResponsePath,
    response,
    `[dm-bridge] update-character ${id} ${ok ? "succeeded" : "failed"}: ${message}`,
    "update-character-response.json"
  );
}

function handleUpdateCharacterRequest(request) {
  console.log(`[dm-bridge] processing update-character ${request.id}`);
  const dndRepoPath = process.env.DND_REPO_PATH;
  if (!dndRepoPath) {
    writeUpdateCharacterResponse(request.id, false,
      "DND_REPO_PATH isn't set. Stop the watcher, set it to your campaign repo's path (e.g. " +
      "DND_REPO_PATH=/path/to/DND/Campaign node dm-bridge/watch.js), and try again.");
    return;
  }
  if (!fs.existsSync(dndRepoPath)) {
    writeUpdateCharacterResponse(request.id, false, `DND_REPO_PATH is set to "${dndRepoPath}", but that path doesn't exist.`);
    return;
  }

  const fileName = path.basename(String(request.fileName || "").trim());
  if (!fileName.toLowerCase().endsWith(".md")) {
    writeUpdateCharacterResponse(request.id, false, "Character file name must end in .md.");
    return;
  }
  const hp = Number(request.hp);
  const maxHp = Number(request.maxHp);
  if (!Number.isFinite(hp) || !Number.isFinite(maxHp)) {
    writeUpdateCharacterResponse(request.id, false, "HP and max HP must both be numbers.");
    return;
  }

  const targetPath = path.join(dndRepoPath, "characters", fileName);
  if (!fs.existsSync(targetPath)) {
    writeUpdateCharacterResponse(request.id, false, `characters/${fileName} doesn't exist in the campaign repo.`);
    return;
  }

  let text;
  try {
    text = fs.readFileSync(targetPath, "utf8");
  } catch (err) {
    writeUpdateCharacterResponse(request.id, false, `Couldn't read the character file: ${err.message}`);
    return;
  }

  const lines = text.split(/\r?\n/);
  const combatRange = findCombatSectionRange(lines);
  if (!combatRange) {
    writeUpdateCharacterResponse(request.id, false, `characters/${fileName} has no "## Combat" section to update.`);
    return;
  }
  const hpLineIndex = lines.slice(combatRange.start, combatRange.end).findIndex((line) => HP_LINE_PATTERN.test(line));
  if (hpLineIndex === -1) {
    writeUpdateCharacterResponse(request.id, false,
      `Couldn't find a "**HP:** current / max" line in characters/${fileName}'s Combat section -- ` +
      "edit it by hand instead this time.");
    return;
  }

  const targetLineIndex = combatRange.start + hpLineIndex;
  lines[targetLineIndex] = lines[targetLineIndex].replace(HP_LINE_PATTERN, (full, prefix, oldHp, separator, oldMax, suffix) =>
    `${prefix}${hp}${separator}${maxHp}${suffix}`
  );
  const updatedText = lines.join(text.includes("\r\n") ? "\r\n" : "\n");

  try {
    fs.writeFileSync(targetPath, updatedText, "utf8");
  } catch (err) {
    writeUpdateCharacterResponse(request.id, false, `Couldn't write the character file: ${err.message}`);
    return;
  }

  writeUpdateCharacterResponse(request.id, true, `Updated characters/${fileName}: HP ${hp} / ${maxHp}.`);
}

function pollUpdateCharacter() {
  fs.readFile(updateCharacterRequestPath, "utf8", (err, data) => {
    if (!err) {
      try {
        const request = JSON.parse(data);
        if (request.id && request.id !== lastProcessedUpdateCharacterId) {
          lastProcessedUpdateCharacterId = request.id;
          handleUpdateCharacterRequest(request);
        }
      } catch {
        // partial write mid-poll -- try again next tick
      }
    }
    setTimeout(pollUpdateCharacter, 1500);
  });
}

// --- Import Campaign write-back ------------------------------------------------------
//
// Godot's Campaign Browser (Campaign-OS-3D only, ROADMAP.md's "Seven requested features"
// item 4) has no browser FileList/File System Access API to read a folder of campaign
// markdown with -- unlike ui/app.js's own Campaign Browser, which reads one directly via
// engine/campaign.js's importMarkdownFiles(). Same deterministic (no Claude call, no
// cost) write-back-style mailbox as Create/Update Character above, just reading instead
// of writing: recursively walks DND_REPO_PATH for real .md files, wraps each as a small
// object satisfying importMarkdownFiles()'s own duck-typed File interface (it only ever
// calls .name/.webkitRelativePath/.lastModified/.text() on what it's given -- confirmed
// by reading that function directly, not assumed), and returns the exact same parsed
// campaign structure (files/categories) engine/campaign.js already produces for the 2D
// app -- no new parsing logic, just a different way of feeding it real files.
// webkitRelativePath matters, not just name: classify() reads folder segments like
// "characters/"/"npcs/" out of it to sort each file into the right category, so a bare
// filename with no path would misclassify everything as "notes".
//
// engine/campaign.js's own location differs between the two projects this file is kept
// byte-identical across (see sync-engine.sh's own header comment): Campaign-OS has it at
// engine/campaign.js, a sibling of this dm-bridge/ folder; Campaign-OS-3D nests it under
// engine-server/engine/campaign.js instead. Rather than hardcode either path (which would
// silently break in whichever project doesn't use it), loadCampaignEngine() checks both
// candidates and uses whichever actually exists on disk.
function loadCampaignEngine() {
  const candidates = [
    path.join(bridgeDir, "..", "engine", "campaign.js"),
    path.join(bridgeDir, "..", "engine-server", "engine", "campaign.js")
  ];
  const found = candidates.find((candidate) => fs.existsSync(candidate));
  if (!found) return null;
  const code = fs.readFileSync(found, "utf8");
  const engineWindow = {};
  new Function("window", "console", code)(engineWindow, console);
  return engineWindow.CampaignOSCampaign;
}
const CampaignEngine = loadCampaignEngine();

const importCampaignRequestPath = path.join(bridgeDir, "import-campaign-request.json");
const importCampaignResponsePath = path.join(bridgeDir, "import-campaign-response.json");
let lastProcessedImportCampaignId = primeLastProcessedId(importCampaignRequestPath);

function writeImportCampaignResponse(id, ok, message, campaign) {
  const response = { id, ok, message, campaign: campaign || null, respondedAt: new Date().toISOString() };
  writeJsonResponseFile(
    importCampaignResponsePath,
    response,
    `[dm-bridge] import-campaign ${id} ${ok ? "succeeded" : "failed"}: ${message}`,
    "import-campaign-response.json"
  );
}

// Every relative path fs.readdirSync(dir, {recursive: true}) returns is relative to
// `dndRepoPath` already -- exactly the shape webkitRelativePath needs -- so this just
// filters to real .md files (a directory that happens to be named "notes.md" is
// vanishingly unlikely but checked anyway, same defensive spirit as everywhere else
// this file treats "found but not actually a file" as skip-not-crash) and pairs each
// with its absolute path for the actual read.
function listMarkdownFiles(dndRepoPath) {
  return fs.readdirSync(dndRepoPath, { recursive: true })
    .filter((relativePath) => relativePath.toLowerCase().endsWith(".md"))
    .map((relativePath) => ({
      relativePath: relativePath.split(path.sep).join("/"),
      absolutePath: path.join(dndRepoPath, relativePath)
    }))
    .filter(({ absolutePath }) => {
      try {
        return fs.statSync(absolutePath).isFile();
      } catch {
        return false;
      }
    });
}

function handleImportCampaignRequest(request) {
  console.log(`[dm-bridge] processing import-campaign ${request.id}`);
  if (!CampaignEngine) {
    writeImportCampaignResponse(request.id, false,
      "Couldn't load engine/campaign.js on this machine (expected next to dm-bridge/, or under engine-server/engine/).");
    return;
  }
  const dndRepoPath = process.env.DND_REPO_PATH;
  if (!dndRepoPath) {
    writeImportCampaignResponse(request.id, false,
      "DND_REPO_PATH isn't set. Stop the watcher, set it to your campaign repo's path (e.g. " +
      "DND_REPO_PATH=/path/to/DND/Campaign node dm-bridge/watch.js), and try again.");
    return;
  }
  if (!fs.existsSync(dndRepoPath)) {
    writeImportCampaignResponse(request.id, false, `DND_REPO_PATH is set to "${dndRepoPath}", but that path doesn't exist.`);
    return;
  }

  let entries;
  try {
    entries = listMarkdownFiles(dndRepoPath);
  } catch (err) {
    writeImportCampaignResponse(request.id, false, `Couldn't read the campaign repo: ${err.message}`);
    return;
  }

  const fileList = entries.map(({ relativePath, absolutePath }) => {
    let mtimeMs = 0;
    try {
      mtimeMs = fs.statSync(absolutePath).mtimeMs;
    } catch {
      // fall back to 0 -- only used to build a stable-ish id, not load-bearing otherwise
    }
    return {
      name: path.basename(absolutePath),
      webkitRelativePath: relativePath,
      lastModified: mtimeMs,
      text: () => Promise.resolve(fs.readFileSync(absolutePath, "utf8"))
    };
  });

  CampaignEngine.importMarkdownFiles(fileList).then((campaign) => {
    // Pre-computed here (not left for Godot/engine-server to ask for separately later)
    // since tokenDraftFromItem() is a cheap, synchronous, pure function already loaded
    // in this same process -- one less round trip before a DM can actually spawn someone.
    // Mutating item.draft in place is enough: campaign.categories.characters and
    // campaign.files hold the SAME object references per item (see campaign.js's own
    // importMarkdownFiles(), which pushes one item into both arrays), not copies.
    campaign.categories.characters.forEach((item) => {
      item.draft = CampaignEngine.tokenDraftFromItem(item);
    });
    writeImportCampaignResponse(request.id, true, `Imported ${campaign.files.length} file(s) from the campaign repo.`, campaign);
  }).catch((err) => {
    writeImportCampaignResponse(request.id, false, `Import failed: ${err.message}`);
  });
}

function pollImportCampaign() {
  fs.readFile(importCampaignRequestPath, "utf8", (err, data) => {
    if (!err) {
      try {
        const request = JSON.parse(data);
        if (request.id && request.id !== lastProcessedImportCampaignId) {
          lastProcessedImportCampaignId = request.id;
          handleImportCampaignRequest(request);
        }
      } catch {
        // partial write mid-poll -- try again next tick
      }
    }
    setTimeout(pollImportCampaign, 1500);
  });
}

console.log(`[dm-bridge] watching ${requestPath}`);
console.log(`[dm-bridge] model: ${process.env.DM_BRIDGE_MODEL || "haiku"} (override with DM_BRIDGE_MODEL env var)`);
console.log(`[dm-bridge] watching ${endSessionRequestPath}`);
console.log(`[dm-bridge] watching ${createCharacterRequestPath}`);
console.log(`[dm-bridge] watching ${updateCharacterRequestPath}`);
console.log(`[dm-bridge] watching ${importCampaignRequestPath}`);
console.log(`[dm-bridge] DND_REPO_PATH: ${process.env.DND_REPO_PATH || "(not set -- End Session, Create Character, character HP edits, and Campaign Import will fail until this is set)"}`);
poll();
pollEndSession();
pollCreateCharacter();
pollUpdateCharacter();
pollImportCampaign();
