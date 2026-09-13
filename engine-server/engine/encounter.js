(function () {
  const ABILITY_KEYS = ["STR", "DEX", "CON", "INT", "WIS", "CHA"];

  // The canonical 18 5e skills and their governing ability -- duplicated here rather than
  // shared with characterCreator.js's own copy, same convention as CONDITION_LIST/
  // MONSTER_LIST being duplicated between this file and dm-bridge/watch.js (no bundler, no
  // shared-module mechanism across these plain browser/Node scripts).
  const SKILL_LIST = [
    { name: "Acrobatics", ability: "DEX" },
    { name: "Animal Handling", ability: "WIS" },
    { name: "Arcana", ability: "INT" },
    { name: "Athletics", ability: "STR" },
    { name: "Deception", ability: "CHA" },
    { name: "History", ability: "INT" },
    { name: "Insight", ability: "WIS" },
    { name: "Intimidation", ability: "CHA" },
    { name: "Investigation", ability: "INT" },
    { name: "Medicine", ability: "WIS" },
    { name: "Nature", ability: "INT" },
    { name: "Perception", ability: "WIS" },
    { name: "Performance", ability: "CHA" },
    { name: "Persuasion", ability: "CHA" },
    { name: "Religion", ability: "INT" },
    { name: "Sleight of Hand", ability: "DEX" },
    { name: "Stealth", ability: "DEX" },
    { name: "Survival", ability: "WIS" }
  ];

  function findSkill(name) {
    const normalized = String(name || "").trim().toLowerCase();
    return SKILL_LIST.find((skill) => skill.name.toLowerCase() === normalized);
  }

  const conditionList = [
    "Blinded",
    "Charmed",
    "Frightened",
    "Grappled",
    "Invisible",
    "Paralyzed",
    "Poisoned",
    "Prone",
    "Restrained",
    "Stunned",
    "Unconscious"
  ];

  // The 13 SRD damage types -- a reference list for the token sheet's dropdowns (below) and
  // characterCreator.js's weapon field, not an engine-side validation gate: damageTypeModifier
  // matches whatever string an attack profile/token carries case-insensitively, same
  // "freeform, not a closed enum" treatment resource names already get, so a homebrew type
  // typed directly (not through a dropdown) still works for resistance/vulnerability/immunity
  // matching -- it just won't appear pre-listed in the UI.
  const DAMAGE_TYPE_LIST = [
    "acid", "bludgeoning", "cold", "fire", "force", "lightning", "necrotic",
    "piercing", "poison", "psychic", "radiant", "slashing", "thunder"
  ];

  // RAW mechanical hooks for a subset of the conditions above -- attack()/rollSavingThrow()/
  // effectiveSpeed() read these the same way they already read token.exhaustion. Charmed and
  // Frightened are deliberately left descriptive-only (tag only, no automated effect): their
  // real effects depend on a tracked "source" token and line of sight, which this engine has
  // no notion of -- same documented-gap spirit as Troll's Regeneration/Hit Dice elsewhere in
  // this file, not an oversight.
  function hasCondition(token, name) {
    return Array.isArray(token.conditions) && token.conditions.includes(name);
  }

  // Disadvantage/advantage a token's OWN conditions impose on its own attack roll (combines
  // with an explicit options.advantage/disadvantage and exhaustion-3+ using attack()'s
  // existing "any number of each still counts as one, both present cancels to a flat roll"
  // logic -- these two just add more sources on each side of that same cancellation).
  function ownAttackConditionPenalty(token) {
    return hasCondition(token, "Blinded") || hasCondition(token, "Restrained")
      || hasCondition(token, "Prone") || hasCondition(token, "Poisoned");
  }
  function ownAttackConditionBonus(token) {
    return hasCondition(token, "Invisible");
  }

  // Advantage/disadvantage that attacking `target` gets purely from the target's own
  // conditions. Blinded is RAW-bidirectional -- "Attack rolls against the creature have
  // advantage, and the creature's attack rolls have disadvantage" -- so it belongs on BOTH
  // this function and ownAttackConditionPenalty above, not just the latter (an earlier
  // version of this file only modeled the self-penalty half; verified against the SRD's
  // Conditions appendix).
  function targetGrantsAttackAdvantage(target) {
    return hasCondition(target, "Restrained") || hasCondition(target, "Prone")
      || hasCondition(target, "Stunned") || hasCondition(target, "Paralyzed")
      || hasCondition(target, "Unconscious") || hasCondition(target, "Blinded");
  }
  function targetGrantsAttackDisadvantage(target) {
    return hasCondition(target, "Invisible");
  }

  // RAW: any hit against a Paralyzed or Unconscious target from an attacker within 5 ft is an
  // automatic critical hit, not just advantage on the roll to get there. `isAdjacent` is a
  // one-square (5 ft) proxy for "melee range" -- this engine has no melee/ranged distinction
  // on attack profiles, so a ranged attack from an adjacent square is treated the same as a
  // melee one; a documented simplification, not a RAW-accurate melee check.
  function isAdjacent(a, b) {
    return Math.max(Math.abs(a.x - b.x), Math.abs(a.y - b.y)) <= 1;
  }
  function forcesAutoCrit(target) {
    return hasCondition(target, "Paralyzed") || hasCondition(target, "Unconscious");
  }

  // SRD 5.1 stat blocks for the monsters `parseCommand`'s spawn phrasing recognizes
  // (see monsterPattern below). attackBonus/damageDice reflect the monster's primary
  // attack for single-attack resolution and the token sheet's editable fields; `attacks`
  // (when present) lists every attack a Multiattack action makes, consumed by attack()
  // below. `initiativeMod` is the monster's real Dex modifier, not a flat guess -- same
  // number as abilityScores.DEX's modifier, kept as its own field since it predates
  // ability scores being modeled at all. None of these have a stated saving throw
  // proficiency in the SRD, so their saves fall back to a flat ability modifier (see
  // savingThrowBonus) -- no `savingThrows` override needed. None carry spellcasting either
  // (Priest/Mage-style SRD casters would need it, but every monster below is a
  // straightforward melee attacker, matching the original six). `regeneration`/
  // `rechargeAbilities` (see nextTurn()) are set on the two monsters that have them --
  // Pack Tactics is still NOT automated below (it needs to know whether an ally is
  // adjacent to the same target, which attack() has no notion of); set advantage by hand
  // when that condition is actually met. `xp` (added Phase 14, 2026-08-22, one real SRD
  // value per monster, page-checked the same way the stat blocks themselves were) is each
  // monster's own published XP value -- read by `evaluateEncounterDifficulty()` below, not
  // copied onto a spawned token (nothing about combat resolution needs it, only the
  // difficulty calculator does, and it looks the name back up in this table directly).
  const STAT_BLOCKS = {
    // Hell Hound (added after checking the real campaign's session log -- its one actual
    // non-humanoid encounter, three hellhounds guarding a market entrance; everything else
    // fought was generic human guards, already covered by `bandit`). Bite RAW deals two
    // damage types in one hit (1d8+3 piercing plus 2d6 fire); damageDice here is a single
    // dice notation, and tagging the combined roll with either type alone would misrepresent
    // it for a creature resistant/immune to only one of the two (see damageTypeModifier), so
    // it's left untyped -- approximated as one combined roll (avg ~14.5, matching 1d8+3 + 2d6)
    // rather than dropping either component. Fire Breath (15 ft cone, DC 12 DEX save, 6d6 fire/half) now
    // has a real path end to end: rechargeAbilities tracks whether it's available (roll a
    // d6 >= 5 at the start of the hell hound's turn, per nextTurn()), use_recharge_ability
    // spends it, and cast_area_spell (or the equivalent local command) resolves the actual
    // damage/save against whichever tokens are caught in it -- Claude/the DM still decides
    // which tokens that is, since this engine has no area-of-effect geometry (no cone/blast
    // shape against the grid), just the dice-and-save resolution once targets are named.
    hellhound: {
      hp: 45, ac: 15, attackBonus: 5, damageDice: "4d6+1", initiativeMod: 1, speed: 50, xp: 700,
      abilityScores: { STR: 17, DEX: 12, CON: 14, INT: 6, WIS: 13, CHA: 6 },
      rechargeAbilities: { "Fire Breath": { rechargeMin: 5, available: true } }
    },
    goblin: {
      hp: 7, ac: 15, attackBonus: 4, damageDice: "1d6+2", damageType: "slashing", initiativeMod: 2, speed: 30, xp: 50,
      abilityScores: { STR: 8, DEX: 14, CON: 10, INT: 10, WIS: 8, CHA: 8 }
    },
    orc: {
      hp: 15, ac: 13, attackBonus: 5, damageDice: "1d12+3", damageType: "slashing", initiativeMod: 1, speed: 30, xp: 100,
      abilityScores: { STR: 16, DEX: 12, CON: 16, INT: 7, WIS: 11, CHA: 10 }
    },
    wolf: {
      hp: 11, ac: 13, attackBonus: 4, damageDice: "2d4+2", damageType: "piercing", initiativeMod: 2, speed: 40, xp: 50,
      abilityScores: { STR: 12, DEX: 15, CON: 12, INT: 3, WIS: 12, CHA: 6 }
    },
    bandit: {
      hp: 11, ac: 12, attackBonus: 3, damageDice: "1d6+1", damageType: "slashing", initiativeMod: 1, speed: 30, xp: 25,
      abilityScores: { STR: 11, DEX: 12, CON: 12, INT: 10, WIS: 10, CHA: 10 }
    },
    // Regeneration (10 HP at the start of its turn "unless it took acid or fire damage
    // since its last turn") is handled by nextTurn() -- the acid/fire exception still isn't
    // modeled, even now that damage types are tracked elsewhere: it needs "did this token
    // take type X since its LAST turn," a per-turn damage-type history nextTurn() has no
    // notion of (damageTypeModifier only sees one hit at a time, at the moment it lands), a
    // different problem from resistance/vulnerability/immunity; skip issuing the heal by hand
    // (via the token editor) on a turn where that exception should apply.
    troll: {
      hp: 84,
      ac: 15,
      attackBonus: 7,
      damageDice: "1d6+4",
      // Real SRD Dex is 13 (+1 mod) -- fixing a pre-existing -1 here alongside adding the
      // full ability block, since the two were clearly meant to be the same number.
      initiativeMod: 1,
      speed: 30,
      xp: 1800,
      abilityScores: { STR: 18, DEX: 13, CON: 20, INT: 7, WIS: 9, CHA: 7 },
      regeneration: { amount: 10 },
      attacks: [
        { name: "Bite", attackBonus: 7, damageDice: "1d6+4", damageType: "piercing" },
        { name: "Claw", attackBonus: 7, damageDice: "2d6+4", damageType: "slashing" },
        { name: "Claw", attackBonus: 7, damageDice: "2d6+4", damageType: "slashing" }
      ]
    },
    // Vulnerability to bludgeoning damage IS modeled now that damage types are tracked --
    // resistance/vulnerability/immunity checks against a token's damageVulnerabilities list.
    skeleton: {
      hp: 13, ac: 13, attackBonus: 4, damageDice: "1d6+2", damageType: "piercing", initiativeMod: 2, speed: 30, xp: 50,
      abilityScores: { STR: 10, DEX: 14, CON: 15, INT: 6, WIS: 8, CHA: 5 },
      damageVulnerabilities: ["bludgeoning"]
    },
    // Undead Fortitude (a failed CON save lets it drop to 1 HP instead of 0, unless the
    // killing damage was radiant or a critical hit) still isn't automated -- applyDamage has
    // no notion of "this specific hit" to key a save off of separately from the death-save
    // machinery it already runs, even though damage type itself is now tracked; apply it by
    // hand.
    zombie: {
      hp: 22, ac: 8, attackBonus: 3, damageDice: "1d6+1", damageType: "bludgeoning", initiativeMod: -2, speed: 20, xp: 50,
      abilityScores: { STR: 13, DEX: 6, CON: 16, INT: 3, WIS: 6, CHA: 5 }
    },
    // Ghoul's Claws (the second Multiattack hit) also inflict paralysis on a failed CON
    // save (elves immune) -- not automated, since there's no per-attack rider mechanic here;
    // issue a separate saving_throw + toggle_condition("Paralyzed") by hand if it hits.
    ghoul: {
      hp: 22, ac: 12, attackBonus: 2, damageDice: "2d6+2", initiativeMod: 2, speed: 30, xp: 200,
      abilityScores: { STR: 13, DEX: 15, CON: 10, INT: 7, WIS: 10, CHA: 6 },
      attacks: [
        { name: "Bite", attackBonus: 2, damageDice: "2d6+2", damageType: "piercing" },
        { name: "Claws", attackBonus: 4, damageDice: "2d4+2", damageType: "slashing" }
      ]
    },
    ogre: {
      hp: 59, ac: 11, attackBonus: 6, damageDice: "2d8+4", damageType: "bludgeoning", initiativeMod: -1, speed: 40, xp: 450,
      abilityScores: { STR: 19, DEX: 8, CON: 16, INT: 5, WIS: 7, CHA: 7 }
    },
    owlbear: {
      hp: 59, ac: 13, attackBonus: 7, damageDice: "1d10+5", initiativeMod: 1, speed: 40, xp: 700,
      abilityScores: { STR: 20, DEX: 12, CON: 17, INT: 3, WIS: 12, CHA: 7 },
      attacks: [
        { name: "Beak", attackBonus: 7, damageDice: "1d10+5", damageType: "piercing" },
        { name: "Claws", attackBonus: 7, damageDice: "2d8+5", damageType: "slashing" }
      ]
    },
    worg: {
      hp: 26, ac: 13, attackBonus: 5, damageDice: "2d6+3", damageType: "piercing", initiativeMod: 1, speed: 50, xp: 100,
      abilityScores: { STR: 16, DEX: 13, CON: 13, INT: 7, WIS: 11, CHA: 8 }
    },
    // Bite RAW deals two damage types in one hit (1d8+3 piercing plus 2d8 poison) plus a
    // DC 11 CON save or poisoned -- same combined-single-roll approximation the hell hound's
    // Bite above uses, so it's left untyped here too (tagging it as either piercing or poison
    // alone would misrepresent it for a creature resistant/immune to only one of the two), and
    // the poisoned-on-hit rider isn't automated for the same reason ghoul's paralysis rider
    // isn't.
    "giant spider": {
      hp: 26, ac: 14, attackBonus: 5, damageDice: "3d8+4", initiativeMod: 3, speed: 30, xp: 200,
      abilityScores: { STR: 14, DEX: 16, CON: 12, INT: 2, WIS: 11, CHA: 4 }
    },
    cultist: {
      hp: 9, ac: 12, attackBonus: 3, damageDice: "1d6+1", damageType: "slashing", initiativeMod: 1, speed: 30, xp: 25,
      abilityScores: { STR: 11, DEX: 12, CON: 10, INT: 10, WIS: 11, CHA: 10 }
    },
    guard: {
      hp: 11, ac: 16, attackBonus: 3, damageDice: "1d6+1", damageType: "piercing", initiativeMod: 1, speed: 30, xp: 25,
      abilityScores: { STR: 13, DEX: 12, CON: 12, INT: 10, WIS: 11, CHA: 10 }
    },
    // The SRD Priest also has Channel Divinity/Spiritual Weapon-style spellcasting -- not
    // modeled here, same "melee stat line only" simplification noted where STAT_BLOCKS is
    // introduced above; only its Mace attack is represented.
    priest: {
      hp: 27, ac: 13, attackBonus: 2, damageDice: "1d6", damageType: "bludgeoning", initiativeMod: 0, speed: 30, xp: 450,
      abilityScores: { STR: 10, DEX: 10, CON: 12, INT: 13, WIS: 16, CHA: 13 }
    },
    // The eight below (Phase 13, 2026-08-22) were transcribed directly from the System
    // Reference Document PDF at I:\DND\Core Rulebooks\SRD (page-checked, not guessed --
    // see ROADMAP.md's Phase 13 for the "extract as needed, verify against a real page"
    // approach this follows), chosen to fill real gaps in the original 16 rather than as a
    // bulk dump: a raider tier above goblin/orc (bugbear, hobgoblin, gnoll), the first
    // incorporeal undead (specter -- skeleton/zombie/ghoul are all corporeal), the first
    // low-tier fiend distinct from Malphestor's own custom-authored NPC sheet (imp), a
    // generic elite humanoid NPC (veteran, the natural step up from guard/cultist/priest),
    // and a bear (brown bear/dire wolf -- thematically relevant to this campaign's
    // bear-kin/bear-spirit motif per the paired DnD repo's session log, and a genuine gap:
    // no beast-type monster existed in STAT_BLOCKS at all before these two).
    "brown bear": {
      hp: 34, ac: 11, attackBonus: 5, damageDice: "1d8+4", damageType: "piercing", initiativeMod: 0, speed: 40, xp: 200,
      abilityScores: { STR: 19, DEX: 10, CON: 16, INT: 2, WIS: 13, CHA: 7 },
      attacks: [
        { name: "Bite", attackBonus: 5, damageDice: "1d8+4", damageType: "piercing" },
        { name: "Claws", attackBonus: 5, damageDice: "2d6+4", damageType: "slashing" }
      ]
    },
    "dire wolf": {
      hp: 37, ac: 14, attackBonus: 5, damageDice: "2d6+3", damageType: "piercing", initiativeMod: 2, speed: 50, xp: 200,
      abilityScores: { STR: 17, DEX: 15, CON: 15, INT: 3, WIS: 12, CHA: 7 }
    },
    bugbear: {
      hp: 27, ac: 16, attackBonus: 4, damageDice: "2d8+2", damageType: "piercing", initiativeMod: 2, speed: 30, xp: 200,
      abilityScores: { STR: 15, DEX: 14, CON: 13, INT: 8, WIS: 11, CHA: 9 }
    },
    hobgoblin: {
      hp: 11, ac: 18, attackBonus: 3, damageDice: "1d8+1", damageType: "slashing", initiativeMod: 1, speed: 30, xp: 100,
      abilityScores: { STR: 13, DEX: 12, CON: 12, INT: 10, WIS: 10, CHA: 9 }
    },
    gnoll: {
      hp: 22, ac: 15, attackBonus: 4, damageDice: "1d4+2", damageType: "piercing", initiativeMod: 1, speed: 30, xp: 100,
      abilityScores: { STR: 14, DEX: 12, CON: 11, INT: 6, WIS: 10, CHA: 7 }
    },
    // Incorporeal Movement and Sunlight Sensitivity aren't modeled (same "no per-attack/
    // per-trait mechanic to hook into yet" spirit as Ghoul's paralysis rider above) --
    // apply them by hand. Speed is a flat 50 (its only real movement -- 0 ft. ground, fly
    // 50 ft. hover -- this engine has one speed field, not a per-mode set, same
    // simplification every other flier here already uses).
    specter: {
      hp: 22, ac: 12, attackBonus: 4, damageDice: "3d6", damageType: "necrotic", initiativeMod: 2, speed: 50, xp: 200,
      abilityScores: { STR: 1, DEX: 14, CON: 11, INT: 10, WIS: 10, CHA: 11 },
      damageResistances: ["acid", "cold", "fire", "lightning", "thunder"],
      damageImmunities: ["necrotic", "poison"]
    },
    // Sting also deals 10 (3d6) poison damage on a failed DC 11 CON save (half on success)
    // on top of the flat piercing hit modeled here -- not automated, same unmodeled-rider
    // convention as Ghoul's paralysis/Giant Spider's poison above. Shapechanger/
    // Invisibility (its other real tools) aren't modeled either, same "melee stat line
    // only" simplification the SRD Priest note above already documents.
    imp: {
      hp: 10, ac: 13, attackBonus: 5, damageDice: "1d4+3", damageType: "piercing", initiativeMod: 3, speed: 20, xp: 200,
      abilityScores: { STR: 6, DEX: 17, CON: 13, INT: 11, WIS: 12, CHA: 14 },
      damageResistances: ["cold"],
      damageImmunities: ["fire", "poison"]
    },
    // Multiattack is RAW two Longsword hits, plus an optional third Shortsword attack
    // "if it has a shortsword drawn" -- an equipment-state choice this engine has no
    // notion of, so only the guaranteed two-Longsword baseline is modeled here, same
    // "model the default Multiattack, not every optional variant" precedent Troll/Ghoul/
    // Owlbear already set.
    veteran: {
      hp: 58, ac: 17, attackBonus: 5, damageDice: "1d8+3", damageType: "slashing", initiativeMod: 1, speed: 30, xp: 700,
      abilityScores: { STR: 16, DEX: 13, CON: 14, INT: 10, WIS: 11, CHA: 10 },
      attacks: [
        { name: "Longsword", attackBonus: 5, damageDice: "1d8+3", damageType: "slashing" },
        { name: "Longsword", attackBonus: 5, damageDice: "1d8+3", damageType: "slashing" }
      ]
    }
  };
  // Safety net for a monster name that reaches spawnMonster without a STAT_BLOCKS entry
  // (not reachable through parseCommand today, since monsterPattern only matches the
  // names above, but spawnMonster itself doesn't enforce that).
  const GENERIC_STAT_BLOCK = {
    hp: 10, ac: 13, attackBonus: 3, damageDice: "1d8+1", initiativeMod: 2, speed: 30,
    abilityScores: { STR: 10, DEX: 10, CON: 10, INT: 10, WIS: 10, CHA: 10 }
  };

  // DMG "XP Thresholds by Character Level" table (Chapter 3, Combat Encounter Difficulty),
  // transcribed directly from the Dungeon Master's Guide PDF at I:\DND\Core Rulebooks
  // rather than approximated -- Phase 14's roadmap note flagged "how strictly to follow
  // the DMG's budget math vs. a looser approximation" as an open question; having the
  // real table on hand settled it in favor of the real thing. Keyed by character level
  // 1-20 (not 0-indexed); each entry is that one character's own XP budget per difficulty
  // tier, added up across the whole party by evaluateEncounterDifficulty() below.
  const XP_THRESHOLDS_BY_LEVEL = {
    1: { easy: 25, medium: 50, hard: 75, deadly: 100 },
    2: { easy: 50, medium: 100, hard: 150, deadly: 200 },
    3: { easy: 75, medium: 150, hard: 225, deadly: 400 },
    4: { easy: 125, medium: 250, hard: 375, deadly: 500 },
    5: { easy: 250, medium: 500, hard: 750, deadly: 1100 },
    6: { easy: 300, medium: 600, hard: 900, deadly: 1400 },
    7: { easy: 350, medium: 750, hard: 1100, deadly: 1700 },
    8: { easy: 450, medium: 900, hard: 1400, deadly: 2100 },
    9: { easy: 550, medium: 1100, hard: 1600, deadly: 2400 },
    10: { easy: 600, medium: 1200, hard: 1900, deadly: 2800 },
    11: { easy: 800, medium: 1600, hard: 2400, deadly: 3600 },
    12: { easy: 1000, medium: 2000, hard: 3000, deadly: 4500 },
    13: { easy: 1100, medium: 2200, hard: 3400, deadly: 5100 },
    14: { easy: 1250, medium: 2500, hard: 3800, deadly: 5700 },
    15: { easy: 1400, medium: 2800, hard: 4300, deadly: 6400 },
    16: { easy: 1600, medium: 3200, hard: 4800, deadly: 7200 },
    17: { easy: 2000, medium: 3900, hard: 5900, deadly: 8800 },
    18: { easy: 2100, medium: 4200, hard: 6300, deadly: 9500 },
    19: { easy: 2400, medium: 4900, hard: 7300, deadly: 10900 },
    20: { easy: 2800, medium: 5700, hard: 8500, deadly: 12700 }
  };

  // DMG "Encounter Multipliers" table -- the more monsters in a fight, the more attack
  // rolls happen per round regardless of their individual XP total, so the DMG scales the
  // monsters' combined XP up before comparing it to the party's thresholds. Ladder order
  // matters: the "Party Size" adjustment just below steps one tier up/down this same list.
  const ENCOUNTER_MULTIPLIER_STEPS = [0.5, 1, 1.5, 2, 2.5, 3, 4];
  function baseEncounterMultiplier(monsterCount) {
    if (monsterCount <= 1) return 1;
    if (monsterCount === 2) return 1.5;
    if (monsterCount <= 6) return 2;
    if (monsterCount <= 10) return 2.5;
    if (monsterCount <= 14) return 3;
    return 4;
  }
  // DMG "Party Size" note: the multiplier table above assumes 3-5 PCs. Fewer than 3 steps
  // UP one tier (a small party feels a given monster count's action economy harder); 6 or
  // more steps DOWN one tier (a big party spreads the same monster actions thinner) --
  // including the DMG's own explicit example, a 0.5 multiplier for a single monster against
  // 6+ PCs, which only exists via this adjustment (0.5 is never a monster-count tier on its
  // own). Clamped at both ends of ENCOUNTER_MULTIPLIER_STEPS rather than stepping past it.
  function encounterMultiplier(monsterCount, partySize) {
    const base = baseEncounterMultiplier(monsterCount);
    const index = ENCOUNTER_MULTIPLIER_STEPS.indexOf(base);
    if (partySize > 0 && partySize < 3) return ENCOUNTER_MULTIPLIER_STEPS[Math.min(index + 1, ENCOUNTER_MULTIPLIER_STEPS.length - 1)];
    if (partySize >= 6) return ENCOUNTER_MULTIPLIER_STEPS[Math.max(index - 1, 0)];
    return base;
  }

  // A hero token's true class level isn't tracked as a single number anywhere else in this
  // engine -- ability scores/spellcasting/resources all vary too much per class to reduce
  // to one field, the same reason this file's other "trust the sheet" fields exist. Hit
  // Dice pools come closest for free: one Hit Die per character level is a fixed 5e rule
  // (RAW) regardless of class or multiclass split, unlike everything else on a sheet, so
  // summing every hitDice[dieType].total already gives the real total character level with
  // no new extraction needed. A hero token with no Hit Dice pool at all (added by hand, or
  // imported without the campaign markdown's Class & Level line) falls back to level 1 --
  // a documented simplification, not a guess at their actual level; edit the party
  // manually in that case by giving that token a Hit Dice entry.
  function partyLevelFromToken(token) {
    if (!token.hitDice) return 1;
    const total = Object.values(token.hitDice).reduce((sum, pool) => sum + (pool.total || 0), 0);
    return clampNumber(total || 1, 1, 20);
  }

  // Looks a monster token's XP up the same way spawnMonster's own baseName does -- strip a
  // spawned instance's trailing number, lowercase, look up STAT_BLOCKS. A monster token
  // that didn't come from spawnMonster (an imported NPC sheet, a hand-added or renamed
  // token, a monster spawned before this field existed) has no known XP and is reported
  // separately by evaluateEncounterDifficulty() rather than guessed -- the same "don't
  // invent a number" rule the damage resistance/vulnerability fields already follow.
  function monsterXpFromToken(token) {
    const key = token.name.trim().toLowerCase().replace(/\s+\d+$/, "");
    const stats = STAT_BLOCKS[key];
    return stats && typeof stats.xp === "number" ? stats.xp : null;
  }

  // The actual DMG "Evaluating Encounter Difficulty" procedure (steps 1-5, Chapter 3),
  // read straight off the current encounter -- hero-type tokens on the active map are the
  // party, monster-type tokens are the encounter, both filtered to exclude anything already
  // `dead` (a defeated monster shouldn't count toward difficulty; a `dying`-but-not-dead
  // hero still does, since they're still part of the party's resource pool this is
  // measuring against). Deliberately a read-only query, not a {state, message} mutator --
  // same shape as effectiveSpeed()/damageTypeModifier()/savingThrowBonus() above, since
  // nothing here changes state.
  function evaluateEncounterDifficulty(state) {
    const tokens = tokensOnCurrentMap(state).filter((token) => !token.dead);
    const heroes = tokens.filter((token) => token.type === "hero");
    const monsters = tokens.filter((token) => token.type === "monster");

    const partyLevels = heroes.map(partyLevelFromToken);
    const thresholds = partyLevels.reduce(
      (totals, level) => {
        const row = XP_THRESHOLDS_BY_LEVEL[level];
        return {
          easy: totals.easy + row.easy,
          medium: totals.medium + row.medium,
          hard: totals.hard + row.hard,
          deadly: totals.deadly + row.deadly
        };
      },
      { easy: 0, medium: 0, hard: 0, deadly: 0 }
    );

    const unratedMonsterNames = [];
    const monsterXpTotal = monsters.reduce((sum, token) => {
      const xp = monsterXpFromToken(token);
      if (xp === null) {
        unratedMonsterNames.push(token.name);
        return sum;
      }
      return sum + xp;
    }, 0);

    const multiplier = encounterMultiplier(monsters.length, heroes.length);
    const adjustedXp = Math.round(monsterXpTotal * multiplier);

    // "Compare XP... the threshold that equals the adjusted XP value determines the
    // encounter's difficulty. If there's no match, use the closest threshold that is
    // lower than the adjusted XP value" -- checked highest-first so an adjusted XP past
    // Deadly still reports Deadly (there's no tier above it), not falls through unmatched.
    let difficulty = "Trivial";
    if (thresholds.deadly > 0 && adjustedXp >= thresholds.deadly) difficulty = "Deadly";
    else if (thresholds.hard > 0 && adjustedXp >= thresholds.hard) difficulty = "Hard";
    else if (thresholds.medium > 0 && adjustedXp >= thresholds.medium) difficulty = "Medium";
    else if (thresholds.easy > 0 && adjustedXp >= thresholds.easy) difficulty = "Easy";

    return {
      heroCount: heroes.length,
      partyLevels,
      thresholds,
      monsterCount: monsters.length,
      monsterXpTotal,
      multiplier,
      adjustedXp,
      unratedMonsterNames,
      difficulty
    };
  }

  const initialState = {
    mapName: "",
    maps: {},
    selectedTokenId: null,
    log: [],
    tokens: [],
    // The active turn tracker. tokenId is null when no encounter turn order is running
    // (free positioning/scene-setting outside combat); round starts at 1 once nextTurn()
    // is first called. Movement speed limits (see moveToken) only apply to whichever token
    // this currently points at -- everything else can still be freely repositioned.
    turn: { tokenId: null, round: 0 }
  };

  function clone(value) {
    return JSON.parse(JSON.stringify(value));
  }

  function createState() {
    return clone(initialState);
  }

  function sortByInitiative(tokens) {
    return [...tokens].sort((a, b) => b.initiative - a.initiative || a.name.localeCompare(b.name));
  }

  function tokensOnCurrentMap(state) {
    return state.tokens.filter((token) => token.mapName === state.mapName);
  }

  function occupied(state, x, y) {
    return tokensOnCurrentMap(state).some((token) => token.x === x && token.y === y);
  }

  function findOpenTile(state, startX, startY) {
    const queue = [{ x: startX, y: startY }];
    const seen = new Set();

    while (queue.length) {
      const current = queue.shift();
      const key = `${current.x},${current.y}`;
      if (seen.has(key)) continue;
      seen.add(key);

      const grid = currentGrid(state);
      if (current.x >= 1 && current.x <= grid.columns && current.y >= 1 && current.y <= grid.rows && !occupied(state, current.x, current.y)) {
        return current;
      }

      queue.push(
        { x: current.x + 1, y: current.y },
        { x: current.x - 1, y: current.y },
        { x: current.x, y: current.y + 1 },
        { x: current.x, y: current.y - 1 }
      );
    }

    return { x: 1, y: 1 };
  }

  function nextMonsterNumber(state, baseName) {
    const matcher = new RegExp(`^${baseName} (\\d+)$`, "i");
    return state.tokens.reduce((highest, token) => {
      const match = token.name.match(matcher);
      return match ? Math.max(highest, Number(match[1])) : highest;
    }, 0) + 1;
  }

  function spawnMonster(state, monsterName, count) {
    const nextState = clone(state);
    const spawned = [];
    const baseName = monsterName.charAt(0).toUpperCase() + monsterName.slice(1).toLowerCase();
    const stats = STAT_BLOCKS[monsterName.toLowerCase()] || GENERIC_STAT_BLOCK;

    for (let index = 0; index < count; index += 1) {
      const number = nextMonsterNumber(nextState, baseName);
      const tile = findOpenTile(nextState, 7 + index, 3 + index);
      const token = {
        id: `${monsterName.toLowerCase()}-${Date.now()}-${index}`,
        name: `${baseName} ${number}`,
        icon: baseName.slice(0, 2).toUpperCase(),
        type: "monster",
        mapName: nextState.mapName,
        x: tile.x,
        y: tile.y,
        hp: stats.hp,
        maxHp: stats.hp,
        ac: stats.ac,
        attackBonus: stats.attackBonus,
        damageDice: stats.damageDice,
        speed: stats.speed,
        movementUsed: 0,
        diagonalStepsThisTurn: 0,
        initiative: rollDie(20) + stats.initiativeMod,
        conditions: [],
        abilityScores: { ...stats.abilityScores }
      };
      if (stats.attacks) token.attacks = stats.attacks;
      if (stats.damageType) token.damageType = stats.damageType;
      if (stats.damageResistances) token.damageResistances = [...stats.damageResistances];
      if (stats.damageVulnerabilities) token.damageVulnerabilities = [...stats.damageVulnerabilities];
      if (stats.damageImmunities) token.damageImmunities = [...stats.damageImmunities];
      if (stats.regeneration) token.regeneration = { ...stats.regeneration };
      if (stats.rechargeAbilities) {
        token.rechargeAbilities = Object.fromEntries(
          Object.entries(stats.rechargeAbilities).map(([name, ability]) => [name, { ...ability }])
        );
      }
      nextState.tokens.push(token);
      spawned.push(token);
    }

    nextState.selectedTokenId = spawned[0]?.id || nextState.selectedTokenId;
    return { state: nextState, spawned };
  }

  function addToken(state, draft) {
    const nextState = clone(state);
    const tile = findOpenTile(nextState, 4, 4);
    const token = {
      id: `${slugify(draft.name || "token")}-${Date.now()}`,
      name: draft.name || "Campaign Token",
      icon: draft.icon || String(draft.name || "CT").slice(0, 2).toUpperCase(),
      type: draft.type || "hero",
      mapName: nextState.mapName,
      x: tile.x,
      y: tile.y,
      hp: clampNumber(draft.hp ?? draft.maxHp ?? 10, 0, 999),
      maxHp: clampNumber(draft.maxHp ?? draft.hp ?? 10, 1, 999),
      ac: clampNumber(draft.ac ?? 12, 1, 99),
      attackBonus: clampNumber(draft.attackBonus ?? 3, -20, 99),
      damageDice: draft.damageDice || "1d6+1",
      speed: clampNumber(draft.speed ?? 30, 0, 999),
      movementUsed: 0,
      diagonalStepsThisTurn: 0,
      initiative: clampNumber(draft.initiative ?? rollDie(20), 0, 99),
      conditions: draft.conditions || [],
      sourcePath: draft.sourcePath || ""
    };
    if (Array.isArray(draft.attacks) && draft.attacks.length > 1) token.attacks = draft.attacks;
    // Sparse, absent (visible) by default -- excluded from the read-only player window's map
    // and initiative list entirely when true (see ui/playerView.js), for a secret monster or
    // an NPC not yet revealed. Does NOT retroactively (or prospectively) redact the token's
    // name out of freeform combat log text -- that's a known, documented gap, not an oversight.
    if (draft.hiddenFromPlayers) token.hiddenFromPlayers = true;
    if (typeof draft.damageType === "string" && draft.damageType.trim()) {
      token.damageType = draft.damageType.trim().toLowerCase();
    }
    const damageResistances = normalizeDamageTypeList(draft.damageResistances);
    if (damageResistances) token.damageResistances = damageResistances;
    const damageVulnerabilities = normalizeDamageTypeList(draft.damageVulnerabilities);
    if (damageVulnerabilities) token.damageVulnerabilities = damageVulnerabilities;
    const damageImmunities = normalizeDamageTypeList(draft.damageImmunities);
    if (damageImmunities) token.damageImmunities = damageImmunities;
    const abilityScores = normalizeAbilityScores(draft.abilityScores);
    if (abilityScores) token.abilityScores = abilityScores;
    const savingThrows = normalizeSavingThrows(draft.savingThrows);
    if (savingThrows) token.savingThrows = savingThrows;
    const skills = normalizeSkills(draft.skills);
    if (skills) token.skills = skills;
    const spellcasting = normalizeSpellcasting(draft.spellcasting);
    if (spellcasting) token.spellcasting = spellcasting;
    const spellSlots = normalizeSpellSlots(draft.spellSlots);
    if (spellSlots) token.spellSlots = spellSlots;
    const resources = normalizeResources(draft.resources);
    if (resources) token.resources = resources;
    const hitDice = normalizeHitDice(draft.hitDice);
    if (hitDice) token.hitDice = hitDice;
    const legendaryActions = normalizeLegendaryActions(draft.legendaryActions);
    if (legendaryActions) token.legendaryActions = legendaryActions;
    const rechargeAbilities = normalizeRechargeAbilities(draft.rechargeAbilities);
    if (rechargeAbilities) token.rechargeAbilities = rechargeAbilities;
    if (draft.regeneration && Number.isFinite(Number(draft.regeneration.amount)) && Number(draft.regeneration.amount) > 0) {
      token.regeneration = { amount: clampNumber(draft.regeneration.amount, 1, 999) };
    }
    // How many additional attacks attack() allows in one action-consuming call before the
    // action is spent (RAW Extra Attack) -- sparse, absent/0 for anything without it.
    if (Number.isFinite(Number(draft.extraAttacks)) && Number(draft.extraAttacks) > 0) {
      token.extraAttacks = clampNumber(draft.extraAttacks, 1, 10);
    }
    // Max sight distance in feet for a hero-type token (cellVisibleToHero) -- sparse,
    // absent/unset means unlimited. Meaningless on a non-hero token today (only hero vision
    // drives what the player window reveals), but not restricted to type "hero" here, in case
    // a token later changes type or the field turns out useful elsewhere.
    if (Number.isFinite(Number(draft.visionRange)) && Number(draft.visionRange) > 0) {
      token.visionRange = clampNumber(draft.visionRange, 1, 999);
    }
    token.hp = clampNumber(token.hp, 0, token.maxHp);
    nextState.tokens.push(token);
    nextState.selectedTokenId = token.id;
    return { state: nextState, token };
  }

  function slugify(value) {
    return String(value).toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "") || "token";
  }

  function rollDie(sides) {
    return Math.floor(Math.random() * sides) + 1;
  }

  function rollDice(notation) {
    const match = String(notation).trim().match(/^(\d*)d(\d+)([+-]\d+)?$/i);
    if (!match) return { total: 0, rolls: [], modifier: 0, notation };

    const count = Number(match[1] || 1);
    const sides = Number(match[2]);
    const modifier = Number(match[3] || 0);
    const rolls = [];
    for (let index = 0; index < count; index += 1) {
      rolls.push(rollDie(sides));
    }

    return {
      total: rolls.reduce((sum, roll) => sum + roll, 0) + modifier,
      rolls,
      modifier,
      notation
    };
  }

  // A freeform, DM-facing roll not tied to any token or action -- a trap, a random table, loot
  // -- reusing rollDice's own NdM[+-K] parsing rather than a second parser. Unlike the other
  // self-logging rolls (rollDeathSave, rollSavingThrow, ...) there's no pass/fail or target to
  // report against, just the breakdown, so the message is the roll itself. Fails outright (same
  // `state` reference, no clone, no log entry) for anything that doesn't parse as dice notation.
  function rollFreeform(state, notation) {
    const result = rollDice(notation);
    if (!result.rolls.length) {
      return { state, message: `Couldn't parse "${notation}" as dice (expected something like 3d6+2).` };
    }
    const modifierText = result.modifier ? ` ${result.modifier > 0 ? "+" : "-"} ${Math.abs(result.modifier)}` : "";
    const message = `Rolled ${result.notation}: [${result.rolls.join(", ")}]${modifierText} = ${result.total}.`;
    return { state: addLogEntry(state, message), message, total: result.total };
  }

  function normalizeAbilityScores(raw) {
    if (!raw || typeof raw !== "object") return undefined;
    const scores = {};
    let any = false;
    ABILITY_KEYS.forEach((key) => {
      const value = Number(raw[key]);
      if (Number.isFinite(value)) {
        scores[key] = clampNumber(value, 1, 30);
        any = true;
      }
    });
    return any ? scores : undefined;
  }

  // A stated saving-throw bonus (parsed from a real character sheet's "Saving throws:"
  // line, e.g. "Wisdom +6 (Resilient, lvl Fighter 4)") is stored as-is rather than
  // recomputed from ability score + proficiency bonus -- real sheets accumulate feats,
  // multiclass bumps, and magic items a flat formula can't reproduce. Sparse: only the
  // abilities actually stated are recorded, everything else falls back to the raw
  // ability modifier (see savingThrowBonus).
  function normalizeSavingThrows(raw) {
    if (!raw || typeof raw !== "object") return undefined;
    const saves = {};
    let any = false;
    ABILITY_KEYS.forEach((key) => {
      const value = Number(raw[key]);
      if (Number.isFinite(value)) {
        saves[key] = Math.round(value);
        any = true;
      }
    });
    return any ? saves : undefined;
  }

  // A stated skill bonus (parsed from a character sheet's "Skills:" line, e.g.
  // "Perception +9, Stealth +6") is stored as-is rather than recomputed from ability
  // modifier + proficiency (+ expertise) -- same rationale as normalizeSavingThrows: real
  // sheets bake in bumps a flat formula can't reproduce. Sparse: only the skills actually
  // stated are recorded, everything else falls back to the raw ability modifier (see
  // abilityCheckBonus).
  function normalizeSkills(raw) {
    if (!raw || typeof raw !== "object") return undefined;
    const skills = {};
    let any = false;
    SKILL_LIST.forEach(({ name }) => {
      const value = Number(raw[name]);
      if (Number.isFinite(value)) {
        skills[name] = Math.round(value);
        any = true;
      }
    });
    return any ? skills : undefined;
  }

  function abilityModifier(score) {
    return Math.floor((Number(score) - 10) / 2);
  }

  // Sparse per-level (1-9) spell slot tracker: only levels the caster actually has are
  // present. Each level stores {max, current}; current is clamped to [0, max] so a bad
  // update (e.g. current > max after an editor typo) can't create slots out of nowhere.
  function normalizeSpellSlots(raw) {
    if (!raw || typeof raw !== "object") return undefined;
    const slots = {};
    let any = false;
    for (let level = 1; level <= 9; level += 1) {
      const entry = raw[level];
      if (!entry || typeof entry !== "object") continue;
      const max = Number(entry.max);
      if (!Number.isFinite(max) || max <= 0) continue;
      const clampedMax = clampNumber(max, 1, 99);
      const current = Number.isFinite(Number(entry.current)) ? Number(entry.current) : clampedMax;
      slots[level] = { max: clampedMax, current: clampNumber(current, 0, clampedMax) };
      any = true;
    }
    return any ? slots : undefined;
  }

  // A stated spell save DC / spell attack bonus (parsed from a real sheet's
  // "Spellcasting:" line, e.g. "Spell save DC 16, spell attack +8") is stored as-is,
  // same rationale as savingThrows: real sheets bake in proficiency/feats/magic items a
  // flat formula can't reproduce. Sparse -- either field can be present alone.
  function normalizeSpellcasting(raw) {
    if (!raw || typeof raw !== "object") return undefined;
    const result = {};
    const saveDC = Number(raw.saveDC);
    if (Number.isFinite(saveDC)) result.saveDC = clampNumber(saveDC, 1, 30);
    const attackBonus = Number(raw.attackBonus);
    if (Number.isFinite(attackBonus)) result.attackBonus = clampNumber(attackBonus, -20, 99);
    return Object.keys(result).length ? result : undefined;
  }

  function ordinal(level) {
    if (level === 1) return "1st";
    if (level === 2) return "2nd";
    if (level === 3) return "3rd";
    return `${level}th`;
  }

  // Sparse, named class-resource tracker (Rage, Wild Shape, Ki Points, Superiority Dice,
  // Channel Divinity, Bardic Inspiration, ...) -- each entry is {max, current}, current
  // clamped to [0, max]. Unlike spell slots (a fixed 1-9 numeric range with one canonical
  // sheet line), class resources vary too much in name, count, and recovery wording across
  // classes to auto-extract reliably from freeform Features & Traits prose, so these are
  // entered by hand on the token sheet (see ui/app.js's Resources section) rather than
  // imported from markdown -- a deliberate, known gap, same spirit as Troll's Regeneration
  // not being automated in spawnMonster.
  // `recovery` is "short" (restored by both a short and a long rest -- Second Wind, Wild
  // Shape, Superiority Dice, Channel Divinity, etc. all work this way) or "long" (only a
  // long rest restores it -- Rage, most everything else), defaulting to "long" since that's
  // the safer assumption for a resource added without specifying (nothing is over-restored
  // by a short rest it shouldn't be).
  function normalizeResources(raw) {
    if (!raw || typeof raw !== "object") return undefined;
    const resources = {};
    let any = false;
    Object.keys(raw).forEach((name) => {
      const key = String(name || "").trim();
      const entry = raw[name];
      if (!key || !entry || typeof entry !== "object") return;
      const max = Number(entry.max);
      if (!Number.isFinite(max) || max <= 0) return;
      const clampedMax = clampNumber(max, 1, 99);
      const current = Number.isFinite(Number(entry.current)) ? Number(entry.current) : clampedMax;
      const recovery = entry.recovery === "short" ? "short" : "long";
      resources[key] = { max: clampedMax, current: clampNumber(current, 0, clampedMax), recovery };
      any = true;
    });
    return any ? resources : undefined;
  }

  // A token's damageResistances/damageVulnerabilities/damageImmunities: a plain array of
  // lowercase type strings (not a sparse map like resources/hitDice, since there's no
  // per-entry {max,current} to track -- a type is either listed or it isn't). Accepts either
  // a real array or a comma-separated string (the token sheet's own text-input shape), so the
  // UI can submit either without its own pre-parsing. Deduplicated case-insensitively; empty/
  // blank entries dropped.
  function normalizeDamageTypeList(raw) {
    if (!raw) return undefined;
    const list = Array.isArray(raw) ? raw : String(raw).split(",");
    const cleaned = [...new Set(list.map((entry) => String(entry || "").trim().toLowerCase()).filter(Boolean))];
    return cleaned.length ? cleaned : undefined;
  }

  // A token's Hit Dice, sparse by die type (e.g. "d12", "d10") rather than a single
  // {die, total, current} -- a real high-level sheet is routinely multiclassed (this
  // campaign's own PCs are: "Barbarian 11 / Fighter 4" has 11d12 + 4d10, not one die type),
  // and 5e RAW already pools same-size dice from different classes together rather than
  // tracking them per-class. `campaign.js`'s `extractHitDice` builds this from a sheet's
  // "Class & Level" line; `total`/`current` follow the same {max→total, current} shape as
  // every other sparse pool in this file.
  function normalizeHitDice(raw) {
    if (!raw || typeof raw !== "object") return undefined;
    const hitDice = {};
    let any = false;
    Object.keys(raw).forEach((dieKey) => {
      const key = String(dieKey || "").trim().toLowerCase();
      const entry = raw[dieKey];
      if (!/^d\d+$/.test(key) || !entry || typeof entry !== "object") return;
      const total = Number(entry.total);
      if (!Number.isFinite(total) || total <= 0) return;
      const clampedTotal = clampNumber(total, 1, 99);
      const current = Number.isFinite(Number(entry.current)) ? Number(entry.current) : clampedTotal;
      hitDice[key] = { total: clampedTotal, current: clampNumber(current, 0, clampedTotal) };
      any = true;
    });
    return any ? hitDice : undefined;
  }

  // Resource names are free text (not a fixed enum like abilities/save keys), so lookups
  // match case-insensitively -- narration or Claude saying "rage" should still find a
  // token's stored "Rage" entry -- and return the actual stored key so callers can report
  // and mutate using the sheet's own casing.
  function findResourceKey(token, name) {
    const normalized = String(name || "").trim().toLowerCase();
    return Object.keys(token.resources || {}).find((key) => key.toLowerCase() === normalized);
  }

  // A recharge-based monster ability (Fire Breath, etc.) -- sparse map keyed by ability
  // name, each `{rechargeMin, available}`. `rechargeMin` is the lowest d6 roll (1-6) that
  // recharges it at the start of the token's own turn (see nextTurn()); `available`
  // defaults to true (a fresh monster's recharge abilities start ready) and flips false once
  // spent via useRechargeAbility(). Unlike resources (which only refill on a rest) or
  // legendary actions (which refill every turn unconditionally), this is a per-turn dice
  // roll that might not succeed -- matching RAW's "recharge 5-6" wording exactly rather than
  // guaranteeing availability.
  function normalizeRechargeAbilities(raw) {
    if (!raw || typeof raw !== "object") return undefined;
    const abilities = {};
    let any = false;
    Object.keys(raw).forEach((name) => {
      const key = String(name || "").trim();
      const entry = raw[name];
      if (!key || !entry || typeof entry !== "object" || !Number.isFinite(Number(entry.rechargeMin))) return;
      const rechargeMin = clampNumber(entry.rechargeMin, 1, 6);
      const available = entry.available === undefined ? true : Boolean(entry.available);
      abilities[key] = { rechargeMin, available };
      any = true;
    });
    return any ? abilities : undefined;
  }

  function findRechargeAbilityKey(token, name) {
    const normalized = String(name || "").trim().toLowerCase();
    return Object.keys(token.rechargeAbilities || {}).find((key) => key.toLowerCase() === normalized);
  }

  // A single {max, current} tracker, same shape as one named resource -- but unlike
  // resources (which only refill on a rest), legendary actions refill automatically at the
  // start of the token's own turn (see nextTurn()), matching RAW ("regains all expended
  // legendary actions at the start of its turn"). Most tokens have none at all (sparse,
  // absent by default).
  function normalizeLegendaryActions(raw) {
    if (!raw || typeof raw !== "object") return undefined;
    const max = Number(raw.max);
    if (!Number.isFinite(max) || max <= 0) return undefined;
    const clampedMax = clampNumber(max, 1, 10);
    const current = Number.isFinite(Number(raw.current)) ? Number(raw.current) : clampedMax;
    return { max: clampedMax, current: clampNumber(current, 0, clampedMax) };
  }

  // The bonus rollSavingThrow adds to the d20: an explicit stated save bonus if the sheet
  // has one, else the raw ability modifier (no proficiency bonus -- a token only gets that
  // if it's baked into an explicit override, matching how monsters without a stated
  // saving-throw proficiency in the SRD just use a flat ability modifier too), else 0 if
  // the token has no ability scores recorded at all.
  function savingThrowBonus(token, ability) {
    const stated = token.savingThrows?.[ability];
    if (Number.isFinite(stated)) return stated;
    const score = token.abilityScores?.[ability];
    return Number.isFinite(score) ? abilityModifier(score) : 0;
  }

  // The bonus rollAbilityCheck adds to the d20. `skillOrAbility` can be a named skill
  // (e.g. "Perception") -- resolved through the token's stated skills override, falling
  // back to the ability modifier of that skill's governing ability -- or a bare ability
  // (e.g. "STR", for an unnamed check like forcing a door), resolved the same way
  // savingThrowBonus resolves a save with no stated override. Returns null for a name that
  // matches neither a known skill nor a valid ability, so callers can distinguish "no bonus
  // known" (0) from "not a real skill/ability at all".
  function abilityCheckBonus(token, skillOrAbility) {
    const skill = findSkill(skillOrAbility);
    if (skill) {
      const stated = token.skills?.[skill.name];
      if (Number.isFinite(stated)) return stated;
      const score = token.abilityScores?.[skill.ability];
      return Number.isFinite(score) ? abilityModifier(score) : 0;
    }
    const key = String(skillOrAbility || "").toUpperCase().slice(0, 3);
    if (ABILITY_KEYS.includes(key)) {
      const score = token.abilityScores?.[key];
      return Number.isFinite(score) ? abilityModifier(score) : 0;
    }
    return null;
  }

  // Rolls a saving throw for `tokenId` against `dc`, using its real ability modifier (or
  // stated save bonus, see savingThrowBonus above) rather than a flat guess. Only reports
  // pass/fail -- it does not apply any follow-up effect (e.g. half damage on a success);
  // narration/subsequent actions apply damage or conditions based on the reported result
  // separately, the same way a real table resolves a save before deciding the consequence.
  // Exhaustion level 3+ forces disadvantage on the roll automatically (RAW) -- derived from
  // the token's own state, not something a caller has to remember to pass in. Stunned,
  // Paralyzed, and Unconscious automatically fail any STR/DEX save with no roll at all (RAW:
  // these conditions cause a STR/DEX save failure outright); Restrained imposes disadvantage
  // specifically on DEX saves (not saves generally) -- see hasCondition and friends above.
  // options: { advantage: bool, disadvantage: bool } -- a situational source a DM declares
  // (Bless-like effects, cover, a class feature) rather than derived from the token's own
  // state, combined with the automatic condition-based disadvantage above using attack()'s
  // own convention: explicit and automatic sources on the same side just both count as one
  // (RAW doesn't stack multiple advantage or multiple disadvantage), and advantage +
  // disadvantage together cancel out to a normal roll rather than one silently winning.
  function rollSavingThrow(state, tokenId, ability, dc, options = {}) {
    const key = String(ability || "").toUpperCase().slice(0, 3);
    if (!ABILITY_KEYS.includes(key)) {
      return { state, message: `Saving throw failed: "${ability}" is not a valid ability.`, success: false };
    }

    const token = tokensOnCurrentMap(state).find((item) => item.id === tokenId);
    if (!token) return { state, message: "Saving throw failed: token was not found.", success: false };

    const dcNumber = Number(dc) || 0;
    const autoFails = (key === "STR" || key === "DEX")
      && (hasCondition(token, "Stunned") || hasCondition(token, "Paralyzed") || hasCondition(token, "Unconscious"));
    if (autoFails) {
      const message = `${token.name} automatically fails the ${key} save vs DC ${dcNumber} (incapacitated).`;
      return { state: addLogEntry(state, message), message, success: false, total: null };
    }

    const bonus = savingThrowBonus(token, key);
    const exhausted = (token.exhaustion || 0) >= 3;
    const restrainedDex = key === "DEX" && hasCondition(token, "Restrained");
    const hasDisadvantage = Boolean(options.disadvantage) || exhausted || restrainedDex;
    const hasAdvantage = Boolean(options.advantage);
    const mode = hasDisadvantage && hasAdvantage ? null : hasDisadvantage ? "disadvantage" : hasAdvantage ? "advantage" : null;
    const d20Info = rollD20WithMode(mode);
    const roll = d20Info.roll;
    const total = roll + bonus;
    const success = total >= dcNumber;
    const disadvantageReason = mode !== "disadvantage" ? null
      : exhausted && restrainedDex ? "exhaustion + restrained disadvantage"
      : exhausted ? "exhaustion disadvantage" : restrainedDex ? "restrained disadvantage" : "disadvantage";
    const reasonLabel = mode === "advantage" ? "advantage" : disadvantageReason;
    const rollLabel = d20Info.rolls.length ? `${roll} (${reasonLabel}: ${d20Info.rolls.join(", ")})` : `${roll}`;
    const message = `${token.name} rolls a ${key} save: ${rollLabel} ${bonus >= 0 ? "+" : ""}${bonus} = ${total} vs DC ${dcNumber}. ${success ? "Success" : "Failure"}.`;
    return { state: addLogEntry(state, message), message, success, total };
  }

  // Rolls an ability/skill check for `tokenId` against `dc` -- Perception, Stealth,
  // Persuasion, etc. (see SKILL_LIST), or a bare ability (STR/DEX/...) for an unnamed check
  // like forcing open a door. Mirrors rollSavingThrow's structure: only reports pass/fail,
  // no follow-up effect. RAW: exhaustion level 1+ imposes disadvantage on ability checks --
  // a different, lower threshold than attack rolls/saves' level 3+ (see the Exhaustion
  // bullet in CLAUDE.md) -- and Poisoned imposes disadvantage on ability checks the same way
  // it does attack rolls. Blinded's "auto-fails a check that requires sight" isn't modeled:
  // whether a given check is sight-dependent is a DM judgment call this engine can't make,
  // the same "leave it to narration" treatment Charmed/Frightened get. options: see
  // rollSavingThrow's own doc comment -- same declared-vs-automatic combination convention.
  function rollAbilityCheck(state, tokenId, skillOrAbility, dc, options = {}) {
    const token = tokensOnCurrentMap(state).find((item) => item.id === tokenId);
    if (!token) return { state, message: "Ability check failed: token was not found.", success: false };

    const bonus = abilityCheckBonus(token, skillOrAbility);
    if (bonus === null) {
      return { state, message: `Ability check failed: "${skillOrAbility}" is not a valid skill or ability.`, success: false };
    }

    const dcNumber = Number(dc) || 0;
    const skill = findSkill(skillOrAbility);
    const label = skill ? skill.name : String(skillOrAbility || "").toUpperCase().slice(0, 3);
    const exhausted = (token.exhaustion || 0) >= 1;
    const poisoned = hasCondition(token, "Poisoned");
    const hasDisadvantage = Boolean(options.disadvantage) || exhausted || poisoned;
    const hasAdvantage = Boolean(options.advantage);
    const mode = hasDisadvantage && hasAdvantage ? null : hasDisadvantage ? "disadvantage" : hasAdvantage ? "advantage" : null;
    const d20Info = rollD20WithMode(mode);
    const roll = d20Info.roll;
    const total = roll + bonus;
    const success = total >= dcNumber;
    const disadvantageReason = mode !== "disadvantage" ? null
      : exhausted && poisoned ? "exhaustion + poisoned disadvantage"
      : exhausted ? "exhaustion disadvantage" : poisoned ? "poisoned disadvantage" : "disadvantage";
    const reasonLabel = mode === "advantage" ? "advantage" : disadvantageReason;
    const rollLabel = d20Info.rolls.length ? `${roll} (${reasonLabel}: ${d20Info.rolls.join(", ")})` : `${roll}`;
    const message = `${token.name} rolls a ${label} check: ${rollLabel} ${bonus >= 0 ? "+" : ""}${bonus} = ${total} vs DC ${dcNumber}. ${success ? "Success" : "Failure"}.`;
    return { state: addLogEntry(state, message), message, success, total };
  }

  // Rolls initiative for `tokenId`: 1d20 + the token's real DEX modifier (RAW), sets
  // token.initiative directly, and logs it -- a flat re-roll every call, with no "keep the
  // higher of two rolls"/Alert-feat-style bonus modeled, matching this engine's existing
  // "derive from the ability score, don't model every possible modifier" pattern
  // (abilityCheckBonus/savingThrowBonus do the same). No advantage/disadvantage support
  // here unlike attack/save/check/spell -- an initiative roll having advantage isn't a RAW
  // thing outside a specific feat this engine doesn't model. For a player who rolls their
  // own physical d20 and just reports the total, or a DM correcting/tie-breaking an
  // already-set value, use updateToken(state, tokenId, { initiative }) directly instead --
  // the exact mechanism the 2D app's own plain number field on the token sheet already
  // uses, no dedicated function needed for a flat assignment.
  function rollInitiative(state, tokenId) {
    const nextState = clone(state);
    const token = nextState.tokens.find((item) => item.id === tokenId);
    if (!token) return { state, message: "Initiative roll failed: token was not found." };

    const dexScore = token.abilityScores?.DEX;
    const dexMod = Number.isFinite(dexScore) ? abilityModifier(dexScore) : 0;
    const roll = rollDie(20);
    const total = roll + dexMod;
    token.initiative = clampNumber(total, 0, 99);
    const message = `${token.name} rolls initiative: ${roll} ${dexMod >= 0 ? "+" : ""}${dexMod} = ${token.initiative}.`;
    return { state: addLogEntry(nextState, message), message };
  }

  // Spends one of `caster`'s spell slots at `level` (0 = cantrip, never consumes one),
  // mutating `caster` in place -- a live reference into a cloned state's tokens array, the
  // same in-place-mutation convention every primitive in this file follows -- and returning
  // a status message. `ok: false` (no mutation) if the caster has none of that level left.
  // Shared by castSpell and castAreaSpell so both fail/report identically.
  function spendSpellSlot(caster, level, spellName) {
    if (level > 0) {
      const slot = caster.spellSlots?.[level];
      if (!slot || slot.current <= 0) {
        return { ok: false, message: `${caster.name} has no ${ordinal(level)}-level spell slots remaining.` };
      }
      slot.current -= 1;
      return { ok: true, message: `${caster.name} casts ${spellName} using a ${ordinal(level)}-level spell slot (${slot.current} remaining).` };
    }
    return { ok: true, message: `${caster.name} casts ${spellName}.` };
  }

  // Casts a spell for `casterId`: consumes one of the caster's spell slots at `level`
  // (0 = cantrip, never consumes a slot), failing outright with no state change if the
  // caster has none of that level left. When `options.targetId` is also given, rolls a
  // single spell attack against it using the caster's stated spell attack bonus (see
  // normalizeSpellcasting) and applies any resulting damage -- the same resolveOneAttack
  // primitive attack() uses, just with a spell's own damage dice instead of a token's
  // weapon damageDice. A save-based spell (Fireball, Hold Person) has no attack roll to
  // make here; cast it alone to spend the slot, then issue separate rollSavingThrow calls
  // per target using the caster's spellcasting.saveDC, the same one-shot-batch pattern
  // saving_throw already uses for traps/effects (see dm-bridge/watch.js's guidance) --
  // OR, when every target takes the same save-for-half damage, use castAreaSpell below
  // instead, which resolves all of that in one call.
  function castSpell(state, casterId, options = {}) {
    let nextState = clone(state);
    const caster = tokensOnCurrentMap(nextState).find((token) => token.id === casterId);
    if (!caster) return { state, message: "Spellcasting failed: caster was not found." };

    const level = clampNumber(options.level ?? 0, 0, 9);
    const spellName = options.spellName || "a spell";
    const messages = [];

    // Action economy: only enforced for a leveled spell (a cantrip is exempted, same
    // simplification the plan behind this scoped it to -- most cantrips are also
    // action-consuming under RAW, but distinguishing which ones would need per-spell data
    // this engine doesn't have) on the caster's own active turn, same carve-out attack() uses.
    const isActiveTurn = Boolean(state.turn && state.turn.tokenId === casterId);
    const actionType = options.actionType === "bonusAction" ? "bonusAction" : "action";
    if (isActiveTurn && level > 0) {
      if (actionType === "bonusAction") {
        if (caster.bonusActionUsed) return { state, message: `${caster.name} has already used a bonus action this turn.` };
      } else if (caster.actionUsed || (caster.attacksUsedThisTurn || 0) > 0) {
        return { state, message: `${caster.name} has already used their action this turn.` };
      }
    }

    const slotResult = spendSpellSlot(caster, level, spellName);
    if (!slotResult.ok) return { state, message: slotResult.message };
    messages.push(slotResult.message);
    if (isActiveTurn && level > 0) {
      if (actionType === "bonusAction") caster.bonusActionUsed = true;
      else caster.actionUsed = true;
    }

    // A concentration spell always replaces whatever the caster was already concentrating
    // on (5e RAW: only one at a time) -- a non-concentration cast (options.concentration
    // falsy) leaves any existing concentration alone entirely.
    if (options.concentration) {
      if (caster.concentratingOn && caster.concentratingOn.spell !== spellName) {
        messages.push(`${caster.name}'s concentration on ${caster.concentratingOn.spell} ends.`);
      }
      caster.concentratingOn = { spell: spellName };
    }

    if (options.targetId) {
      const target = tokensOnCurrentMap(nextState).find((token) => token.id === options.targetId);
      if (target) {
        const bonus = caster.spellcasting?.attackBonus;
        if (Number.isFinite(bonus)) {
          // Same exhaustion/condition-driven mode computation attack() uses -- a spell
          // attack roll is still an attack roll under RAW, so it isn't exempt from either.
          const conditionDisadvantage = ownAttackConditionPenalty(caster) || targetGrantsAttackDisadvantage(target);
          const conditionAdvantage = ownAttackConditionBonus(caster) || targetGrantsAttackAdvantage(target);
          const hasDisadvantage = Boolean(options.disadvantage) || (caster.exhaustion || 0) >= 3 || conditionDisadvantage;
          const hasAdvantage = Boolean(options.advantage) || conditionAdvantage;
          const mode = hasDisadvantage && hasAdvantage ? null : hasDisadvantage ? "disadvantage" : hasAdvantage ? "advantage" : null;
          const forceCrit = forcesAutoCrit(target) && isAdjacent(caster, target);
          const result = resolveOneAttack(caster, target, bonus, options.damageDice, mode, spellName, forceCrit);
          messages.push(result.message);
          if (result.damageTotal > 0) {
            const damageResult = applyDamage(nextState, target.id, result.damageTotal, { critical: result.isCritical, damageType: options.damageType });
            nextState = damageResult.state;
            if (damageResult.message) messages.push(damageResult.message);
          }
        } else {
          messages.push(`(no stated spell attack bonus for ${caster.name} -- attack roll skipped.)`);
        }
      }
    }

    const message = messages.join(" ");
    return { state: addLogEntry(nextState, message), message };
  }

  // Casts an area-of-effect / multi-target spell (Fireball, Hold Person's damage-dealing
  // cousins, etc.) that hits every token in `options.targetIds` with the same saving throw
  // and damage in one call -- the "half on success, full on failure" resolution castSpell
  // plus a separate saving_throw per target can't do together in one action, because the
  // one-shot-batch dm-bridge (see CLAUDE.md) never lets Claude see a save's result before
  // deciding the next action in that same response. Folding the whole resolution into one
  // deterministic engine call sidesteps that entirely -- the half/full decision is computed
  // here from the roll itself, not chosen by Claude after the fact, the same reasoning
  // applyDamage() already uses to resolve a concentration check synchronously with no round
  // trip. `options`: { spellName, level, targetIds: [...], saveAbility, saveDC, damageDice,
  // damageType (optional -- feeds applyDamage's resistance/vulnerability/immunity check per
  // target, same as attack()/castSpell()), halfOnSave (default true), concentration }.
  // Damage is rolled ONCE for the whole area
  // (RAW: one damage roll applies to everyone caught in it, not a separate roll per target)
  // and applied per target via applyDamage, so each target's own concentration/death-save
  // bookkeeping still resolves individually -- same as attack()'s Multiattack loop resolving
  // each sub-attack against one target in turn. Each target's saveResult self-logs via
  // rollSavingThrow (so the individual rolls stay visible in the log), and the final
  // returned message/log entry folds everything -- slot spend, each save, each damage --
  // into one self-contained summary. A save with no damage roll at all (Hold Person -- an
  // effect, not damage) isn't this primitive's job: cast alone via castSpell to spend the
  // slot, then a separate saving_throw + toggle_condition per target, same as before this
  // existed.
  function castAreaSpell(state, casterId, options = {}) {
    let nextState = clone(state);
    const caster = tokensOnCurrentMap(nextState).find((token) => token.id === casterId);
    if (!caster) return { state, message: "Spellcasting failed: caster was not found." };

    const saveAbility = String(options.saveAbility || "").toUpperCase().slice(0, 3);
    if (!ABILITY_KEYS.includes(saveAbility)) {
      return { state, message: `Area spell failed: "${options.saveAbility}" is not a valid ability.` };
    }
    const targetIds = Array.isArray(options.targetIds) ? options.targetIds : [];
    if (!targetIds.length) {
      return { state, message: "Area spell failed: no targets given." };
    }

    const level = clampNumber(options.level ?? 0, 0, 9);
    const spellName = options.spellName || "a spell";
    const messages = [];

    const slotResult = spendSpellSlot(caster, level, spellName);
    if (!slotResult.ok) return { state, message: slotResult.message };
    messages.push(slotResult.message);

    if (options.concentration) {
      if (caster.concentratingOn && caster.concentratingOn.spell !== spellName) {
        messages.push(`${caster.name}'s concentration on ${caster.concentratingOn.spell} ends.`);
      }
      caster.concentratingOn = { spell: spellName };
    }

    const saveDC = Number(options.saveDC) || 0;
    const halfOnSave = options.halfOnSave !== false;
    const damage = rollDice(options.damageDice || "1d6");

    targetIds.forEach((targetId) => {
      const target = tokensOnCurrentMap(nextState).find((token) => token.id === targetId);
      if (!target) {
        messages.push("(could not find one of the area spell's targets.)");
        return;
      }

      const saveResult = rollSavingThrow(nextState, target.id, saveAbility, saveDC);
      nextState = saveResult.state;
      messages.push(saveResult.message);

      const amount = saveResult.success ? (halfOnSave ? Math.floor(damage.total / 2) : 0) : damage.total;
      if (amount > 0) {
        const damageResult = applyDamage(nextState, target.id, amount, { damageType: options.damageType });
        nextState = damageResult.state;
        messages.push(`${target.name} takes ${amount} damage (${damage.notation}).${damageResult.message ? ` ${damageResult.message}` : ""}`);
      } else {
        messages.push(`${target.name} takes no damage.`);
      }
    });

    const message = messages.join(" ");
    return { state: addLogEntry(nextState, message), message };
  }

  // Voluntarily ends whatever a token is concentrating on -- e.g. before casting a
  // non-concentration spell, or narration just says a caster stops on purpose. A no-op
  // message (not a failure) if the token wasn't concentrating on anything, same tone as
  // toggleCondition removing a condition that isn't there.
  function dropConcentration(state, tokenId) {
    const nextState = clone(state);
    const token = nextState.tokens.find((item) => item.id === tokenId);
    if (!token) return { state, message: "Drop concentration failed: token was not found." };

    if (!token.concentratingOn) {
      return { state: nextState, message: `${token.name} isn't concentrating on anything.` };
    }

    const spellName = token.concentratingOn.spell;
    delete token.concentratingOn;
    const message = `${token.name} stops concentrating on ${spellName}.`;
    return { state: addLogEntry(nextState, message), message };
  }

  // Spends `amount` (default 1) charges of a named class resource -- fails outright with
  // no state change if the token has no such resource tracked, or not enough left. Only
  // spends the charge and logs how many remain; any actual effect (damage, healing, a
  // saving throw) needs its own separate call, the same composable-primitives approach
  // castSpell/rollSavingThrow already use.
  function useResource(state, tokenId, resourceName, amount) {
    let nextState = clone(state);
    const token = tokensOnCurrentMap(nextState).find((item) => item.id === tokenId);
    if (!token) return { state, message: "Resource use failed: token was not found." };

    const key = findResourceKey(token, resourceName);
    if (!key) return { state, message: `${token.name} has no "${resourceName}" resource tracked.` };

    const resource = token.resources[key];
    const spend = clampNumber(amount ?? 1, 1, 99);
    if (resource.current < spend) {
      return { state, message: `${token.name} doesn't have ${spend} ${key} left (${resource.current}/${resource.max} remaining).` };
    }

    resource.current -= spend;
    const message = `${token.name} uses ${key}${spend > 1 ? ` (${spend})` : ""} (${resource.current}/${resource.max} remaining).`;
    return { state: addLogEntry(nextState, message), message };
  }

  // Restores charges to a named class resource, clamped so it can't exceed max -- covers
  // "regains an expended resource" (a short/long rest, a feature that grants one back)
  // without the engine modeling rest cadence itself; omitting `amount` restores to full,
  // the same manual-trigger pattern the HP panel's Heal/Full HP buttons already use for HP.
  function restoreResource(state, tokenId, resourceName, amount) {
    let nextState = clone(state);
    const token = tokensOnCurrentMap(nextState).find((item) => item.id === tokenId);
    if (!token) return { state, message: "Resource restore failed: token was not found." };

    const key = findResourceKey(token, resourceName);
    if (!key) return { state, message: `${token.name} has no "${resourceName}" resource tracked.` };

    const resource = token.resources[key];
    const restoreAmount = Number.isFinite(Number(amount)) ? clampNumber(amount, 1, 99) : resource.max;
    resource.current = clampNumber(resource.current + restoreAmount, 0, resource.max);
    const message = `${token.name} regains ${key} (${resource.current}/${resource.max} remaining).`;
    return { state: addLogEntry(nextState, message), message };
  }

  // Spends `count` (default 1) Hit Dice of a given die type (e.g. "d10") -- rolls that many
  // dice plus the token's CON modifier per die (RAW: minimum 1 total, even if the modifier
  // is negative enough to zero it out) and heals the total via applyHealing, decrementing
  // `current`. Fails outright (no state change, same convention as useResource) if the token
  // has no dice of that type tracked or fewer remain than requested. This is the one place
  // Hit Dice actually get spent -- longRest() restores half back (rounded up), but nothing
  // spends them automatically during a short rest, since a real table decides how many (if
  // any) to spend rather than the engine assuming all of them.
  function spendHitDie(state, tokenId, dieType, count) {
    let nextState = clone(state);
    const token = tokensOnCurrentMap(nextState).find((item) => item.id === tokenId);
    if (!token) return { state, message: "Hit Dice spend failed: token was not found." };

    const key = String(dieType || "").trim().toLowerCase();
    const pool = token.hitDice?.[key];
    if (!pool) return { state, message: `${token.name} has no ${key || "?"} Hit Dice tracked.` };

    const spend = clampNumber(count ?? 1, 1, 99);
    if (pool.current < spend) {
      return { state, message: `${token.name} doesn't have ${spend} ${key} Hit Dice left (${pool.current}/${pool.total} remaining).` };
    }

    const sides = Number(key.slice(1));
    const conMod = Number.isFinite(token.abilityScores?.CON) ? abilityModifier(token.abilityScores.CON) : 0;
    let healed = 0;
    for (let i = 0; i < spend; i += 1) {
      healed += Math.max(1, rollDie(sides) + conMod);
    }

    pool.current -= spend;
    const healResult = applyHealing(nextState, token.id, healed);
    nextState = healResult;
    const healedToken = tokensOnCurrentMap(nextState).find((item) => item.id === token.id);
    const message = `${token.name} spends ${spend} ${key} Hit Dice, healing ${healed} (${healedToken.hp}/${healedToken.maxHp} HP) -- ${pool.current}/${pool.total} ${key} Hit Dice remaining.`;
    return { state: addLogEntry(nextState, message), message };
  }

  // Spends a named recharge-based ability (Fire Breath, etc.) -- fails outright with no
  // state change if the token has no such ability tracked or it's already been spent this
  // encounter and hasn't recharged yet. Unlike useResource/useLegendaryAction, this only
  // flips `available` to false; it never bundles the ability's actual effect (damage, a
  // saving throw), which still needs its own separate action, the same compose-only pattern
  // cast_spell/use_resource already use. It recharges back on a d6 roll (>= rechargeMin) at
  // the start of the token's own next turn -- see nextTurn().
  function useRechargeAbility(state, tokenId, name) {
    const nextState = clone(state);
    const token = nextState.tokens.find((item) => item.id === tokenId);
    if (!token) return { state, message: "Recharge ability use failed: token was not found." };

    const key = findRechargeAbilityKey(token, name);
    if (!key) return { state, message: `${token.name} has no "${name}" recharge ability tracked.` };

    const ability = token.rechargeAbilities[key];
    if (!ability.available) {
      return { state, message: `${token.name}'s ${key} hasn't recharged yet.` };
    }

    ability.available = false;
    const message = `${token.name} uses ${key}.`;
    return { state: addLogEntry(nextState, message), message };
  }

  // Spends `cost` (default 1) legendary action points -- fails outright with no state change
  // if the token has none tracked, or not enough left. RAW says legendary actions are only
  // usable "at the end of another creature's turn"; this engine has no notion of whose turn
  // just ended beyond next_turn's own result, so -- same as rollDeathSave's "at the start of
  // its turn" trigger -- that timing judgment is left to the DM/Claude (see
  // dm-bridge/watch.js's guidance) rather than enforced here. Refreshing to full happens
  // automatically at the start of the token's own turn; see nextTurn().
  function useLegendaryAction(state, tokenId, cost) {
    const nextState = clone(state);
    const token = nextState.tokens.find((item) => item.id === tokenId);
    if (!token) return { state, message: "Legendary action failed: token was not found." };
    if (!token.legendaryActions) return { state, message: `${token.name} has no legendary actions tracked.` };

    const spend = clampNumber(cost ?? 1, 1, 10);
    if (token.legendaryActions.current < spend) {
      return {
        state,
        message: `${token.name} doesn't have ${spend} legendary action${spend > 1 ? "s" : ""} left (${token.legendaryActions.current}/${token.legendaryActions.max} remaining).`
      };
    }

    token.legendaryActions.current -= spend;
    const message = `${token.name} uses a legendary action${spend > 1 ? ` (${spend})` : ""} (${token.legendaryActions.current}/${token.legendaryActions.max} remaining).`;
    return { state: addLogEntry(nextState, message), message };
  }

  // Triggers the current map's lair action for this round -- RAW: on initiative count 20,
  // once per round, so a second call in the same round is refused rather than silently
  // stacking. `description` is freeform (what the lair actually does this round -- the DM/
  // Claude narrates it and applies any real effect via separate actions, e.g. apply_damage or
  // saving_throw, the same compose-only pattern cast_spell/use_resource already use). Tracked
  // per encounter state, not per map -- a deliberate simplification; switching maps mid-fight
  // doesn't reset it.
  function triggerLairAction(state, description) {
    const nextState = clone(state);
    const round = nextState.turn?.round || 0;
    if (nextState.lairActionRound === round) {
      return { state: nextState, message: "The lair action has already triggered this round." };
    }

    nextState.lairActionRound = round;
    const message = `Lair action: ${description || "the lair stirs."}`;
    return { state: addLogEntry(nextState, message), message };
  }

  // A long rest (~8 hours): full HP, every spell slot back to max, every resource back to
  // max regardless of its recovery tag, half (rounded up) of each Hit Dice pool restored,
  // and one level of exhaustion removed (RAW). Skips only the HP/revival part for a token
  // flagged dead -- a long rest isn't a substitute for Raise Dead/Revivify -- but still
  // refreshes slots/resources/Hit Dice/exhaustion regardless, since none of those require
  // the token to be conscious for the rest to have happened around them.
  function longRest(state, tokenId) {
    const nextState = clone(state);
    const token = nextState.tokens.find((item) => item.id === tokenId);
    if (!token) return { state, message: "Long rest failed: token was not found." };

    const messages = [`${token.name} takes a long rest.`];

    if (!token.dead) {
      token.hp = token.maxHp;
      delete token.dying;
      messages.push(`Fully healed (${token.hp}/${token.maxHp} HP).`);
    }

    if (token.spellSlots && Object.keys(token.spellSlots).length) {
      Object.values(token.spellSlots).forEach((slot) => { slot.current = slot.max; });
      messages.push("All spell slots restored.");
    }

    if (token.resources && Object.keys(token.resources).length) {
      Object.values(token.resources).forEach((resource) => { resource.current = resource.max; });
      messages.push("All resources restored.");
    }

    // RAW (PHB "Long Rest"): a long rest restores UP TO half of a creature's total Hit Dice,
    // rounded DOWN, with a minimum of one die restored -- not all of them, unlike spell
    // slots/resources above, which fully refill. Rounds down, not up: the rule's own
    // "(minimum of one die)" clause only has a reason to exist under round-down math --
    // rounding up already guarantees at least one for any total >= 1, so a separate minimum
    // would be redundant text. The PHB's own worked example (8 total -> 4 restored) is exact
    // and doesn't distinguish the two, but this file's own tests (11 total -> 5, not 6) do.
    if (token.hitDice && Object.keys(token.hitDice).length) {
      Object.values(token.hitDice).forEach((pool) => {
        const restored = Math.max(1, Math.floor(pool.total / 2));
        pool.current = clampNumber(pool.current + restored, 0, pool.total);
      });
      messages.push("Half of all Hit Dice restored.");
    }

    if (token.exhaustion) {
      token.exhaustion = clampNumber(token.exhaustion - 1, 0, 6);
      if (token.exhaustion === 0) delete token.exhaustion;
      messages.push(`Exhaustion reduced to ${token.exhaustion || 0}.`);
    }

    const message = messages.join(" ");
    return { state: addLogEntry(nextState, message), message };
  }

  // A short rest (~1 hour): restores every resource tagged recovery: "short" to max --
  // Second Wind, Wild Shape, Superiority Dice, Channel Divinity, and similar. Deliberately
  // does NOT touch HP or Hit Dice directly -- RAW lets a creature spend Hit Dice during a
  // short rest, but how many (if any) is the player's choice each time, not an automatic
  // full/half refill like the pools above, so that's `spendHitDie()` called explicitly
  // rather than something shortRest does on its own -- nor spell slots (almost no class
  // recovers those on a short rest; the one common exception, Warlock Pact Magic, isn't
  // specially modeled here -- restore a Warlock's slots by hand via the token editor if
  // that comes up).
  function shortRest(state, tokenId) {
    const nextState = clone(state);
    const token = nextState.tokens.find((item) => item.id === tokenId);
    if (!token) return { state, message: "Short rest failed: token was not found." };

    const shortRestNames = Object.keys(token.resources || {}).filter((name) => token.resources[name].recovery === "short");
    if (!shortRestNames.length) {
      const message = `${token.name} takes a short rest -- no short-rest resources to restore.`;
      return { state: addLogEntry(nextState, message), message };
    }

    shortRestNames.forEach((name) => { token.resources[name].current = token.resources[name].max; });
    const message = `${token.name} takes a short rest. Restored: ${shortRestNames.join(", ")}.`;
    return { state: addLogEntry(nextState, message), message };
  }

  // Applies damage and resolves whatever it triggers -- a concentration check if the target
  // was concentrating, and/or death-save bookkeeping if it's at (or drops to) 0 HP:
  //   - Still conscious after this hit, and concentrating: the normal CON save (DC = max(10,
  //     half the damage, rounded down)) to maintain it.
  //   - Drops from above 0 to exactly 0 this hit: concentration ends outright with no save
  //     (an unconscious creature can't concentrate), and death saves start (skipped if the
  //     token is already flagged dead, which shouldn't normally coincide with hp > 0 anyway).
  //   - Already at 0 HP and takes MORE damage: that's an automatic failed death save per RAW
  //     (not a roll) -- two failures instead of one if `options.critical` is set, same as a
  //     real critical hit against a downed creature. Three failures kills outright. This
  //     applies whether or not the token is currently stable: RAW ("if a stable creature
  //     takes damage, it starts making death saving throws again") means a stabilized token
  //     taking a hit un-stabilizes and resumes dying, not that the damage is silently
  //     absorbed for free -- successes/failures reset to 0 first (a genuine restart, not a
  //     resume from wherever the count was when it stabilized), then this hit's automatic
  //     failure(s) apply on top, same as the non-stable case below.
  // Every token type is treated the same here (RAW technically reserves death saves for PCs,
  // leaving monsters to the DM's judgment) -- a deliberate simplification; a monster the DM
  // just wants to treat as dead at 0 HP can simply be left alone or edited directly.
  // Deliberately does NOT self-log the way rollSavingThrow/rollDeathSave do -- damage is
  // applied from several different contexts (a weapon attack, a spell attack, a flat
  // DM-narrated amount, a manual HP-panel click) that each already build their own single
  // combined message/log line, so the caller folds `message` into that rather than getting a
  // second, separately-logged entry for free. See attack(), castSpell(), dmBridge.js's
  // apply_damage case, and the HP panel's Damage button.
  //
  // Resistance/vulnerability/immunity, when options.damageType is given and matches (case-
  // insensitively) one of the token's own damageImmunities/damageResistances/
  // damageVulnerabilities: immunity zeroes the damage outright, resistance halves it (rounded
  // down), vulnerability doubles it. A token listed as BOTH resistant and vulnerable to the
  // exact same type (a contradiction under normal RAW, but not one this engine enforces at
  // entry) cancels out to the raw amount, the commonly accepted ruling for that edge case --
  // matched before either single-direction check so it can't fall through to one of them by
  // list-ordering accident. No damageType given (every existing call site before this feature,
  // and still the deliberate choice for the HP panel's manual Damage button and a flat
  // DM-narrated amount with no stated type) skips this entirely -- full amount applies, exactly
  // today's behavior, so nothing is affected without opting in.
  function damageTypeModifier(token, damageType) {
    if (!damageType) return null;
    const type = String(damageType).trim().toLowerCase();
    if (!type) return null;
    const listHas = (list) => Array.isArray(list) && list.some((entry) => String(entry).toLowerCase() === type);
    if (listHas(token.damageImmunities)) return "immune";
    const resistant = listHas(token.damageResistances);
    const vulnerable = listHas(token.damageVulnerabilities);
    if (resistant && vulnerable) return null;
    if (resistant) return "resistant";
    if (vulnerable) return "vulnerable";
    return null;
  }

  function applyDamage(state, tokenId, amount, options = {}) {
    const nextState = clone(state);
    const token = nextState.tokens.find((item) => item.id === tokenId);
    if (!token) return { state: nextState, message: null };

    const modifier = damageTypeModifier(token, options.damageType);
    const adjustedAmount = modifier === "immune" ? 0
      : modifier === "resistant" ? Math.floor(amount / 2)
      : modifier === "vulnerable" ? amount * 2
      : amount;
    const modifierNote = modifier && amount > 0
      ? modifier === "immune" ? `${token.name} is immune to ${options.damageType} -- no damage taken.`
        : modifier === "resistant" ? `${token.name} resists ${options.damageType} -- damage reduced to ${adjustedAmount}.`
        : `${token.name} is vulnerable to ${options.damageType} -- damage increased to ${adjustedAmount}.`
      : null;

    const wasAboveZero = token.hp > 0;
    token.hp = clampNumber(token.hp - adjustedAmount, 0, token.maxHp);
    if (adjustedAmount <= 0) return { state: nextState, message: modifierNote };

    const amountTaken = adjustedAmount;
    const messages = modifierNote ? [modifierNote] : [];

    if (wasAboveZero && token.hp === 0) {
      if (token.concentratingOn) {
        messages.push(`${token.name} falls unconscious and loses concentration on ${token.concentratingOn.spell}.`);
        delete token.concentratingOn;
      }
      if (!token.dead) {
        token.dying = { successes: 0, failures: 0, stable: false };
        messages.push(`${token.name} drops to 0 HP and starts making death saves.`);
      }
    } else if (wasAboveZero) {
      if (token.concentratingOn) {
        const spellName = token.concentratingOn.spell;
        const dc = Math.max(10, Math.floor(amountTaken / 2));
        const bonus = savingThrowBonus(token, "CON");
        const roll = rollDie(20);
        const total = roll + bonus;
        const rollText = `${token.name} rolls a CON save (concentration): ${roll} ${bonus >= 0 ? "+" : ""}${bonus} = ${total} vs DC ${dc}.`;
        if (total >= dc) {
          messages.push(`${rollText} Maintains concentration on ${spellName}.`);
        } else {
          delete token.concentratingOn;
          messages.push(`${rollText} Loses concentration on ${spellName}.`);
        }
      }
    } else if (token.dying) {
      const wasStable = token.dying.stable;
      if (wasStable) {
        token.dying.stable = false;
        token.dying.successes = 0;
        token.dying.failures = 0;
      }
      const failCount = options.critical ? 2 : 1;
      token.dying.failures += failCount;
      const resumeNote = wasStable ? ` ${token.name} is no longer stable and resumes making death saves.` : "";
      messages.push(`${token.name} takes damage while down: ${failCount > 1 ? "2 automatic failed death saves (critical hit)" : "1 automatic failed death save"} (${token.dying.failures}/3 failures).${resumeNote}`);
      if (token.dying.failures >= 3) {
        delete token.dying;
        token.dead = true;
        messages.push(`${token.name} dies.`);
      }
    }

    return { state: nextState, message: messages.length ? messages.join(" ") : null };
  }

  // Rolls a death saving throw for a token currently making them: a flat d20, no modifiers.
  // 10+ succeeds, anything else fails (a natural 1 counts as two failures at once); a natural
  // 20 instead regains 1 HP and consciousness immediately. Three successes stabilizes (still
  // unconscious at 0 HP, but no longer rolling); three failures kills. A no-op (not a
  // failure) if the token isn't actually making death saves right now -- not down, already
  // stable, or already dead. Self-logs, same as rollSavingThrow/useResource -- this is its own
  // atomic, player-visible event, not something folded into a wider action's message.
  function rollDeathSave(state, tokenId) {
    const nextState = clone(state);
    const token = nextState.tokens.find((item) => item.id === tokenId);
    if (!token) return { state, message: "Death save failed: token was not found." };

    if (!token.dying) {
      return { state: nextState, message: `${token.name} isn't making death saves right now.` };
    }
    if (token.dying.stable) {
      return { state: nextState, message: `${token.name} is already stable and doesn't need to roll.` };
    }

    const roll = rollDie(20);
    let message;

    if (roll === 20) {
      token.hp = clampNumber(1, 0, token.maxHp);
      delete token.dying;
      message = `${token.name} rolls a natural 20 on their death save and springs back to 1 HP!`;
    } else if (roll === 1) {
      token.dying.failures += 2;
      message = `${token.name} rolls a 1 on their death save -- 2 failures (${token.dying.failures}/3).`;
    } else if (roll >= 10) {
      token.dying.successes += 1;
      message = `${token.name} rolls ${roll} on their death save -- success (${token.dying.successes}/3).`;
    } else {
      token.dying.failures += 1;
      message = `${token.name} rolls ${roll} on their death save -- failure (${token.dying.failures}/3).`;
    }

    if (token.dying && token.dying.failures >= 3) {
      delete token.dying;
      token.dead = true;
      message += ` ${token.name} dies.`;
    } else if (token.dying && token.dying.successes >= 3) {
      token.dying.stable = true;
      message += ` ${token.name} stabilizes.`;
    }

    return { state: addLogEntry(nextState, message), message };
  }

  // Sets a token's exhaustion level directly (0-6, clamped) -- e.g. a DM ruling, or an
  // effect that removes it outright (Greater Restoration). Reaching level 6 kills the token
  // instantly per RAW (no save, no death-save roll), clearing any in-progress death-save
  // tracking the same way it would for any other death. Only the automatic level-based
  // effects this engine actually models are documented here -- disadvantage on attack rolls
  // and saving throws at level 3+ (see attack()/rollSavingThrow()) and halved/zeroed speed at
  // level 2+/5+ (see effectiveSpeed()) -- disadvantage on ability checks (level 1) isn't
  // modeled since ability checks aren't a mechanic this engine has at all, and a halved HP
  // maximum (level 4) isn't automated either (same known-gap spirit as Troll's Regeneration
  // or Hit Dice): halve maxHp by hand via the token editor if actual play reaches that point.
  function setExhaustion(state, tokenId, level) {
    const nextState = clone(state);
    const token = nextState.tokens.find((item) => item.id === tokenId);
    if (!token) return { state, message: "Exhaustion failed: token was not found." };

    const clamped = clampNumber(level, 0, 6);
    if (clamped > 0) token.exhaustion = clamped;
    else delete token.exhaustion;

    let message = `${token.name} is now at exhaustion level ${clamped}.`;
    if (clamped >= 6) {
      token.hp = 0;
      token.dead = true;
      delete token.dying;
      message += ` ${token.name} dies from exhaustion.`;
    }
    return { state: addLogEntry(nextState, message), message };
  }

  // Adds (or, with a negative amount, removes) exhaustion levels -- e.g. a forced march adds
  // one, Greater Restoration removes one. Delegates to setExhaustion for the clamping/death
  // handling so both paths stay consistent; default amount is 1 (gaining a single level, the
  // common case).
  function addExhaustion(state, tokenId, amount) {
    const token = state.tokens.find((item) => item.id === tokenId);
    if (!token) return { state, message: "Exhaustion failed: token was not found." };
    const current = token.exhaustion || 0;
    const delta = Number.isFinite(Number(amount)) ? Number(amount) : 1;
    return setExhaustion(state, tokenId, current + delta);
  }

  // Healing that brings a token back above 0 HP ends any in-progress death-save tracking
  // (dying or already-stable) and clears a dead flag too -- if the caller chose to heal a
  // token flagged dead, that's a deliberate narrative revival (Revivify, Raise Dead, DM
  // ruling), not something this engine should second-guess.
  function applyHealing(state, tokenId, amount) {
    const nextState = clone(state);
    const token = nextState.tokens.find((item) => item.id === tokenId);
    if (token) {
      token.hp = clampNumber(token.hp + amount, 0, token.maxHp);
      if (token.hp > 0) {
        delete token.dying;
        delete token.dead;
      }
    }
    return nextState;
  }

  function clampNumber(value, min, max) {
    const number = Number(value);
    if (!Number.isFinite(number)) return min;
    return Math.min(max, Math.max(min, Math.round(number)));
  }

  function updateToken(state, tokenId, changes) {
    const nextState = clone(state);
    const token = nextState.tokens.find((item) => item.id === tokenId);
    if (!token) return nextState;

    if (typeof changes.name === "string") {
      token.name = changes.name.trim() || token.name;
      token.icon = token.name.slice(0, 2).toUpperCase();
    }

    if (changes.maxHp !== undefined) {
      token.maxHp = clampNumber(changes.maxHp, 1, 999);
      token.hp = clampNumber(token.hp, 0, token.maxHp);
    }

    if (changes.hp !== undefined) {
      token.hp = clampNumber(changes.hp, 0, token.maxHp);
      // A manual hp edit above 0 is a deliberate correction/revival -- same reasoning as
      // applyHealing clearing dying/dead, just via the token editor instead of a heal.
      if (token.hp > 0) {
        delete token.dying;
        delete token.dead;
      }
    }

    if (changes.initiative !== undefined) {
      token.initiative = clampNumber(changes.initiative, 0, 99);
    }

    if (changes.ac !== undefined) {
      token.ac = clampNumber(changes.ac, 1, 99);
    }

    if (changes.attackBonus !== undefined) {
      token.attackBonus = clampNumber(changes.attackBonus, -20, 99);
    }

    if (typeof changes.damageDice === "string") {
      token.damageDice = changes.damageDice.trim() || token.damageDice || "1d4";
    }

    // The token's own single/primary attack damage type -- Multiattack sub-profiles
    // (token.attacks[].damageType) aren't editable here, same as attackBonus/damageDice above
    // only ever reflect the primary attack, not each Multiattack row.
    if (typeof changes.damageType === "string") {
      const trimmed = changes.damageType.trim().toLowerCase();
      if (trimmed) token.damageType = trimmed;
      else delete token.damageType;
    }

    // Whole-list replace, not a per-key merge like resources/hitDice -- there's no per-entry
    // {max,current} to preserve, just a flat set of type names, so the token sheet's comma-
    // separated text field can always submit its full current list.
    if (changes.damageResistances !== undefined) {
      const normalized = normalizeDamageTypeList(changes.damageResistances);
      if (normalized) token.damageResistances = normalized;
      else delete token.damageResistances;
    }
    if (changes.damageVulnerabilities !== undefined) {
      const normalized = normalizeDamageTypeList(changes.damageVulnerabilities);
      if (normalized) token.damageVulnerabilities = normalized;
      else delete token.damageVulnerabilities;
    }
    if (changes.damageImmunities !== undefined) {
      const normalized = normalizeDamageTypeList(changes.damageImmunities);
      if (normalized) token.damageImmunities = normalized;
      else delete token.damageImmunities;
    }

    if (changes.speed !== undefined) {
      token.speed = clampNumber(changes.speed, 0, 999);
    }

    // A manual exhaustion edit is a direct correction (like the hp branch above), not a real
    // game event -- it does NOT trigger the level-6 death that setExhaustion()/addExhaustion()
    // apply for an actual narrative gain, matching how editing hp to 0 here doesn't start
    // death saves either.
    if (changes.exhaustion !== undefined) {
      const level = clampNumber(changes.exhaustion, 0, 6);
      if (level > 0) token.exhaustion = level;
      else delete token.exhaustion;
    }

    if (changes.abilityScores !== undefined) {
      const merged = normalizeAbilityScores({ ...(token.abilityScores || {}), ...changes.abilityScores });
      if (merged) token.abilityScores = merged;
    }

    if (changes.savingThrows !== undefined) {
      const merged = normalizeSavingThrows({ ...(token.savingThrows || {}), ...changes.savingThrows });
      if (merged) token.savingThrows = merged;
    }

    if (changes.skills !== undefined) {
      const merged = normalizeSkills({ ...(token.skills || {}), ...changes.skills });
      if (merged) token.skills = merged;
    }

    if (changes.spellcasting !== undefined) {
      const merged = normalizeSpellcasting({ ...(token.spellcasting || {}), ...changes.spellcasting });
      if (merged) token.spellcasting = merged;
    }

    // Spell slots merge per-level -- a change to level 2's {max, current} pair shouldn't
    // touch level 1's, the same way updating one ability score doesn't touch the others.
    // Within a given level, the caller (the token editor's combined "current/max" field)
    // always supplies both max and current together, so a whole-entry replace is correct.
    if (changes.spellSlots !== undefined) {
      const merged = normalizeSpellSlots({ ...(token.spellSlots || {}), ...changes.spellSlots });
      if (merged) token.spellSlots = merged;
    }

    // Resources merge per-name, same as spell slots merge per-level -- but resources can
    // also be removed entirely (a resource added by mistake, or a feature retired), which
    // spell slots never need since all 9 levels always potentially apply. Setting a name's
    // value to null deletes it from the merged set before normalizing.
    if (changes.resources !== undefined) {
      const merged = { ...(token.resources || {}) };
      Object.keys(changes.resources).forEach((name) => {
        if (changes.resources[name] === null) delete merged[name];
        else merged[name] = changes.resources[name];
      });
      const normalized = normalizeResources(merged);
      if (normalized) token.resources = normalized;
      else delete token.resources;
    }

    // Hit Dice merge per die-type, same null-deletes-the-entry convention as resources above.
    if (changes.hitDice !== undefined) {
      const merged = { ...(token.hitDice || {}) };
      Object.keys(changes.hitDice).forEach((dieKey) => {
        if (changes.hitDice[dieKey] === null) delete merged[dieKey];
        else merged[dieKey] = changes.hitDice[dieKey];
      });
      const normalized = normalizeHitDice(merged);
      if (normalized) token.hitDice = normalized;
      else delete token.hitDice;
    }

    // A single tracker (not a per-name map like resources), so null clears it entirely
    // rather than needing a per-key delete.
    if (changes.legendaryActions !== undefined) {
      if (changes.legendaryActions === null) {
        delete token.legendaryActions;
      } else {
        const merged = normalizeLegendaryActions({ ...(token.legendaryActions || {}), ...changes.legendaryActions });
        if (merged) token.legendaryActions = merged;
      }
    }

    // Recharge abilities merge per-name, same null-deletes-the-entry convention as
    // resources/hitDice above.
    if (changes.rechargeAbilities !== undefined) {
      const merged = { ...(token.rechargeAbilities || {}) };
      Object.keys(changes.rechargeAbilities).forEach((name) => {
        if (changes.rechargeAbilities[name] === null) delete merged[name];
        else merged[name] = changes.rechargeAbilities[name];
      });
      const normalized = normalizeRechargeAbilities(merged);
      if (normalized) token.rechargeAbilities = normalized;
      else delete token.rechargeAbilities;
    }

    // A single {amount} tracker, same null-clears-it-entirely convention as
    // legendaryActions above.
    if (changes.regeneration !== undefined) {
      if (changes.regeneration === null || !Number.isFinite(Number(changes.regeneration.amount)) || Number(changes.regeneration.amount) <= 0) {
        delete token.regeneration;
      } else {
        token.regeneration = { amount: clampNumber(changes.regeneration.amount, 1, 999) };
      }
    }

    if (changes.extraAttacks !== undefined) {
      if (changes.extraAttacks === null || !Number.isFinite(Number(changes.extraAttacks)) || Number(changes.extraAttacks) <= 0) {
        delete token.extraAttacks;
      } else {
        token.extraAttacks = clampNumber(changes.extraAttacks, 1, 10);
      }
    }

    if (changes.visionRange !== undefined) {
      if (changes.visionRange === null || !Number.isFinite(Number(changes.visionRange)) || Number(changes.visionRange) <= 0) {
        delete token.visionRange;
      } else {
        token.visionRange = clampNumber(changes.visionRange, 1, 999);
      }
    }

    if (typeof changes.image === "string") {
      token.image = changes.image;
    }

    if (changes.hiddenFromPlayers !== undefined) {
      if (changes.hiddenFromPlayers) token.hiddenFromPlayers = true;
      else delete token.hiddenFromPlayers;
    }

    return nextState;
  }

  function setMapImage(state, mapName, image, details = {}) {
    const nextState = clone(state);
    nextState.maps = nextState.maps || {};
    nextState.maps[mapName] = {
      ...(nextState.maps[mapName] || {}),
      image,
      ...details
    };
    return nextState;
  }

  function setMapGrid(state, mapName, columns, rows) {
    const nextState = clone(state);
    nextState.maps = nextState.maps || {};
    nextState.maps[mapName] = {
      ...(nextState.maps[mapName] || {}),
      columns: clampNumber(columns, 4, 80),
      rows: clampNumber(rows, 4, 80)
    };
    nextState.tokens = nextState.tokens.map((token) => token.mapName === mapName
      ? {
          ...token,
          x: clampNumber(token.x, 1, nextState.maps[mapName].columns),
          y: clampNumber(token.y, 1, nextState.maps[mapName].rows)
        }
      : token);
    return nextState;
  }

  function setMapView(state, mapName, settings) {
    const nextState = clone(state);
    const current = nextState.maps?.[mapName] || {};
    nextState.maps = nextState.maps || {};
    nextState.maps[mapName] = {
      ...current,
      showGrid: settings.showGrid !== false,
      gridOpacity: clampNumber(settings.gridOpacity ?? current.gridOpacity ?? 35, 0, 100),
      fitMode: settings.fitMode === "contain" ? "contain" : "cover",
      tokenSize: clampNumber(settings.tokenSize ?? current.tokenSize ?? 78, 40, 100),
      feetPerSquare: clampNumber(settings.feetPerSquare ?? current.feetPerSquare ?? 5, 1, 30)
    };
    return nextState;
  }

  function currentGrid(state) {
    const mapSettings = state.maps?.[state.mapName] || {};
    return {
      columns: clampNumber(mapSettings.columns || 12, 4, 80),
      rows: clampNumber(mapSettings.rows || 8, 4, 80)
    };
  }

  // Walls (for line-of-sight -- see hasLineOfSight below) are stored per map as a plain array
  // of {x1,y1,x2,y2} segments in GRID VERTEX space -- integer coordinates 0..columns/0..rows,
  // the corners between cells, NOT the 1..columns cell-index space token x/y use. A wall runs
  // along cell boundaries (or across them, for a diagonal wall), never through a cell's
  // interior. Absent/empty is the common case (no walls drawn for this map yet) and
  // deliberately means "no line-of-sight restriction at all" -- see hasLineOfSight.
  function addWall(state, mapName, x1, y1, x2, y2) {
    const nextState = clone(state);
    nextState.maps = nextState.maps || {};
    const current = nextState.maps[mapName] || {};
    const walls = Array.isArray(current.walls) ? current.walls.slice() : [];
    walls.push({ x1, y1, x2, y2 });
    nextState.maps[mapName] = { ...current, walls };
    return nextState;
  }

  function removeWall(state, mapName, index) {
    const nextState = clone(state);
    const current = nextState.maps?.[mapName];
    if (!current || !Array.isArray(current.walls) || !current.walls[index]) return state;
    nextState.maps[mapName] = { ...current, walls: current.walls.filter((_, i) => i !== index) };
    return nextState;
  }

  function clearWalls(state, mapName) {
    const nextState = clone(state);
    const current = nextState.maps?.[mapName];
    if (!current || !Array.isArray(current.walls) || !current.walls.length) return state;
    nextState.maps[mapName] = { ...current, walls: [] };
    return nextState;
  }

  // Standard orientation-based segment intersection test (cross-product sign comparison) --
  // the textbook algorithm, not something bespoke to this file. Returns true for a proper
  // crossing OR a collinear overlap; two segments that only touch at a shared endpoint may
  // resolve either way depending on floating-point rounding, which is fine for a line-of-sight
  // check (see hasLineOfSight's own comment on why token positions never land exactly on a
  // wall vertex in practice).
  function orientation(a, b, c) {
    const val = (b.y - a.y) * (c.x - b.x) - (b.x - a.x) * (c.y - b.y);
    if (val === 0) return 0;
    return val > 0 ? 1 : 2;
  }
  function onSegment(a, b, c) {
    return Math.min(a.x, c.x) <= b.x && b.x <= Math.max(a.x, c.x)
      && Math.min(a.y, c.y) <= b.y && b.y <= Math.max(a.y, c.y);
  }
  function segmentsIntersect(p1, p2, p3, p4) {
    const o1 = orientation(p1, p2, p3);
    const o2 = orientation(p1, p2, p4);
    const o3 = orientation(p3, p4, p1);
    const o4 = orientation(p3, p4, p2);
    if (o1 !== o2 && o3 !== o4) return true;
    if (o1 === 0 && onSegment(p1, p3, p2)) return true;
    if (o2 === 0 && onSegment(p1, p4, p2)) return true;
    if (o3 === 0 && onSegment(p3, p1, p4)) return true;
    if (o4 === 0 && onSegment(p3, p2, p4)) return true;
    return false;
  }

  // Perpendicular distance from point p to segment a-b (0 if p is on the segment) -- used only
  // to hit-test "which wall did the DM click near" for deletion; not part of the line-of-sight
  // check itself.
  function distanceToSegment(p, a, b) {
    const dx = b.x - a.x;
    const dy = b.y - a.y;
    const lengthSquared = dx * dx + dy * dy;
    const t = lengthSquared === 0 ? 0 : Math.max(0, Math.min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / lengthSquared));
    const closestX = a.x + t * dx;
    const closestY = a.y + t * dy;
    return Math.hypot(p.x - closestX, p.y - closestY);
  }

  // Index of the closest wall on `mapName` to vertex-space point (x, y), within `maxDistance`
  // (in grid units, e.g. 0.5 = half a cell) -- null if none are that close. Used by the UI to
  // decide "the DM clicked near an existing wall, remove it" vs. "start drawing a new one."
  function findNearestWallIndex(state, mapName, x, y, maxDistance) {
    const walls = state.maps?.[mapName]?.walls;
    if (!Array.isArray(walls) || !walls.length) return null;
    let bestIndex = null;
    let bestDistance = maxDistance;
    walls.forEach((wall, index) => {
      const distance = distanceToSegment({ x, y }, { x: wall.x1, y: wall.y1 }, { x: wall.x2, y: wall.y2 });
      if (distance <= bestDistance) {
        bestDistance = distance;
        bestIndex = index;
      }
    });
    return bestIndex;
  }

  // AoE template shape geometry -- pure point-in-shape tests, all working in grid CELL units
  // (not feet, not percent) so callers do the feet<->cells conversion once at the boundary,
  // same layering as everywhere else distance/geometry math lives in this file. These exist so
  // ui/app.js's AoE template tool can auto-detect which tokens a drawn circle/cone/line
  // actually covers (the roadmap's "auto-target-detection" follow-up to the circle-only
  // template) rather than the DM reading it off by eye -- the template's own placement state
  // (shape, origin, angle, size) still lives in ui/app.js, not `state` (unchanged from the
  // circle-only version: purely a local UI concern, never persisted), only the shape math
  // moved here for the same testability reason segmentsIntersect/distanceToSegment did.
  function pointInCircle(px, py, centerX, centerY, radiusCells) {
    return Math.hypot(px - centerX, py - centerY) <= radiusCells;
  }

  // RAW cone geometry (SRD): "the cone's width at a given point along its length is equal to
  // that point's distance from the point of origin" -- read literally, this is a TRUE
  // TRIANGLE (apex + two straight edges), not a circular sector ("pie slice") of some fixed
  // angle -- those are different shapes: a sector bulges wider than a triangle at the same
  // along-axis distance for any point off the centerline. The correct, RAW-literal test is the
  // same rotated-frame technique pointInLine already uses (origin at the apex, axis along +x):
  // a point is in the cone if its along-axis position (localX) is within [0, length], and its
  // perpendicular offset (localY) is within half of localX itself -- literally "half-width at
  // this point along the length equals half this point's distance along the length," i.e.
  // width = distance. `angleRad` is the cone's own center-line direction (0 = +x/east,
  // increasing clockwise in screen space, matching Math.atan2(dy, dx) on screen pixel deltas).
  function pointInCone(px, py, apexX, apexY, angleRad, lengthCells) {
    const dx = px - apexX;
    const dy = py - apexY;
    const cos = Math.cos(-angleRad);
    const sin = Math.sin(-angleRad);
    const localX = dx * cos - dy * sin;
    const localY = dx * sin + dy * cos;
    if (localX < 0 || localX > lengthCells) return false;
    return Math.abs(localY) <= localX / 2;
  }

  // A line "originates from a point ... and extends [length] in a certain direction, with a
  // total length you choose" (RAW) at some fixed width (5 ft for the overwhelming majority of
  // line spells, but a caller-supplied `widthCells` rather than a hardcoded 5 ft here, since
  // it's already a per-spell UI input, not a rules constant the way the cone's angle is).
  // Tests the point by rotating it into the line's own reference frame (origin at (0,0),
  // direction along +x) rather than testing against four separately-rotated edges.
  function pointInLine(px, py, originX, originY, angleRad, lengthCells, widthCells) {
    const dx = px - originX;
    const dy = py - originY;
    const cos = Math.cos(-angleRad);
    const sin = Math.sin(-angleRad);
    const localX = dx * cos - dy * sin;
    const localY = dx * sin + dy * cos;
    return localX >= 0 && localX <= lengthCells && Math.abs(localY) <= widthCells / 2;
  }

  // True if nothing on `mapName`'s wall list blocks the straight line between grid CELL
  // coordinates (ax, ay) and (bx, by) -- both converted to their cell-center point in the same
  // vertex space walls are stored in (a cell's center sits at (index - 0.5), always a
  // half-integer, so it can never land exactly on an integer wall vertex -- side-steps the
  // "does a ray touching a wall's endpoint count as blocked" ambiguity for the common case
  // entirely, rather than needing to resolve it). No walls drawn for this map at all (the
  // overwhelmingly common case -- most maps never get any) is a fast path that skips the
  // geometry entirely and always returns true: absence of walls means no restriction, not an
  // opaque map. Walls only -- no vision RADIUS/darkvision distance limit here (see
  // cellVisibleToHero below for that layered on top) and no "dim light" gradation.
  function hasLineOfSight(state, mapName, ax, ay, bx, by) {
    const walls = state.maps?.[mapName]?.walls;
    if (!Array.isArray(walls) || !walls.length) return true;
    const p1 = { x: ax - 0.5, y: ay - 0.5 };
    const p2 = { x: bx - 0.5, y: by - 0.5 };
    return !walls.some((wall) => segmentsIntersect(p1, p2, { x: wall.x1, y: wall.y1 }, { x: wall.x2, y: wall.y2 }));
  }

  // True if `hero` (a hero-type token) can see grid cell (x, y) on `mapName` -- both a clear
  // line of sight (hasLineOfSight, walls only) AND, when hero.visionRange is set, within that
  // distance. Distance is measured with gridMoveCost's own feet-per-square + RAW alternating-
  // diagonal rule (diagonalStepsAlreadyUsed 0, a one-off static measurement, not an actual
  // move) -- the same distance the Ruler tool already shows the DM, so "how far away is that"
  // means the same thing everywhere in this app rather than introducing a second, divergent
  // notion of distance just for vision. hero.visionRange absent/not finite means unlimited
  // sight distance (sparse, same convention as every other optional numeric field in this
  // file) -- this is a flat maximum-distance limit only, NOT a full lighting model: no per-cell
  // bright/dim/dark state, no light sources, just "can this hero see this far, at all,"
  // deliberately staying a first-cut simplification rather than growing into one.
  //
  // A map with no walls drawn returns true immediately, BEFORE even considering visionRange --
  // deliberately checked here rather than left to fall through to hasLineOfSight's own "no
  // walls" fast path, so the entire vision system (range included) stays strictly opt-in via
  // drawing at least one wall, matching every other "no walls = zero restriction" default in
  // this feature set. Without this explicit check, a DM who fills in a hero's Vision Range on
  // a map that has never had a wall drawn would find monsters silently disappearing from the
  // player window with no walls involved at all -- a surprising, hard-to-explain regression on
  // a map that opted into nothing.
  function cellVisibleToHero(state, mapName, hero, x, y) {
    const walls = state.maps?.[mapName]?.walls;
    if (!Array.isArray(walls) || !walls.length) return true;
    if (!hasLineOfSight(state, mapName, hero.x, hero.y, x, y)) return false;
    if (!Number.isFinite(hero.visionRange)) return true;
    return gridMoveCost({ ...state, mapName }, hero.x, hero.y, x, y, 0).feet <= hero.visionRange;
  }

  // A token is "visible to the party" if it's itself a hero (a PC always sees itself/is always
  // shown, regardless of line of sight to its own square) or within sight (see
  // cellVisibleToHero) of at least one hero-type token on the same map -- the union of every
  // player character's vision, the standard tabletop convention ("if any one of you can see
  // it, the table sees it"). Used by the player window (ui/playerView.js) to filter tokens on
  // top of the manual hiddenFromPlayers flag, not instead of it -- a token can be both
  // technically in line of sight AND manually hidden (not yet meant to be revealed even if
  // walls would allow seeing it), and the manual flag always wins in that case (checked
  // separately by the caller).
  function isVisibleToParty(state, token) {
    if (token.type === "hero") return true;
    const heroes = tokensOnCurrentMap({ ...state, mapName: token.mapName }).filter((other) => other.type === "hero");
    if (!heroes.length) return true; // no PCs on the map at all -- nothing to hide anything from
    return heroes.some((hero) => cellVisibleToHero(state, token.mapName, hero, token.x, token.y));
  }

  // Every currently-visible cell for the party on `mapName` (union over every hero-type token
  // there, same convention as isVisibleToParty) -- an array of [x, y] cell coordinates. No
  // hero tokens on the map returns an EMPTY array, the opposite default from
  // isVisibleToParty's own "no heroes = show everything": there being no party to compute
  // visibility for is genuinely "nothing explored yet," not "nothing to hide," so this
  // shouldn't claim the whole map has been seen.
  function visibleCellsForParty(state, mapName) {
    const heroes = tokensOnCurrentMap({ ...state, mapName }).filter((token) => token.type === "hero");
    if (!heroes.length) return [];
    const grid = currentGrid({ ...state, mapName });
    const cells = [];
    for (let y = 1; y <= grid.rows; y += 1) {
      for (let x = 1; x <= grid.columns; x += 1) {
        if (heroes.some((hero) => cellVisibleToHero(state, mapName, hero, x, y))) {
          cells.push([x, y]);
        }
      }
    }
    return cells;
  }

  // Merges every currently-visible cell into `mapName`'s persisted "explored" memory
  // (state.maps[mapName].revealedTiles, a sparse {"x,y": true} map) -- the standard fog-of-war
  // three-state model (never seen / explored-but-not-currently-visible / currently visible):
  // once a tile is marked explored here it stays that way until an explicit resetFog(), even
  // as the party moves elsewhere and it drops out of current visibility. ui/app.js calls this
  // from saveEncounter() -- the one choke point virtually every mutation already flows through
  // (see the Undo bullet above for why that's a reliable hook) -- rather than from each
  // individual action that could move a hero, so there's no risk of a new movement path
  // forgetting to trigger a reveal. Skips the whole computation and returns the SAME state
  // reference for a map with no walls drawn: walls are what make hasLineOfSight (and
  // therefore visibility) mean anything at all, a wall-free map is already always fully
  // visible via isVisibleToParty's own fast path, so there's no memory worth tracking for one
  // -- this is also what keeps calling this on every save a true no-op for every map that's
  // never had a wall drawn on it (i.e. almost all of them). Also returns the same reference
  // when nothing NEW was revealed this call, matching every other no-op-means-no-clone
  // primitive in this file.
  function revealVisibleTiles(state, mapName) {
    const walls = state.maps?.[mapName]?.walls;
    if (!Array.isArray(walls) || !walls.length) return state;

    const visible = visibleCellsForParty(state, mapName);
    const current = state.maps?.[mapName]?.revealedTiles || {};
    const merged = { ...current };
    let changed = false;
    visible.forEach(([x, y]) => {
      const key = `${x},${y}`;
      if (!merged[key]) {
        merged[key] = true;
        changed = true;
      }
    });
    if (!changed) return state;

    const nextState = clone(state);
    nextState.maps[mapName] = { ...nextState.maps[mapName], revealedTiles: merged };
    return nextState;
  }

  // Forgets everything a map's revealedTiles has accumulated -- a DM control (Reset Fog) for
  // reusing a map for a different area, or deliberately re-hiding terrain. Same state
  // reference, unchanged, if there's nothing to reset (no revealedTiles at all, or already
  // empty), matching removeWall's own "rejected/no-op" convention.
  function resetFog(state, mapName) {
    const current = state.maps?.[mapName];
    if (!current || !current.revealedTiles || !Object.keys(current.revealedTiles).length) return state;
    const nextState = clone(state);
    nextState.maps[mapName] = { ...current, revealedTiles: {} };
    return nextState;
  }

  // The real-world scale of one grid square on the current map, in feet. Defaults to the
  // standard 5 ft/square (used for both distance-based movement and the diagonal-cost rule).
  function feetPerSquare(state) {
    return clampNumber(state.maps?.[state.mapName]?.feetPerSquare ?? 5, 1, 30);
  }

  // True once a map has real art or an imported campaign location behind it -- distinguishes
  // a genuinely prepared map from a bare name a token happens to reference.
  function hasRealMapData(state, mapName) {
    const mapData = state.maps?.[mapName];
    return Boolean(mapData && (mapData.image || mapData.sourcePath));
  }

  // Switches to an already-prepared map (real art or a campaign sourcePath) -- returns the
  // same state reference, unchanged, if that map doesn't exist or has no real data yet, the
  // same "rejected" convention as setTokenPosition/moveToken. Can't create a map from
  // nothing here: doing that needs image data this pure, DOM-free engine has no access to
  // (see ui/app.js's Map Library "Use" flow, which is how a map actually gets prepared).
  function setActiveMap(state, mapName) {
    if (!hasRealMapData(state, mapName)) return state;
    const nextState = clone(state);
    nextState.mapName = mapName;
    return nextState;
  }

  // PHB movement/diagonals: every *other* diagonal square moved this turn costs double a
  // normal square (5/10/5/10 ft...), not a flat cost per square. `diagonalStepsAlreadyUsed`
  // carries the parity across a token's whole turn, even across separate moveToken() calls,
  // so ending a turn mid-alternation and moving again later still charges correctly.
  function gridMoveCost(state, x1, y1, x2, y2, diagonalStepsAlreadyUsed) {
    const squareFeet = feetPerSquare(state);
    const dx = Math.abs(x2 - x1);
    const dy = Math.abs(y2 - y1);
    const diagonalSteps = Math.min(dx, dy);
    const straightSteps = Math.max(dx, dy) - diagonalSteps;
    let diagonalFeet = 0;
    for (let step = 0; step < diagonalSteps; step += 1) {
      const stepIndex = diagonalStepsAlreadyUsed + step;
      diagonalFeet += stepIndex % 2 === 0 ? squareFeet : squareFeet * 2;
    }
    return { feet: straightSteps * squareFeet + diagonalFeet, diagonalSteps };
  }

  function addLogEntry(state, text) {
    const nextState = clone(state);
    nextState.log = [text, ...(nextState.log || [])].slice(0, 12);
    return nextState;
  }

  // Rolls one d20 (or two, for advantage/disadvantage, keeping the higher/lower) and
  // reports both the chosen roll and the raw rolls behind it, so callers can show their
  // work the same way a natural-1/natural-20 already does.
  function rollD20WithMode(mode) {
    if (mode === "advantage" || mode === "disadvantage") {
      const a = rollDie(20);
      const b = rollDie(20);
      const roll = mode === "advantage" ? Math.max(a, b) : Math.min(a, b);
      return { roll, rolls: [a, b] };
    }
    return { roll: rollDie(20), rolls: [] };
  }

  // Resolves a single attack roll + damage roll against one target. `label` (an attack
  // name like "Claw") is only included in the message when set -- single-attack callers
  // leave it null so the message format matches a plain "<attacker> attacks <target>" line.
  // `forceCrit` (Paralyzed/Unconscious target within 5 ft, see forcesAutoCrit/isAdjacent)
  // upgrades a hit that already beat AC into a critical even on a non-natural-20 roll -- it
  // never turns a miss into a hit; a natural 1 still misses regardless per RAW.
  function resolveOneAttack(attacker, target, attackBonus, damageDice, mode, label, forceCrit) {
    const d20Info = rollD20WithMode(mode);
    const d20 = d20Info.roll;
    const bonus = Number(attackBonus || 0);
    const total = d20 + bonus;
    const targetAc = Number(target.ac || 10);
    const naturalCrit = d20 === 20;
    const isMiss = d20 === 1 || (!naturalCrit && total < targetAc);
    const isCritical = !isMiss && (naturalCrit || Boolean(forceCrit));
    const rollLabel = d20Info.rolls.length
      ? `${d20} (${mode}: ${d20Info.rolls.join(", ")})`
      : `${d20}`;
    const actorLabel = label ? `${attacker.name}'s ${label}` : attacker.name;

    if (isMiss) {
      return {
        damageTotal: 0,
        isCritical: false,
        message: `${actorLabel} attacks ${target.name}: ${rollLabel} + ${bonus} = ${total} vs AC ${targetAc}. Miss.`
      };
    }

    const damage = rollDice(damageDice || "1d4");
    // RAW: a critical hit doubles the damage dice only, not any flat modifier.
    const diceTotal = damage.total - damage.modifier;
    const damageTotal = isCritical ? diceTotal * 2 + damage.modifier : damage.total;
    const critText = isCritical ? " Critical hit." : "";
    return {
      damageTotal,
      isCritical,
      message: `${actorLabel} attacks ${target.name}: ${rollLabel} + ${bonus} = ${total} vs AC ${targetAc}. Hit.${critText} Damage ${damageTotal} (${damage.notation}).`
    };
  }

  // options: { advantage: bool, disadvantage: bool } -- applies to every d20 rolled this
  // call. If the attacker has an `attacks` array (Multiattack, e.g. a troll's Bite + two
  // Claws), each one resolves in order against the same target, stopping early once this
  // action's own hits leave the target at 0 HP (so a Bite that drops them doesn't also get
  // followed by two more Claws in the same action) -- except for a reaction (see below),
  // which is always exactly one attack regardless of Multiattack. This does NOT block
  // starting an attack against a target that was already at 0 HP before this call -- that's
  // a real, meaningful hit against a downed creature (an automatic failed death save, see
  // applyDamage), not a dead action; only a target removed from the map entirely stops the
  // loop outright. Exhaustion level 3+ forces disadvantage on the attacker's rolls (RAW), same
  // as rollSavingThrow -- combined with an explicit options.advantage, they cancel out per RAW
  // rather than exhaustion silently winning. Conditions add more sources on each side of that
  // same cancellation: the attacker's own Blinded/Restrained/Prone/Poisoned or the target's
  // Invisible impose disadvantage; the attacker's own Invisible or the target's
  // Restrained/Prone/Stunned/Paralyzed/Unconscious grant advantage (see ownAttackCondition*/
  // targetGrantsAttack* above).
  //
  // options.actionType: "action" (default), "bonusAction", or "reaction" -- a reaction
  // (an opportunity attack) is gated the OPPOSITE way from action/bonusAction: those are only
  // restricted on the attacker's own active turn (unrestricted outside it, so narration stays
  // free); a reaction is by definition taken on someone ELSE's turn, so it's instead gated
  // whenever turn order is running at all (state.turn.round > 0), regardless of whose turn it
  // currently is, and reset only at the start of the reacting token's own next turn (see
  // nextTurn()) -- exactly mirroring how RAW reactions actually work ("you regain your spent
  // reaction at the start of each of your turns," not at the start of the round). This engine
  // has no path-stepping between two grid coordinates (see gridMoveCost/moveToken) and so
  // cannot detect "this token just left that token's reach" on its own -- moveToken() surfaces
  // a best-effort start-vs-end adjacency hint in its own message (see tokensLeavingReach
  // below), but calling attack(..., {actionType: "reaction"}) against a specific target is
  // always a narrative judgment call left to the DM/Claude, the same "no engine-side timing
  // detection" precedent roll_death_save's "at the start of its turn" and legendary actions'
  // "at the end of another creature's turn" already use.
  function attack(state, attackerId, targetId, options = {}) {
    let nextState = clone(state);
    const activeTokens = tokensOnCurrentMap(nextState);
    const attacker = activeTokens.find((token) => token.id === attackerId);
    const target = activeTokens.find((token) => token.id === targetId);
    if (!attacker || !target) {
      return { state, message: "Attack failed: attacker or target was not found." };
    }

    // Action economy is only enforced on the attacker's own active turn for action/bonusAction
    // -- same "unrestricted outside your own turn" carve-out moveToken already uses for speed,
    // so narration/setup outside formal combat stays free. options.actionType defaults to
    // "action"; a Fighter/Barbarian's Extra Attack (token.extraAttacks, sparse, default 0)
    // lets `attack()` itself be called 1 + extraAttacks times before the action is spent --
    // this is the one action-consumer that can legitimately fire more than once, since RAW's
    // Extra Attack is "more attacks as part of the same Attack action," not a second action.
    const isActiveTurn = Boolean(state.turn && state.turn.tokenId === attackerId);
    const turnOrderRunning = Boolean(state.turn && (state.turn.round || 0) > 0);
    const actionType = options.actionType === "bonusAction" ? "bonusAction"
      : options.actionType === "reaction" ? "reaction"
      : "action";
    if (actionType === "reaction") {
      if (turnOrderRunning && attacker.reactionUsed) {
        return { state, message: `${attacker.name} has already used their reaction since their last turn.` };
      }
    } else if (isActiveTurn) {
      if (actionType === "bonusAction") {
        if (attacker.bonusActionUsed) {
          return { state, message: `${attacker.name} has already used a bonus action this turn.` };
        }
      } else {
        const attacksAllowed = 1 + (attacker.extraAttacks || 0);
        if (attacker.actionUsed || (attacker.attacksUsedThisTurn || 0) >= attacksAllowed) {
          return { state, message: `${attacker.name} has already used their action this turn.` };
        }
      }
    }

    const conditionDisadvantage = ownAttackConditionPenalty(attacker) || targetGrantsAttackDisadvantage(target);
    const conditionAdvantage = ownAttackConditionBonus(attacker) || targetGrantsAttackAdvantage(target);
    const hasDisadvantage = Boolean(options.disadvantage) || (attacker.exhaustion || 0) >= 3 || conditionDisadvantage;
    const hasAdvantage = Boolean(options.advantage) || conditionAdvantage;
    const mode = hasDisadvantage && hasAdvantage ? null : hasDisadvantage ? "disadvantage" : hasAdvantage ? "advantage" : null;
    const allProfiles = Array.isArray(attacker.attacks) && attacker.attacks.length
      ? attacker.attacks
      : [{ name: null, attackBonus: attacker.attackBonus, damageDice: attacker.damageDice, damageType: attacker.damageType }];
    // RAW: an opportunity attack is always exactly one melee attack, never a full Multiattack
    // action -- use the attacker's first/primary profile only (the same "primary attack"
    // convention campaign.js's Multiattack-row extraction already documents).
    const profiles = actionType === "reaction" ? allProfiles.slice(0, 1) : allProfiles;
    const useLabel = profiles.length > 1 || Boolean(profiles[0]?.name);

    const messages = [];
    for (const profile of profiles) {
      const liveTarget = tokensOnCurrentMap(nextState).find((token) => token.id === target.id);
      if (!liveTarget) break;

      const forceCrit = forcesAutoCrit(liveTarget) && isAdjacent(attacker, liveTarget);
      const result = resolveOneAttack(attacker, liveTarget, profile.attackBonus, profile.damageDice, mode, useLabel ? profile.name : null, forceCrit);
      messages.push(result.message);
      if (result.damageTotal > 0) {
        const damageResult = applyDamage(nextState, target.id, result.damageTotal, { critical: result.isCritical, damageType: profile.damageType });
        nextState = damageResult.state;
        if (damageResult.message) messages.push(damageResult.message);
      }

      const updatedTarget = tokensOnCurrentMap(nextState).find((token) => token.id === target.id);
      if (!updatedTarget || updatedTarget.hp <= 0) break;
    }

    const finalAttacker = nextState.tokens.find((token) => token.id === attackerId);
    if (finalAttacker) {
      if (actionType === "reaction") {
        if (turnOrderRunning) finalAttacker.reactionUsed = true;
      } else if (isActiveTurn) {
        if (actionType === "bonusAction") {
          finalAttacker.bonusActionUsed = true;
        } else {
          finalAttacker.attacksUsedThisTurn = (finalAttacker.attacksUsedThisTurn || 0) + 1;
          if (finalAttacker.attacksUsedThisTurn >= 1 + (finalAttacker.extraAttacks || 0)) {
            finalAttacker.actionUsed = true;
          }
        }
      }
    }

    const message = messages.join(" ");
    return { state: addLogEntry(nextState, message), message };
  }

  function findTokenByName(state, name) {
    const normalized = name.trim().toLowerCase();
    return tokensOnCurrentMap(state).find((token) => token.name.toLowerCase() === normalized);
  }

  function removeToken(state, tokenId) {
    const nextState = clone(state);
    nextState.tokens = nextState.tokens.filter((token) => token.id !== tokenId);
    if (nextState.selectedTokenId === tokenId) {
      nextState.selectedTokenId = sortByInitiative(tokensOnCurrentMap(nextState))[0]?.id || null;
    }
    return nextState;
  }

  function setTokenPosition(state, tokenId, x, y) {
    if (occupied(state, x, y) && !tokensOnCurrentMap(state).some((token) => token.id === tokenId && token.x === x && token.y === y)) {
      return state;
    }

    const nextState = clone(state);
    const token = nextState.tokens.find((item) => item.id === tokenId);
    if (token) {
      token.mapName = nextState.mapName;
      token.x = x;
      token.y = y;
    }
    return nextState;
  }

  // Advances the current map's turn order (sorted by initiative, same order the sidebar
  // shows) to the next token, resetting that token's movement budget for its new turn.
  // Wraps to the top of the order and increments the round counter after the last token.
  // If a token was removed since the last call (currentIndex === -1 but a turn was already
  // active), resumes at the top of the order without incrementing the round again, since we
  // can't know where in the round the missing token would have been.
  function nextTurn(state) {
    const nextState = clone(state);
    const ordered = sortByInitiative(tokensOnCurrentMap(nextState));
    if (!ordered.length) {
      nextState.turn = { tokenId: null, round: 0 };
      return nextState;
    }

    const hadActiveTurn = Boolean(nextState.turn && nextState.turn.tokenId);
    const currentIndex = ordered.findIndex((token) => token.id === nextState.turn?.tokenId);
    const round = nextState.turn?.round || 0;
    let nextIndex;
    let nextRound;

    if (currentIndex === -1) {
      nextIndex = 0;
      nextRound = hadActiveTurn ? round : round + 1;
    } else if (currentIndex === ordered.length - 1) {
      nextIndex = 0;
      nextRound = round + 1;
    } else {
      nextIndex = currentIndex + 1;
      nextRound = round;
    }

    const activeTokenId = ordered[nextIndex].id;
    nextState.turn = { tokenId: activeTokenId, round: nextRound };

    const activeToken = nextState.tokens.find((token) => token.id === activeTokenId);
    // Accumulated into one combined log entry (added once, below) rather than several --
    // same "one entry per action" convention attack()'s Multiattack loop uses, and it avoids
    // activeToken going stale: addLogEntry clones its input, so calling it more than once
    // here would silently orphan any mutation made to activeToken after the first call.
    const messages = [];
    if (activeToken) {
      activeToken.movementUsed = 0;
      activeToken.diagonalStepsThisTurn = 0;
      // Action economy resets for the newly active token, same "lives on the token, reset
      // here" convention as movementUsed above (not on state.turn) -- attack()/castSpell()
      // only read these when it's this token's own active turn, so there's nothing to
      // reset for anyone else. reactionUsed is the one exception to "only read on your own
      // turn" (a reaction is spent on someone ELSE's turn, see attack()'s own comment) but it
      // still resets the same way and at the same moment -- RAW: "you regain your spent
      // reaction at the start of each of your turns."
      delete activeToken.actionUsed;
      delete activeToken.bonusActionUsed;
      delete activeToken.attacksUsedThisTurn;
      delete activeToken.reactionUsed;
      // RAW: a legendary creature regains all expended legendary actions at the start of
      // its own turn.
      if (activeToken.legendaryActions) activeToken.legendaryActions.current = activeToken.legendaryActions.max;

      // RAW: some creatures (Troll's Regeneration) heal automatically at the start of their
      // own turn -- damage-type exceptions ("unless it took acid or fire damage since its
      // last turn") still aren't modeled even now that damage types are tracked elsewhere
      // (see damageTypeModifier): that needs a per-turn history of what type of damage a
      // token took, which nothing here keeps; skip issuing the heal by hand (via
      // updateToken/the HP panel) when that matters narratively.
      if (activeToken.regeneration && activeToken.hp > 0 && activeToken.hp < activeToken.maxHp) {
        const healed = Math.min(activeToken.regeneration.amount, activeToken.maxHp - activeToken.hp);
        activeToken.hp += healed;
        messages.push(`${activeToken.name} regenerates ${healed} HP (${activeToken.hp}/${activeToken.maxHp}).`);
      }

      // RAW: a recharge-based ability (Fire Breath, etc.) rolls a d6 at the start of the
      // token's own turn and becomes available again on a roll >= its rechargeMin -- only
      // abilities already spent (available: false) roll at all.
      if (activeToken.rechargeAbilities) {
        Object.keys(activeToken.rechargeAbilities).forEach((name) => {
          const ability = activeToken.rechargeAbilities[name];
          if (ability.available) return;
          const roll = rollDie(6);
          if (roll >= ability.rechargeMin) {
            ability.available = true;
            messages.push(`${activeToken.name}'s ${name} recharges! (rolled ${roll})`);
          }
        });
      }
    }

    return messages.length ? addLogEntry(nextState, messages.join(" ")) : nextState;
  }

  // The speed actually usable this turn once exhaustion's movement penalties are applied
  // (RAW: halved at level 2+, reduced to 0 at level 5+ -- the two thresholds don't stack
  // further beyond that). `token.speed` itself always stays the creature's true,
  // unpenalized speed, so the penalty can't accidentally become permanent if exhaustion is
  // later removed.
  function effectiveSpeed(token) {
    if (hasCondition(token, "Grappled") || hasCondition(token, "Restrained")) return 0;
    const base = Number(token.speed ?? 30);
    const level = token.exhaustion || 0;
    if (level >= 5) return 0;
    if (level >= 2) return Math.floor(base / 2);
    return base;
  }

  // A cheap, honest APPROXIMATION of "did this move leave anyone's reach" -- start-vs-end
  // adjacency only (isAdjacent, the same one-square/5 ft melee-range proxy used elsewhere in
  // this file), not a real square-by-square leaves-reach-mid-path detection: this engine has
  // no path-stepping between two grid coordinates at all (gridMoveCost only computes a
  // distance/cost total, see its own comment), so it genuinely cannot tell whether the mover
  // passed through and back out of a third token's reach without ending outside it, or the
  // reverse (ending outside reach without ever technically "leaving" it under a stricter
  // reading). Returns the names of every living token the mover WAS adjacent to before the
  // move and ISN'T adjacent to after -- purely informational, folded into moveToken()'s own
  // message as a hint; never blocks the move or spends anyone's reaction itself. The DM/Claude
  // still has to decide whether to actually call attack(mover excluded, ..., {actionType:
  // "reaction"}) against one of the names returned.
  function tokensLeavingReach(beforeState, afterState, moverId) {
    const before = tokensOnCurrentMap(beforeState).find((t) => t.id === moverId);
    const after = tokensOnCurrentMap(afterState).find((t) => t.id === moverId);
    if (!before || !after) return [];
    return tokensOnCurrentMap(afterState)
      .filter((other) => other.id !== moverId && !other.dead && (other.hp || 0) > 0)
      .filter((other) => isAdjacent(before, other) && !isAdjacent(after, other))
      .map((other) => other.name);
  }

  function reachHint(beforeState, afterState, moverId) {
    const names = tokensLeavingReach(beforeState, afterState, moverId);
    return names.length ? ` This may provoke an opportunity attack from ${names.join(", ")}.` : "";
  }

  // Speed-limited move for the token whose turn is currently active (per state.turn) --
  // computes the RAW grid cost (see gridMoveCost) against that token's remaining movement
  // this turn and rejects the move (same state reference, like setTokenPosition's occupied-
  // tile rejection) if it can't afford it. A token that ISN'T the active turn moves freely
  // via setTokenPosition underneath -- this only enforces speed on your own turn, the same
  // as a real table: setting a scene or repositioning NPCs outside combat stays unrestricted.
  function moveToken(state, tokenId, x, y) {
    const token = tokensOnCurrentMap(state).find((item) => item.id === tokenId);
    if (!token) return { state, message: "Move failed: token was not found." };

    const isActiveTurn = Boolean(state.turn && state.turn.tokenId === tokenId);
    if (!isActiveTurn) {
      const moved = setTokenPosition(state, tokenId, x, y);
      if (moved === state) return { state, message: `${token.name} could not move to (${x}, ${y}) -- tile occupied.` };
      return { state: moved, message: `${token.name} moves to (${x}, ${y}).${reachHint(state, moved, tokenId)}` };
    }

    const speed = effectiveSpeed(token);
    const used = Number(token.movementUsed || 0);
    const diagonalUsed = Number(token.diagonalStepsThisTurn || 0);
    const remaining = speed - used;
    const cost = gridMoveCost(state, token.x, token.y, x, y, diagonalUsed);

    if (cost.feet > remaining) {
      return {
        state,
        message: `${token.name} can't reach (${x}, ${y}) -- needs ${cost.feet} ft of movement, only ${remaining} ft left this turn (speed ${speed} ft).`
      };
    }

    const moved = setTokenPosition(state, tokenId, x, y);
    if (moved === state) return { state, message: `${token.name} could not move to (${x}, ${y}) -- tile occupied.` };

    const movedToken = moved.tokens.find((item) => item.id === tokenId);
    movedToken.movementUsed = used + cost.feet;
    movedToken.diagonalStepsThisTurn = diagonalUsed + cost.diagonalSteps;
    return {
      state: moved,
      message: `${token.name} moves to (${x}, ${y}) -- ${cost.feet} ft (${remaining - cost.feet} ft left this turn).${reachHint(state, moved, tokenId)}`
    };
  }

  function toggleCondition(state, tokenId, condition) {
    const nextState = clone(state);
    const token = nextState.tokens.find((item) => item.id === tokenId);
    if (!token) return nextState;

    if (token.conditions.includes(condition)) {
      token.conditions = token.conditions.filter((item) => item !== condition);
    } else {
      token.conditions.push(condition);
    }

    return nextState;
  }

  function parseCommand(state, command) {
    const normalized = command.toLowerCase();
    const countWords = { one: 1, two: 2, three: 3, four: 4, five: 5, six: 6 };
    const countPattern = "(one|two|three|four|five|six|\\d+)";
    const monsterPattern = "(goblin|orc|troll|bandit|wolf|hellhound|skeleton|zombie|ghoul|ogre|owlbear|worg|giant spider|cultist|guard|priest|brown bear|dire wolf|bugbear|hobgoblin|gnoll|specter|imp|veteran)s?";
    const actionFirst = new RegExp(`(?:spawn|summon|emerge|appear|add).*?${countPattern}\\s+${monsterPattern}`);
    const countFirst = new RegExp(`${countPattern}\\s+${monsterPattern}.*?(?:spawn|summon|emerge|appear|add)`);
    const spawnMatch = normalized.match(actionFirst) || normalized.match(countFirst);

    // Strip a trailing "with advantage"/"at disadvantage" phrase before matching the
    // attacker/target names, otherwise it gets swallowed into the target name.
    const disadvantageSuffix = /\s+(?:with disadvantage|at disadvantage)\s*[.!?]?$/i;
    const advantageSuffix = /\s+(?:with advantage|at advantage)\s*[.!?]?$/i;
    let attackOptions = {};
    let attackCommand = command;
    if (disadvantageSuffix.test(command)) {
      attackOptions = { disadvantage: true };
      attackCommand = command.replace(disadvantageSuffix, "");
    } else if (advantageSuffix.test(command)) {
      attackOptions = { advantage: true };
      attackCommand = command.replace(advantageSuffix, "");
    }
    const attackMatch = attackCommand.match(/^(.+?)\s+attacks?\s+(.+?)[.!?]?$/i);

    const saveMatch = command.match(
      /^(.+?)\s+(?:makes?|rolls?)\s+an?\s+(strength|dexterity|constitution|intelligence|wisdom|charisma|str|dex|con|int|wis|cha)\s+sav(?:e|ing throw)s?\s+(?:against|vs\.?)?\s*dc\s*(\d+)/i
    );
    if (saveMatch) {
      const token = findTokenByName(state, saveMatch[1]);
      if (!token) return { state, message: "I could not find who's making the save." };
      return rollSavingThrow(state, token.id, saveMatch[2], Number(saveMatch[3]));
    }

    // "<name> rolls/makes a <skill or ability> check against DC <n>" -- e.g. "Sael rolls a
    // Perception check against DC 15" or "Darkhawk makes a Strength check against DC 20"
    // for an unnamed check. `<skill or ability>` is free text since several skill names are
    // multi-word ("Animal Handling", "Sleight of Hand") -- rollAbilityCheck itself validates
    // it against SKILL_LIST/ABILITY_KEYS and fails outright if it matches neither.
    const checkMatch = command.match(
      /^(.+?)\s+(?:makes?|rolls?)\s+an?\s+([a-z ]+?)\s+check\s+(?:against|vs\.?)?\s*dc\s*(\d+)/i
    );
    if (checkMatch) {
      const token = findTokenByName(state, checkMatch[1]);
      if (!token) return { state, message: "I could not find who's making the check." };
      return rollAbilityCheck(state, token.id, checkMatch[2].trim(), Number(checkMatch[3]));
    }

    // "<caster> casts <spell> [at <target>] (cantrip|Nth level[, concentration]) [for <damage
    // dice>]" -- the level/cantrip parenthetical is required so this can't misfire on
    // ordinary narration that happens to contain the word "casts". "at <target>" + "for
    // <dice>" together trigger a spell attack roll; either or both may be omitted for a
    // no-attack-roll spell (buffs, utility, or a save the DM resolves separately). The
    // trailing ", concentration" flag starts (and, if something else was already active,
    // ends) concentration on this cast -- see castSpell's own comment for the RAW behind it.
    const castMatch = command.match(
      /^(.+?)\s+casts?\s+(.+?)(?:\s+at\s+(.+?))?\s*\((cantrip|[1-9](?:st|nd|rd|th))(?:\s+level)?(,\s*concentration)?\)(?:\s+for\s+(\d*d\d+(?:\s*[+-]\s*\d+)?))?\s*[.!?]?$/i
    );

    // "<caster> casts <spell> on <target1>, <target2>, ... (Nth level, <ability> save DC
    // <n>) for <damage dice>" -- an area/multi-target spell (Fireball, etc.) resolved
    // atomically via castAreaSpell: one damage roll, one save per target, half damage on a
    // success (see castAreaSpell's own comment for why this needs to be one call, not a
    // cast_spell + N separate saving_throw commands). Checked BEFORE castMatch above,
    // since castMatch's more permissive "at <target>" is optional and would otherwise
    // swallow "<spell> on <targets> (...)" whole into its own spellName group.
    const areaCastMatch = command.match(
      /^(.+?)\s+casts?\s+(.+?)\s+on\s+(.+?)\s*\((cantrip|[1-9](?:st|nd|rd|th))(?:\s+level)?,\s*(strength|dexterity|constitution|intelligence|wisdom|charisma|str|dex|con|int|wis|cha)\s+sav(?:e|ing throw)\s+dc\s*(\d+)\)\s+for\s+(\d*d\d+(?:\s*[+-]\s*\d+)?)\s*[.!?]?$/i
    );
    if (areaCastMatch) {
      const caster = findTokenByName(state, areaCastMatch[1]);
      if (!caster) return { state, message: "I could not find who's casting." };
      const targetNames = areaCastMatch[3].split(/\s*,\s*|\s+and\s+/i).map((name) => name.trim()).filter(Boolean);
      const targetIds = [];
      for (const name of targetNames) {
        const token = findTokenByName(state, name);
        if (!token) return { state, message: `I could not find "${name}" among the spell's targets.` };
        targetIds.push(token.id);
      }
      const level = areaCastMatch[4].toLowerCase() === "cantrip" ? 0 : Number(areaCastMatch[4].match(/\d/)[0]);
      return castAreaSpell(state, caster.id, {
        spellName: areaCastMatch[2].trim(),
        level,
        targetIds,
        saveAbility: areaCastMatch[5],
        saveDC: Number(areaCastMatch[6]),
        damageDice: areaCastMatch[7].replace(/\s+/g, "")
      });
    }

    // "<caster> stops concentrating" / "<caster> drops concentration" -- voluntarily ends
    // whatever that token is concentrating on, same as the token sheet's Drop Concentration
    // button.
    const dropConcentrationMatch = command.match(/^(.+?)\s+(?:stops?\s+concentrating|drops?\s+concentration)\s*[.!?]?$/i);
    if (dropConcentrationMatch) {
      const token = findTokenByName(state, dropConcentrationMatch[1]);
      if (!token) return { state, message: "I could not find who's concentrating." };
      return dropConcentration(state, token.id);
    }

    // "<name> rolls a death save" / "<name> rolls a death saving throw" -- same roll the
    // token sheet's Roll Death Save button makes.
    const deathSaveMatch = command.match(/^(.+?)\s+rolls?\s+an?\s+death\s+sav(?:e|ing throw)s?\s*[.!?]?$/i);
    if (deathSaveMatch) {
      const token = findTokenByName(state, deathSaveMatch[1]);
      if (!token) return { state, message: "I could not find who's rolling a death save." };
      return rollDeathSave(state, token.id);
    }

    // "<name> takes a long rest" / "<name> takes a short rest" -- same as the token sheet's
    // Long Rest/Short Rest buttons.
    const restMatch = command.match(/^(.+?)\s+takes?\s+an?\s+(long|short)\s+rest\s*[.!?]?$/i);
    if (restMatch) {
      const token = findTokenByName(state, restMatch[1]);
      if (!token) return { state, message: "I could not find who's resting." };
      return restMatch[2].toLowerCase() === "long" ? longRest(state, token.id) : shortRest(state, token.id);
    }

    // "<name> gains a level of exhaustion" / "<name> gains 2 levels of exhaustion" /
    // "<name> loses a level of exhaustion" -- same roll the token sheet's +1/-1 Level
    // buttons make.
    const exhaustionMatch = command.match(/^(.+?)\s+(gains?|loses?)\s+(?:an?|(\d+))\s+levels?\s+of\s+exhaustion\s*[.!?]?$/i);
    if (exhaustionMatch) {
      const token = findTokenByName(state, exhaustionMatch[1]);
      if (!token) return { state, message: "I could not find who's gaining or losing exhaustion." };
      const amount = exhaustionMatch[3] ? Number(exhaustionMatch[3]) : 1;
      const signedAmount = exhaustionMatch[2].toLowerCase().startsWith("lose") ? -amount : amount;
      return addExhaustion(state, token.id, signedAmount);
    }

    // "<name> spends a hit die" / "<name> spends 2 d10 hit dice" -- same roll the token
    // sheet's Spend Hit Die control makes. The die type defaults to whichever single type
    // the token has if only one is tracked (most non-multiclass PCs); a multiclassed token
    // with more than one die type tracked must name which one ("d10 hit dice") explicitly.
    const hitDiceMatch = command.match(/^(.+?)\s+spends?\s+(?:an?|(\d+))\s+(d\d+\s+)?hit\s+(?:die|dice)\s*[.!?]?$/i);
    if (hitDiceMatch) {
      const token = findTokenByName(state, hitDiceMatch[1]);
      if (!token) return { state, message: "I could not find who's spending Hit Dice." };
      const count = hitDiceMatch[2] ? Number(hitDiceMatch[2]) : 1;
      const dieTypes = Object.keys(token.hitDice || {});
      const dieType = hitDiceMatch[3] ? hitDiceMatch[3].trim().toLowerCase() : dieTypes[0];
      if (!dieType) return { state, message: `${token.name} has no Hit Dice tracked.` };
      if (!hitDiceMatch[3] && dieTypes.length > 1) {
        return { state, message: `${token.name} tracks more than one Hit Dice type (${dieTypes.join(", ")}) -- say which one, e.g. "spends 2 ${dieTypes[0]} hit dice".` };
      }
      return spendHitDie(state, token.id, dieType, count);
    }

    // "<name> uses a legendary action" / "<name> uses 2 legendary actions" -- same as the
    // token sheet's Use Legendary Action button.
    const legendaryMatch = command.match(/^(.+?)\s+uses?\s+(?:an?|(\d+))\s+legendary\s+actions?\s*[.!?]?$/i);
    if (legendaryMatch) {
      const token = findTokenByName(state, legendaryMatch[1]);
      if (!token) return { state, message: "I could not find who's using a legendary action." };
      const cost = legendaryMatch[2] ? Number(legendaryMatch[2]) : 1;
      return useLegendaryAction(state, token.id, cost);
    }

    // "Lair action: <what happens>" -- triggers the current map's once-per-round lair
    // action, same as the Lair Action control.
    const lairActionMatch = command.match(/^lair\s+action:?\s*(.+?)\s*[.!?]?$/i);
    if (lairActionMatch) {
      return triggerLairAction(state, lairActionMatch[1].trim());
    }
    if (castMatch) {
      const caster = findTokenByName(state, castMatch[1]);
      if (!caster) return { state, message: "I could not find who's casting." };
      let target = null;
      if (castMatch[3]) {
        target = findTokenByName(state, castMatch[3]);
        if (!target) return { state, message: "I could not find the spell's target." };
      }
      const level = castMatch[4].toLowerCase() === "cantrip" ? 0 : Number(castMatch[4].match(/\d/)[0]);
      return castSpell(state, caster.id, {
        level,
        spellName: castMatch[2].trim(),
        targetId: target ? target.id : null,
        concentration: Boolean(castMatch[5]),
        damageDice: castMatch[6] ? castMatch[6].replace(/\s+/g, "") : undefined
      });
    }

    if (attackMatch) {
      const attacker = findTokenByName(state, attackMatch[1]);
      const target = findTokenByName(state, attackMatch[2]);
      if (!attacker || !target) {
        return { state, message: "I could not find the attacker or target." };
      }
      return attack(state, attacker.id, target.id, attackOptions);
    }

    if (spawnMatch) {
      const count = countWords[spawnMatch[1]] || Number(spawnMatch[1]);
      const result = spawnMonster(state, spawnMatch[2], count);
      return {
        state: result.state,
        message: `${result.spawned.map((token) => token.name).join(", ")} joined the encounter.`
      };
    }

    return { state, message: "I understood the narration, but no tool action matched yet." };
  }

  window.CampaignOS = {
    ABILITY_KEYS,
    SKILL_LIST,
    abilityCheckBonus,
    abilityModifier,
    addExhaustion,
    addLogEntry,
    addWall,
    applyDamage,
    applyHealing,
    attack,
    addToken,
    castAreaSpell,
    castSpell,
    clearWalls,
    conditionList,
    createState,
    DAMAGE_TYPE_LIST,
    damageTypeModifier,
    dropConcentration,
    currentGrid,
    effectiveSpeed,
    encounterMultiplier,
    evaluateEncounterDifficulty,
    feetPerSquare,
    findNearestWallIndex,
    gridMoveCost,
    hasCondition,
    hasLineOfSight,
    hasRealMapData,
    isVisibleToParty,
    longRest,
    resetFog,
    revealVisibleTiles,
    visibleCellsForParty,
    moveToken,
    nextTurn,
    parseCommand,
    pointInCircle,
    pointInCone,
    pointInLine,
    removeToken,
    restoreResource,
    rollAbilityCheck,
    rollFreeform,
    rollInitiative,
    setExhaustion,
    spendHitDie,
    shortRest,
    rollDeathSave,
    rollSavingThrow,
    savingThrowBonus,
    triggerLairAction,
    useLegendaryAction,
    useRechargeAbility,
    useResource,
    removeWall,
    setActiveMap,
    setMapGrid,
    setMapImage,
    setMapView,
    setTokenPosition,
    sortByInitiative,
    tokensLeavingReach,
    tokensOnCurrentMap,
    toggleCondition,
    updateToken,
    XP_THRESHOLDS_BY_LEVEL
  };
})();
