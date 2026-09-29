## What the special biomes do to whoever stands in them (HexGenerator._add_special_biomes places
## them in patches). Walking effects (speed, grip) come from the tile under the feet
## (MovementComponent.terrain_biome, the same on server and client); healing, thorns and the
## mushrooms' recharge run in StatusComponent (health only on the server); hiding and sight look
## the biome up by position (VisibilitySystem, ServerVisibility). The HUD shows the effect you are
## in, the guide lists them all (Encyclopedia).
extends RefCounted
class_name BiomeRules

const MEADOW_HEAL: float = 3.0         # HP per second on the flower meadow
const FROST_SPEED: float = 1.2         # faster on the frost...
const FROST_GRIP: float = 0.22         # ...but you slide: acceleration and braking are this weak
const TALL_GRASS_SPEED: float = 0.85
const MUSHROOM_RECHARGE: float = 0.6   # abilities recharge this much faster among the mushrooms...
const MUSHROOM_SIGHT: float = 0.7      # ...but the spores cut your sight
const THORNS_DAMAGE: float = 4.0       # HP per second in the brambles
const THORNS_SPEED: float = 0.75
const TICK: float = 0.5                # healing / thorns are dealt in steps this long

## Biome of the tile at a world position (-1 off the map)
static func biome_at(grid: HexGrid, pos: Vector3) -> int:
	if not grid or not is_instance_valid(grid):
		return -1
	var tile = grid.get_tile(grid.world_to_hex(pos - grid.global_position))
	return tile.biome_type if tile and not tile.is_destroyed else -1

## Tall grass hides you like a bush
static func hides(grid: HexGrid, pos: Vector3) -> bool:
	return biome_at(grid, pos) == HexTile.BiomeType.TALL_GRASS

static func sight_factor(grid: HexGrid, pos: Vector3) -> float:
	return MUSHROOM_SIGHT if biome_at(grid, pos) == HexTile.BiomeType.MUSHROOM else 1.0

## Acceleration / braking on this ground (1 = normal)
static func grip(biome: int) -> float:
	return FROST_GRIP if biome == HexTile.BiomeType.FROST else 1.0

## Name, what it does, color, good for you? - HUD pill and guide
static func describe(biome: int) -> Array:
	match biome:
		HexTile.BiomeType.MEADOW:
			return ["Flower meadow", Locale.t("Heals %d HP per second") % int(MEADOW_HEAL), Color(1.0, 0.55, 0.8), true]
		HexTile.BiomeType.FROST:
			return ["Frost", Locale.t("Faster, but slippery"), Color(0.6, 0.88, 1.0), true]
		HexTile.BiomeType.TALL_GRASS:
			return ["Tall grass", Locale.t("Hides you like a bush, slows you a little"), Color(0.8, 0.9, 0.35), true]
		HexTile.BiomeType.MUSHROOM:
			return ["Mushroom grove", Locale.t("Abilities recharge faster, the spores cut your sight"), Color(0.75, 0.5, 1.0), true]
		HexTile.BiomeType.THORNS:
			return ["Brambles", Locale.t("Thorns: %d damage per second, slow going") % int(THORNS_DAMAGE), Color(1.0, 0.4, 0.35), false]
	return []

const SPECIAL = [HexTile.BiomeType.MEADOW, HexTile.BiomeType.FROST, HexTile.BiomeType.TALL_GRASS,
	HexTile.BiomeType.MUSHROOM, HexTile.BiomeType.THORNS]
