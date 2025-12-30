# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

ROYALTIM-3 is a 3D top-down battle royale game built with **Godot 4.5.1** featuring anthropomorphic vegetables and fruits as characters. The game uses a procedurally generated hexagonal map with a destruction system instead of a shrinking zone.

## Running the Project

Open the project in Godot 4.5.1 and run `scenes/MainMenuScene.tscn`.

### Running Tests

Tests use GUT (Godot Unit Testing). Run via: `Project -> Tools -> Run Tests` in the Godot editor.

Test files are in `tests/`:
- `test_components.gd` - Component system tests
- `test_inventory.gd` - Inventory tests
- `test_abilities.gd` - Ability tests
- `test_hex_grid.gd` - Hexagonal grid tests

## Architecture

### Component-Based System

The project uses a component-based architecture (ECS-like) where entities are composed of modular components.

**Base classes:**
- `Component` (`core/components/Component.gd`) - RefCounted base class with `entity` reference, `enabled` state, and `update(delta)` method
- `Entity` (`core/entities/Entity.gd`) - Node3D that holds a dictionary of components, calls `update()` on enabled components each frame

**Key components** (in `core/components/`):
- `MovementComponent` - Movement handling
- `HealthComponent` - Health and damage
- `CombatComponent` - Combat system
- `AbilityComponent` - Ability management
- `InventoryComponent` - Item inventory
- `NetworkingComponent` - Network synchronization

### Ability System

Located in `abilities/`:
- `Ability.gd` - Base class with cooldown system
- `ActiveAbility.gd` - Abilities activated by player (has `activate(entity, target_position)`, `duration`, signals)
- `PassiveAbility.gd` - Always-active abilities (override `_apply_passive(entity)`)

To add a new ability:
1. Create class extending `ActiveAbility` or `PassiveAbility`
2. Override `_on_activate()` for active or `_apply_passive()` for passive
3. Reference in character data

### Network Architecture

Server-authoritative multiplayer using ENet:
- **Server** (`network/server/`): `GameServer`, `ServerWorld`, `ServerPlayer`, `TickSystem`
- **Client** (`network/client/`): `GameClient`, `ClientWorld`
- **Sync** (`network/sync/`): `NetworkSync`

**Autoloads** (singletons):
- `NetworkManager` - Manages server/client lifecycle
- `GameManager` - Game state management

**Data flow:**
1. Client sends input to server via RPC
2. Server processes input authoritatively
3. Server broadcasts world state to all clients
4. Clients interpolate received state

**Tick rates:**
- `TickSystem`: 20 ticks/sec for game logic
- State sync: 10 times/sec

### World Generation

Located in `world/generation/`:
- `HexGenerator.gd` - Generates hexagonal grid structure
- `HexGrid.gd` - Grid management
- `HexTile.gd` - Individual tile representation
- `MapGenerator.gd` - Orchestrates map generation

### Map Destruction System

Located in `world/destruction/`:
- `DestructionSystem.gd` - Controls map destruction timing
- `TileDestroyer.gd` - Handles individual tile destruction

Replaces traditional battle royale zone by progressively destroying tiles.

### Resource Types

Located in `core/resources/`:
- `CharacterData` - Character stats (health, speed) and ability references
- `WeaponData` - Weapon properties
- `ItemData` - Item definitions
- `AbilityData` - Ability configuration

### Adding New Content

**New character:**
1. Create resource file in `characters/data/` extending `CharacterData`
2. Set `character_name`, `base_health`, `base_speed`
3. Assign active/passive abilities

**New item:**
1. Create class in `inventory/items/` extending `ItemData`
2. Add to loot tables in `inventory/loot/`

## Key Input Actions

Defined in `project.godot`: `move_up/down/left/right`, `attack`, `interact`, `inventory`, `pause`, `ability_1-4`