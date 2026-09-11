(function () {
  // Builds a new level-1+ 5e character sheet from a form draft: computes the derived
  // numbers (modifiers, proficiency bonus, HP, saves, skills, AC, attack) a real sheet
  // needs, then renders markdown matching the DnD repo's characters/_template.md shape
  // (plus an "### Attacks" table, since engine/campaign.js's extractPrimaryAttack looks
  // for one -- without it, a token spawned from this character would fall back to a
  // generic attack instead of the one just built here).

  const CLASS_LIST = [
    "Barbarian", "Bard", "Cleric", "Druid", "Fighter", "Monk",
    "Paladin", "Ranger", "Rogue", "Sorcerer", "Warlock", "Wizard"
  ];

  const HIT_DIE_BY_CLASS = {
    Barbarian: 12,
    Fighter: 10, Paladin: 10, Ranger: 10,
    Bard: 8, Cleric: 8, Druid: 8, Monk: 8, Rogue: 8, Warlock: 8,
    Sorcerer: 6, Wizard: 6
  };

  const SAVE_PROFICIENCIES_BY_CLASS = {
    Barbarian: ["STR", "CON"], Fighter: ["STR", "CON"],
    Bard: ["DEX", "CHA"], Rogue: ["DEX", "INT"], Monk: ["STR", "DEX"], Ranger: ["STR", "DEX"],
    Cleric: ["WIS", "CHA"], Warlock: ["WIS", "CHA"], Paladin: ["WIS", "CHA"],
    Druid: ["INT", "WIS"], Wizard: ["INT", "WIS"],
    Sorcerer: ["CON", "CHA"]
  };

  const ABILITY_NAMES = {
    STR: "Strength", DEX: "Dexterity", CON: "Constitution",
    INT: "Intelligence", WIS: "Wisdom", CHA: "Charisma"
  };

  const ABILITY_KEYS = ["STR", "DEX", "CON", "INT", "WIS", "CHA"];

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

  function clampLevel(level) {
    return Math.min(Math.max(Math.round(Number(level) || 1), 1), 20);
  }

  function abilityModifier(score) {
    return Math.floor((Number(score) - 10) / 2);
  }

  function formatModifier(mod) {
    return mod >= 0 ? `+${mod}` : `${mod}`;
  }

  function proficiencyBonus(level) {
    return 2 + Math.floor((clampLevel(level) - 1) / 4);
  }

  function averageHitDieRoll(hitDie) {
    return Math.floor(hitDie / 2) + 1;
  }

  function computeHp(className, level, conModifier) {
    const hitDie = HIT_DIE_BY_CLASS[className] || 8;
    const lvl = clampLevel(level);
    let hp = Math.max(1, hitDie + conModifier);
    for (let i = 2; i <= lvl; i += 1) {
      hp += Math.max(1, averageHitDieRoll(hitDie) + conModifier);
    }
    return hp;
  }

  function computeSavingThrows(className, abilityModifiers, prof) {
    const proficient = SAVE_PROFICIENCIES_BY_CLASS[className] || [];
    return proficient.map((key) => ({
      ability: key,
      bonus: abilityModifiers[key] + prof
    }));
  }

  function computeSkills(proficientSkillNames, abilityModifiers, prof) {
    const proficient = new Set(proficientSkillNames || []);
    return SKILL_LIST
      .filter((skill) => proficient.has(skill.name))
      .map((skill) => ({ name: skill.name, bonus: abilityModifiers[skill.ability] + prof }));
  }

  function computeAc(abilityModifiers, override) {
    const overrideNumber = Number(override);
    if (Number.isFinite(overrideNumber) && String(override).trim() !== "") return overrideNumber;
    return 10 + abilityModifiers.DEX;
  }

  function computePassivePerception(abilityModifiers, proficientSkillNames, prof) {
    const isProficient = (proficientSkillNames || []).includes("Perception");
    return 10 + abilityModifiers.WIS + (isProficient ? prof : 0);
  }

  function computeAttack(attackDraft, abilityModifiers, prof) {
    const ability = attackDraft?.ability === "DEX" ? "DEX" : "STR";
    const diceSize = attackDraft?.diceSize || "1d6";
    const mod = abilityModifiers[ability];
    return {
      weaponName: attackDraft?.weaponName || "Weapon",
      toHit: prof + mod,
      damageDice: mod === 0 ? diceSize : `${diceSize}${formatModifier(mod)}`,
      // Defaults to bludgeoning (an unarmed strike's real RAW type) rather than an arbitrary
      // martial-weapon guess when the form draft doesn't specify one.
      damageType: attackDraft?.damageType || "bludgeoning"
    };
  }

  // Takes the raw form draft and returns every derived number/string the markdown
  // template needs, in one place, so callers (tests, the markdown builder, a future UI
  // preview) don't each have to re-derive the same math.
  function computeCharacter(draft) {
    const className = CLASS_LIST.includes(draft.className) ? draft.className : "Fighter";
    const level = clampLevel(draft.level);
    const abilityScores = ABILITY_KEYS.reduce((acc, key) => {
      acc[key] = Math.min(Math.max(Math.round(Number(draft.abilityScores?.[key]) || 10), 1), 30);
      return acc;
    }, {});
    const abilityModifiers = ABILITY_KEYS.reduce((acc, key) => {
      acc[key] = abilityModifier(abilityScores[key]);
      return acc;
    }, {});
    const prof = proficiencyBonus(level);
    const proficientSkills = Array.isArray(draft.proficientSkills) ? draft.proficientSkills : [];

    const spellAbility = draft.spellcasting?.isCaster
      ? (ABILITY_KEYS.includes(draft.spellcasting.ability) ? draft.spellcasting.ability : "INT")
      : null;

    return {
      name: String(draft.name || "").trim() || "Unnamed Character",
      race: String(draft.race || "").trim(),
      className,
      level,
      background: String(draft.background || "").trim(),
      alignment: String(draft.alignment || "").trim(),
      abilityScores,
      abilityModifiers,
      proficiencyBonus: prof,
      hitDie: HIT_DIE_BY_CLASS[className] || 8,
      hp: computeHp(className, level, abilityModifiers.CON),
      ac: computeAc(abilityModifiers, draft.ac),
      speed: Math.round(Number(draft.speed)) || 30,
      initiativeBonus: abilityModifiers.DEX,
      passivePerception: computePassivePerception(abilityModifiers, proficientSkills, prof),
      savingThrows: computeSavingThrows(className, abilityModifiers, prof),
      skills: computeSkills(proficientSkills, abilityModifiers, prof),
      languages: String(draft.languages || "").trim(),
      toolsWeaponsArmor: String(draft.toolsWeaponsArmor || "").trim(),
      features: String(draft.features || "").trim(),
      spellcasting: spellAbility ? {
        ability: spellAbility,
        dc: 8 + prof + abilityModifiers[spellAbility],
        attackBonus: prof + abilityModifiers[spellAbility],
        spellsKnown: String(draft.spellcasting.spellsKnown || "").trim()
      } : null,
      equipment: String(draft.equipment || "").trim(),
      personality: {
        traits: String(draft.personality?.traits || "").trim(),
        ideals: String(draft.personality?.ideals || "").trim(),
        bonds: String(draft.personality?.bonds || "").trim(),
        flaws: String(draft.personality?.flaws || "").trim()
      },
      backstory: String(draft.backstory || "").trim(),
      attack: computeAttack(draft.attack, abilityModifiers, prof)
    };
  }

  function bulletList(text, fallback) {
    const lines = String(text || "").split(/\r?\n/).map((line) => line.trim()).filter(Boolean);
    if (!lines.length) return `- ${fallback}`;
    return lines.map((line) => (line.startsWith("-") ? line : `- ${line}`)).join("\n");
  }

  function singleLine(text, fallback) {
    const value = String(text || "").replace(/\s*\r?\n\s*/g, " ").trim();
    return value || fallback;
  }

  function characterMarkdown(c) {
    const scoreCells = ABILITY_KEYS.map((key) => `${c.abilityScores[key]} (${formatModifier(c.abilityModifiers[key])})`);
    const savingThrowsText = c.savingThrows.length
      ? c.savingThrows.map((s) => `${ABILITY_NAMES[s.ability]} ${formatModifier(s.bonus)}`).join(", ")
      : "—";
    const skillsText = c.skills.length
      ? c.skills.map((s) => `${s.name} ${formatModifier(s.bonus)}`).join(", ")
      : "—";
    const spell = c.spellcasting;

    return [
      `# ${c.name}`,
      "",
      `**Race:** ${c.race || "—"}`,
      `**Class & Level:** ${c.className} ${c.level}`,
      `**Background:** ${c.background || "—"}`,
      `**Alignment:** ${c.alignment || "—"}`,
      "",
      "## Ability Scores",
      "| STR | DEX | CON | INT | WIS | CHA |",
      "|-----|-----|-----|-----|-----|-----|",
      `| ${scoreCells.join(" | ")} |`,
      "",
      "## Combat",
      `- **AC:** ${c.ac}`,
      `- **HP:** ${c.hp} / ${c.hp}`,
      `- **Hit Dice:** ${c.level}d${c.hitDie}`,
      `- **Speed:** ${c.speed} ft.`,
      `- **Initiative bonus:** ${formatModifier(c.initiativeBonus)}`,
      `- **Passive Perception:** ${c.passivePerception}`,
      `- **Proficiency bonus:** ${formatModifier(c.proficiencyBonus)}`,
      "",
      "### Attacks",
      "| Weapon | To Hit | Damage |",
      "|---|---|---|",
      `| ${c.attack.weaponName} | ${formatModifier(c.attack.toHit)} | ${c.attack.damageDice} ${c.attack.damageType} |`,
      "",
      "## Proficiencies & Skills",
      `- **Saving throws:** ${savingThrowsText}`,
      `- **Skills:** ${skillsText}`,
      `- **Languages:** ${c.languages || "—"}`,
      `- **Tools/weapons/armor:** ${c.toolsWeaponsArmor || "—"}`,
      "",
      "## Features & Traits",
      bulletList(c.features, "—"),
      "",
      "## Spellcasting (if applicable)",
      `- Spellcasting ability: ${spell ? ABILITY_NAMES[spell.ability] : "N/A"}`,
      `- Spell save DC / attack bonus: ${spell ? `${spell.dc} / ${formatModifier(spell.attackBonus)}` : "N/A"}`,
      `- Spells known/prepared: ${spell ? (spell.spellsKnown || "—") : "N/A"}`,
      "",
      "## Equipment",
      bulletList(c.equipment, "—"),
      "",
      "## Personality",
      `- Traits: ${singleLine(c.personality.traits, "—")}`,
      `- Ideals: ${singleLine(c.personality.ideals, "—")}`,
      `- Bonds: ${singleLine(c.personality.bonds, "—")}`,
      `- Flaws: ${singleLine(c.personality.flaws, "—")}`,
      "",
      "## Backstory",
      c.backstory || "—",
      "",
      "## Current Status",
      "- Conditions: none",
      "- Inspiration: no",
      "- Notes: —",
      ""
    ].join("\n");
  }

  function fileNameForCharacter(name) {
    const cleaned = String(name || "Character").trim().replace(/[\\/:*?"<>|]/g, "").replace(/\s+/g, " ");
    return `${cleaned || "Character"}.md`;
  }

  function validateDraft(draft) {
    const errors = [];
    if (!String(draft.name || "").trim()) errors.push("Name is required.");
    if (!CLASS_LIST.includes(draft.className)) errors.push("Class must be one of the standard 5e classes.");
    ABILITY_KEYS.forEach((key) => {
      const score = Number(draft.abilityScores?.[key]);
      if (!Number.isFinite(score) || score < 1 || score > 30) errors.push(`${ABILITY_NAMES[key]} score must be between 1 and 30.`);
    });
    return errors;
  }

  window.CampaignOSCharacterCreator = {
    CLASS_LIST,
    SKILL_LIST,
    ABILITY_NAMES,
    ABILITY_KEYS,
    abilityModifier,
    formatModifier,
    proficiencyBonus,
    computeHp,
    computeCharacter,
    characterMarkdown,
    fileNameForCharacter,
    validateDraft
  };
})();
