extends Node2D

@export var depth : int = 6
@export var tileset : TileSet

@export_category("Sources")
@export var wall : TileMapLayer
@export var decor : TileMapLayer
@export var decor_light : TileMapLayer

@export_category("Top Layers")
@export var top_layer : CanvasLayer
@export var top_layer_2 : CanvasLayer

@onready var max_scale : float = Global.top_scale

var tilesets_copy : PackedStringArray = []
var tilesets_generated := !Global.tile_maps.is_empty()

var tilemap_generated := false

var decor_generated : TileMapLayer
var decor_light_generated : TileMapLayer

func user_tile_res(n : int, m : int) -> String:
    return "user://Tileset.map.%d-%d.res" % [m, n]

func _enter_tree() -> void:
    Global.scene_tree.current_scene.ready.connect(init_tile_sets)

func init_tile_sets() -> void:
    if !tilesets_generated:
        for n : int in depth:
            tilesets_copy.append(user_tile_res(n, 1))
            if n < depth - 2:
                tilesets_copy.append(user_tile_res(n, 2))
                if n == depth - 3:
                    tilesets_copy.append(user_tile_res(n, 3))

        for res : String in tilesets_copy:
            ResourceSaver.save(tileset, res)
            Global.tile_maps[res] = ResourceLoader.load(res, "TileSet")

    call_deferred(&"generate_layers")

signal layers_generated

func generate_layers() -> void:

    for n : CanvasLayer in [top_layer, top_layer_2]:
        n.call_deferred(&"add_child", Global.canvas_modulate.instantiate())
        n.follow_viewport_scale = max_scale
        n.follow_viewport_enabled = true
        n.visible = true

    top_layer_2.follow_viewport_scale = max_scale + 0.15

    for d in wall.get_children():
        if d is TileMapLayer:
            d.add_to_group(d.name)

    for n : int in depth:
        var layer := CanvasLayer.new()
        var wall_layer : TileMapLayer = wall.duplicate()
        var wall_tile_set : TileSet = Global.tile_maps[user_tile_res(n, 1)]

        layer.name = str(n)
        layer.layer = 0
        layer.follow_viewport_enabled = true
        layer.follow_viewport_scale = remap(n, 0, depth - 1, 1.0, max_scale)

        wall_layer.modulate = Color.WHITE

        if !tilesets_generated:
            if n != 0:
                wall_layer.collision_enabled = false

            if n == depth - 1:
                wall_tile_set.set_occlusion_layer_light_mask(0, 1)
            else:
                wall_tile_set.remove_occlusion_layer(0)

        wall_layer.tile_set = wall_tile_set
        layer.call_deferred(&"add_child", wall_layer)
        layer.call_deferred(&"add_child", Global.canvas_modulate.instantiate())

        if n < depth - 2:
            var decor_layer : TileMapLayer = decor.duplicate()

            decor_layer.tile_set = Global.tile_maps[user_tile_res(n, 2)]
            decor_layer.collision_enabled = true
            decor_layer.navigation_enabled = false
            layer.call_deferred(&"add_child", decor_layer)

            decor_generated = decor_layer

            if n == depth - 3: # Tileset level lights
                var decor_light_layer : TileMapLayer = decor_light.duplicate()

                decor_light_layer.tile_set = Global.tile_maps[user_tile_res(n, 3)]
                decor_light_layer.collision_enabled = false
                decor_light_layer.navigation_enabled = false

                decor_light_generated = decor_light_layer
                layer.call_deferred(&"add_child", decor_light_layer)

        call_deferred(&"add_child", layer)

    var top_layer_tiles : Node2D = top_layer.get_node(^"Tiles")
    var top_layer_2_tiles : Node2D = top_layer_2.get_node(^"Tiles")

    top_layer_tiles.modulate = Color.WHITE
    top_layer_2_tiles.modulate = Color.WHITE

    for tilemap : Node in (
        top_layer_tiles.get_children(true) +
        top_layer_2_tiles.get_children(true)
       ):
        if tilemap is TileMapLayer:
            tilemap.tile_set = tilemap.tile_set.duplicate()
            tilemap.tile_set.remove_occlusion_layer(0)

            tilemap.add_to_group(&"tilemap_modulate", true)
            tilemap.collision_enabled = false
            tilemap.navigation_enabled = false

    for f : TileMapLayer in [
        wall,
        decor,
        decor_light,
    ]: f.queue_free()

    patch_decor()
    layers_generated.emit()

@export_category("Patches")
@export var collision_patch : TileMapLayer

func patch_decor() -> void:
    const vector2i_2_0 := Vector2i(2, 0)
    # 64^2
    for _64 : Vector2i in [
            Vector2i(1, 5),
            Vector2i(3, 5),
            Vector2i(5, 5),
            Vector2i(7, 5),
        ]:
        for pos in decor_generated.get_used_cells_by_id(2, _64):
            for n in 4:
                collision_patch.set_cell(
                    pos + Vector2i(n % 2, floori(n * .5)),
                    1, vector2i_2_0
                )
