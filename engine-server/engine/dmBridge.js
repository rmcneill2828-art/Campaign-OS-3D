(function () {
  // Translates the structured actions the dm-bridge watcher's Claude call returns
  // (see dm-bridge/watch.js) into real CampaignOS engine calls. Kept separate from
  // encounter.js/campaign.js since this is glue for one specific input source
  // (the bridge), not core encounter or campaign-import logic.

  function findTokenByName(state, name) {
    const normalized = String(name || "").trim().toLowerCase();
    return window.CampaignOS.tokensOnCurrentMap(state).find((token) => token.name.toLowerCase() === normalized);
  }

  function appendLog(state, message) {
    if (!message) return state;
    return { ...state, log: [message, ...(state.log || [])].slice(0, 12) };
  }

  // Applies one action against `state`, returning the next state, the action's
  // resulting description (or null if nothing worth describing happened -- e.g. an
  // unresolved token name), and whether that description is already sitting in
  // state.log (attack() logs its own message internally; appending it again there
  // would double it up, but callers that want the full text regardless -- like the
  // session transcript -- still need it back).
  function applyAction(state, action) {
    switch (action.type) {
      case "spawn_monster": {
        // spawnMonster itself isn't part of CampaignOS's public API (see encounter.js) --
        // parseCommand's natural-language spawn phrasing is the supported entry point,
        // and it already produces the right stat block, naming, and log message.
        const result = window.CampaignOS.parseCommand(state, `spawn ${action.count} ${action.monster}`);
        return { state: result.state, message: result.message, alreadyLogged: false };
      }
      case "attack": {
        const attacker = findTokenByName(state, action.attacker);
        const target = findTokenByName(state, action.target);
        if (!attacker || !target) {
          return {
            state,
            message: `(DM assistant) could not resolve "${action.attacker}" attacking "${action.target}".`,
            alreadyLogged: false
          };
        }
        const result = window.CampaignOS.attack(state, attacker.id, target.id, {
          advantage: Boolean(action.advantage),
          disadvantage: Boolean(action.disadvantage),
          actionType: action.actionType === "bonusAction" ? "bonusAction"
            : action.actionType === "reaction" ? "reaction"
            : "action"
        });
        return { state: result.state, message: result.message, alreadyLogged: true };
      }
      case "apply_damage": {
        const target = findTokenByName(state, action.target);
        if (!target) return { state, message: `(DM assistant) could not find "${action.target}" to damage.`, alreadyLogged: false };
        // applyDamage only returns a message when the target was concentrating (a
        // concentration-check result to fold in) -- it never self-logs, so this base
        // "takes N damage" line plus whatever it reports still goes through appendLog below
        // as one combined entry, same as attack()/castSpell() fold it into their own message.
        const result = window.CampaignOS.applyDamage(state, target.id, action.amount, { damageType: action.damageType });
        const baseMessage = `${target.name} takes ${action.amount} damage.`;
        return {
          state: result.state,
          message: result.message ? `${baseMessage} ${result.message}` : baseMessage,
          alreadyLogged: false
        };
      }
      case "apply_healing": {
        const target = findTokenByName(state, action.target);
        if (!target) return { state, message: `(DM assistant) could not find "${action.target}" to heal.`, alreadyLogged: false };
        return {
          state: window.CampaignOS.applyHealing(state, target.id, action.amount),
          message: `${target.name} heals ${action.amount} HP.`,
          alreadyLogged: false
        };
      }
      case "toggle_condition": {
        const target = findTokenByName(state, action.target);
        if (!target) return { state, message: `(DM assistant) could not find "${action.target}".`, alreadyLogged: false };
        const hadCondition = target.conditions.includes(action.condition);
        return {
          state: window.CampaignOS.toggleCondition(state, target.id, action.condition),
          message: `${target.name} is ${hadCondition ? "no longer" : "now"} ${action.condition}.`,
          alreadyLogged: false
        };
      }
      case "set_visibility": {
        const target = findTokenByName(state, action.target);
        if (!target) return { state, message: `(DM assistant) could not find "${action.target}" to change visibility.`, alreadyLogged: false };
        return {
          state: window.CampaignOS.updateToken(state, target.id, { hiddenFromPlayers: Boolean(action.hidden) }),
          message: `${target.name} is now ${action.hidden ? "hidden from" : "visible to"} players.`,
          alreadyLogged: false
        };
      }
      case "add_wall": {
        if (!state.mapName) return { state, message: "(DM assistant) no active map to add a wall to.", alreadyLogged: false };
        return {
          state: window.CampaignOS.addWall(state, state.mapName, action.x1, action.y1, action.x2, action.y2),
          message: `A wall appears on ${state.mapName}.`,
          alreadyLogged: false
        };
      }
      case "remove_wall_near": {
        if (!state.mapName) return { state, message: "(DM assistant) no active map to remove a wall from.", alreadyLogged: false };
        // A wider threshold than the UI's own click-to-delete (0.35) -- Claude is estimating a
        // coordinate from narration, not clicking a pixel, so it needs more slack to land near
        // the wall it actually means.
        const index = window.CampaignOS.findNearestWallIndex(state, state.mapName, action.x, action.y, 0.75);
        if (index === null) {
          return { state, message: `(DM assistant) no wall found near (${action.x}, ${action.y}) on ${state.mapName}.`, alreadyLogged: false };
        }
        return {
          state: window.CampaignOS.removeWall(state, state.mapName, index),
          message: `A wall on ${state.mapName} is removed.`,
          alreadyLogged: false
        };
      }
      case "move_token": {
        const target = findTokenByName(state, action.target);
        if (!target) return { state, message: `(DM assistant) could not find "${action.target}" to move.`, alreadyLogged: false };
        const grid = window.CampaignOS.currentGrid(state);
        const x = Math.min(Math.max(Math.round(Number(action.x)), 1), grid.columns);
        const y = Math.min(Math.max(Math.round(Number(action.y)), 1), grid.rows);
        // moveToken enforces speed only when `target` is the currently active turn's token
        // (state.turn.tokenId) -- otherwise it behaves exactly like the old unconstrained
        // setTokenPosition, so narration outside formal combat/turn order isn't restricted.
        const result = window.CampaignOS.moveToken(state, target.id, x, y);
        return { state: result.state, message: result.message, alreadyLogged: false };
      }
      case "next_turn": {
        const nextState = window.CampaignOS.nextTurn(state);
        const activeToken = window.CampaignOS.tokensOnCurrentMap(nextState).find((token) => token.id === nextState.turn.tokenId);
        return {
          state: nextState,
          message: activeToken ? `Round ${nextState.turn.round} -- ${activeToken.name}'s turn.` : "No tokens on this map to run initiative for.",
          alreadyLogged: false
        };
      }
      case "saving_throw": {
        const target = findTokenByName(state, action.target);
        if (!target) return { state, message: `(DM assistant) could not find "${action.target}" for a saving throw.`, alreadyLogged: false };
        // rollSavingThrow uses the target's real ability modifier (or a stated save bonus
        // from their sheet) and only reports pass/fail -- it does not apply a follow-up
        // effect (e.g. half damage on success). A separate apply_damage/toggle_condition
        // action, decided from the reported result, covers that.
        const result = window.CampaignOS.rollSavingThrow(state, target.id, action.ability, action.dc);
        return { state: result.state, message: result.message, alreadyLogged: true };
      }
      case "ability_check": {
        const target = findTokenByName(state, action.target);
        if (!target) return { state, message: `(DM assistant) could not find "${action.target}" for an ability check.`, alreadyLogged: false };
        // rollAbilityCheck resolves target.skill against a named skill's stated override
        // (or the ability modifier of its governing ability) or a bare ability with no
        // named skill -- same one-roll, pass/fail-only shape as saving_throw.
        const result = window.CampaignOS.rollAbilityCheck(state, target.id, action.skill, action.dc);
        return { state: result.state, message: result.message, alreadyLogged: true };
      }
      case "cast_spell": {
        const caster = findTokenByName(state, action.caster);
        if (!caster) return { state, message: `(DM assistant) could not find "${action.caster}" to cast a spell.`, alreadyLogged: false };
        const target = action.target ? findTokenByName(state, action.target) : null;
        // castSpell handles everything: consuming the caster's slot at `level` (0 for a
        // cantrip, never consumes one), and -- only when a target is given -- rolling a
        // spell attack against it with the caster's stated spell attack bonus. A spell
        // that instead calls for a saving throw has no target/damageDice here; Claude
        // issues a separate saving_throw action per target this same response using the
        // caster's stated spell save DC, same one-shot-batch pattern as any other save.
        const result = window.CampaignOS.castSpell(state, caster.id, {
          level: action.level,
          spellName: action.spell,
          targetId: target ? target.id : null,
          damageDice: action.damageDice,
          damageType: action.damageType,
          concentration: Boolean(action.concentration),
          advantage: Boolean(action.advantage),
          disadvantage: Boolean(action.disadvantage),
          actionType: action.actionType === "bonusAction" ? "bonusAction" : "action"
        });
        return { state: result.state, message: result.message, alreadyLogged: true };
      }
      case "cast_area_spell": {
        const caster = findTokenByName(state, action.caster);
        if (!caster) return { state, message: `(DM assistant) could not find "${action.caster}" to cast an area spell.`, alreadyLogged: false };
        const targetIds = [];
        for (const name of action.targets || []) {
          const target = findTokenByName(state, name);
          if (!target) return { state, message: `(DM assistant) could not find "${name}" among the area spell's targets.`, alreadyLogged: false };
          targetIds.push(target.id);
        }
        // castAreaSpell resolves the whole spell in one call: spends the slot, rolls one
        // damage total for the area, and rolls each target's own save against it -- full
        // damage on a failure, half (or none, if halfOnSave is explicitly false) on a
        // success -- so Claude doesn't need a separate saving_throw per target the way a
        // single-target cast_spell does.
        const result = window.CampaignOS.castAreaSpell(state, caster.id, {
          level: action.level,
          spellName: action.spell,
          targetIds,
          saveAbility: action.saveAbility,
          saveDC: action.saveDC,
          damageDice: action.damageDice,
          damageType: action.damageType,
          halfOnSave: action.halfOnSave === undefined ? true : Boolean(action.halfOnSave),
          concentration: Boolean(action.concentration)
        });
        return { state: result.state, message: result.message, alreadyLogged: true };
      }
      case "use_resource": {
        const target = findTokenByName(state, action.target);
        if (!target) return { state, message: `(DM assistant) could not find "${action.target}" to use a resource.`, alreadyLogged: false };
        const result = window.CampaignOS.useResource(state, target.id, action.resource, action.amount);
        return { state: result.state, message: result.message, alreadyLogged: true };
      }
      case "spend_hit_die": {
        const target = findTokenByName(state, action.target);
        if (!target) return { state, message: `(DM assistant) could not find "${action.target}" to spend Hit Dice.`, alreadyLogged: false };
        const result = window.CampaignOS.spendHitDie(state, target.id, action.die, action.count);
        return { state: result.state, message: result.message, alreadyLogged: true };
      }
      case "drop_concentration": {
        const target = findTokenByName(state, action.target);
        if (!target) return { state, message: `(DM assistant) could not find "${action.target}" to drop concentration.`, alreadyLogged: false };
        const result = window.CampaignOS.dropConcentration(state, target.id);
        return { state: result.state, message: result.message, alreadyLogged: true };
      }
      case "roll_death_save": {
        const target = findTokenByName(state, action.target);
        if (!target) return { state, message: `(DM assistant) could not find "${action.target}" to roll a death save.`, alreadyLogged: false };
        const result = window.CampaignOS.rollDeathSave(state, target.id);
        return { state: result.state, message: result.message, alreadyLogged: true };
      }
      case "long_rest": {
        const target = findTokenByName(state, action.target);
        if (!target) return { state, message: `(DM assistant) could not find "${action.target}" to rest.`, alreadyLogged: false };
        const result = window.CampaignOS.longRest(state, target.id);
        return { state: result.state, message: result.message, alreadyLogged: true };
      }
      case "short_rest": {
        const target = findTokenByName(state, action.target);
        if (!target) return { state, message: `(DM assistant) could not find "${action.target}" to rest.`, alreadyLogged: false };
        const result = window.CampaignOS.shortRest(state, target.id);
        return { state: result.state, message: result.message, alreadyLogged: true };
      }
      case "add_exhaustion": {
        const target = findTokenByName(state, action.target);
        if (!target) return { state, message: `(DM assistant) could not find "${action.target}" for exhaustion.`, alreadyLogged: false };
        const result = window.CampaignOS.addExhaustion(state, target.id, action.amount);
        return { state: result.state, message: result.message, alreadyLogged: true };
      }
      case "use_legendary_action": {
        const target = findTokenByName(state, action.target);
        if (!target) return { state, message: `(DM assistant) could not find "${action.target}" to use a legendary action.`, alreadyLogged: false };
        const result = window.CampaignOS.useLegendaryAction(state, target.id, action.cost);
        return { state: result.state, message: result.message, alreadyLogged: true };
      }
      case "use_recharge_ability": {
        const target = findTokenByName(state, action.target);
        if (!target) return { state, message: `(DM assistant) could not find "${action.target}" to use a recharge ability.`, alreadyLogged: false };
        const result = window.CampaignOS.useRechargeAbility(state, target.id, action.ability);
        return { state: result.state, message: result.message, alreadyLogged: true };
      }
      case "trigger_lair_action": {
        const result = window.CampaignOS.triggerLairAction(state, action.description);
        return { state: result.state, message: result.message, alreadyLogged: true };
      }
      case "switch_map": {
        const mapName = String(action.map || "").trim();
        const nextState = window.CampaignOS.setActiveMap(state, mapName);
        if (nextState === state) {
          return { state, message: `(DM assistant) could not find a prepared map named "${action.map}".`, alreadyLogged: false };
        }
        return { state: nextState, message: `The scene shifts to ${mapName}.`, alreadyLogged: false };
      }
      default:
        return { state, message: null, alreadyLogged: false };
    }
  }

  // Applies a whole actions array in order -- sequential application (re-resolving
  // token names against the *current* state after each step) matters because a
  // spawn_monster action is routinely followed by attack actions targeting the
  // monsters it just created (e.g. "Goblin 1" doesn't exist until spawn runs).
  // Returns every action's description in `messages`, in order, regardless of
  // whether it's also in state.log -- callers building a longer-lived record (the
  // session transcript) need the full list, not just what fits in the 12-entry cap.
  function applyActions(state, actions) {
    let nextState = state;
    const messages = [];
    (actions || []).forEach((action) => {
      const result = applyAction(nextState, action);
      if (result.message) {
        messages.push(result.message);
        nextState = result.alreadyLogged ? result.state : appendLog(result.state, result.message);
      } else {
        nextState = result.state;
      }
    });
    return { state: nextState, messages };
  }

  window.CampaignOSDMBridge = {
    applyActions,
    findTokenByName
  };
})();
