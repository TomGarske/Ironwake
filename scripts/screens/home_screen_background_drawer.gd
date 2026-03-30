extends Node2D

const TILE_W: float = 64.0
const TILE_H: float = 32.0
const TERRAIN_RENDERER_SCRIPT: GDScript = preload("res://scripts/shared/iso_terrain_renderer.gd")
const MapProfile := preload("res://scripts/shared/ironwake_map_profile.gd")

var time: float = 0.0
var map_offset: Vector2 = Vector2.ZERO
var viewport_size: Vector2 = Vector2.ZERO
var _renderer = TERRAIN_RENDERER_SCRIPT.new()
var _layout: Dictionary = {}
var _focus_world: Vector2 = Vector2.ZERO

func _ready() -> void:
	_layout = MapProfile.configure_renderer(_renderer)
	_focus_world = MapProfile.get_default_view_focus(_layout)

func _draw() -> void:
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return
	var origin: Vector2 = MapProfile.world_focus_to_origin(viewport_size, _focus_world, TILE_W, TILE_H, 1.0) - map_offset
	_renderer.draw_tiles(self, origin, viewport_size, TILE_W, TILE_H, 2)
	MapProfile.draw_map_overlay(self, origin, TILE_W, TILE_H, _layout, time)
