extends Node2D

const TILE_W: float = 64.0
const TILE_H: float = 32.0
const TERRAIN_RENDERER_SCRIPT := preload("res://scripts/shared/iso_terrain_renderer.gd")

var time: float = 0.0
var map_offset: Vector2 = Vector2.ZERO
var viewport_size: Vector2 = Vector2.ZERO
var _renderer = TERRAIN_RENDERER_SCRIPT.new()

func _ready() -> void:
	_renderer.chunk_size = 16
	_renderer.configure_seed(0xBB_11_22)

func _draw() -> void:
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return
	var origin: Vector2 = Vector2(
		viewport_size.x * 0.5 - map_offset.x,
		viewport_size.y * 0.58 - map_offset.y
	)
	_renderer.draw_tiles(self, origin, viewport_size, TILE_W, TILE_H, 3)
