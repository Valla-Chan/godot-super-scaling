# [Godot Super Scaling]
# created by Andres Hernandez
# modified for Ghodost2D by Allison Ghost
class_name SuperScaler
extends Node

enum {USAGE_3D, USAGE_2D}
const epsilon := 0.01

'''CATEGORY''' export var _c_nodes:int
export (Array, NodePath) var included_nodes = [null] # Include the game world.
export (NodePath) var game_ui = null # Path to game UI
'''CATEGORY''' export var _c_viewport:int
export (float, 0.1, 4.0) var scale_factor = 1.0 setget change_scale_factor
export (float, 0.0, 1.0) var smoothness = 1.0 setget change_smoothness
export (bool) var enable_on_play = false
export (bool) var use_transparency = true
export (int, "3D", "2D") var usage = 1
export (int, "Disabled", "2X", "4X", "8X", "16X") var msaa = 0 setget change_msaa
export (bool) var fxaa = false setget change_fxaa
export (int, 1, 4096) var shadow_atlas = 1 setget change_shadow_atlas

onready var viewport_base_node = $Base
onready var sampler_shader = load(get_script().resource_path.get_base_dir() + "/SuperScaling.tres")
var sampler_material : ShaderMaterial
var game_nodes = []
var overlay : ColorRect
var viewport : Viewport
var viewport_size : Vector2
var root_viewport : Viewport
var native_resolution : Vector2
var original_resolution : Vector2
var native_aspect_ratio : float
var original_aspect_ratio : float
var finish_timer : float

var use_greenscreen := false

var image_alpha = 1.0 setget set_image_alpha

# Return the node where objects are attached.
func get_base_node() -> Node2D:
	return viewport_base_node

# Get a node by name or index from the affected_nodes[] list.
func get_node(idx = 0) -> Node:
	if idx is int:
		if idx > -1 && idx < game_nodes.size():
			return game_nodes[idx]
	elif idx is String:
		for node in game_nodes:
			if node.name == idx:
				return node
	return null

func _ready():
	if get_parent().name == "SceneBase":
		GlEnts.superscaler = self
	viewport_base_node = find_node("Base")
	if (enable_on_play):
		_finish_setup()
	else:
		_pull_game_nodes()

func _finish_setup() -> void:
	_pull_game_nodes()
	_remove_nodes()
	_get_screen_size()
	_create_viewport()
	_add_nodes()
	self.call_deferred("add_child", viewport)
	self.rect_position -= (viewport.size / 4)
	original_resolution = native_resolution
	original_aspect_ratio = native_aspect_ratio
	root_viewport = get_viewport()
	#warning-ignore:RETURN_VALUE_DISCARDED
	viewport.connect("size_changed", self, "_on_window_resize")
	#warning-ignore:RETURN_VALUE_DISCARDED
	root_viewport.connect("size_changed", self, "_on_window_resize")
	_on_window_resize()
	_create_sampler()
	_set_shader_texture()
	change_msaa(msaa)
	change_fxaa(fxaa)
	change_smoothness(smoothness)
	#set_process_input(false)
	#set_process_unhandled_input(false)

func _pull_game_nodes():
	for index in included_nodes.size():
		if included_nodes[index] is NodePath:
			game_nodes.append(get_node_or_null(included_nodes[index]))
	# get camera from game ui node
	if game_ui is NodePath:
		game_nodes.append(get_node_or_null(game_ui).get_node("Camera"))
	
func _remove_nodes() -> void:
	for node in game_nodes:
		if node != self && is_instance_valid(node):
			node.get_parent().call_deferred("remove_child", node)
	
func _add_nodes() -> void:
	self.remove_child(viewport_base_node)
	viewport.call_deferred("add_child", viewport_base_node)
	for node in game_nodes:
		viewport_base_node = viewport_base_node
		viewport_base_node.call_deferred("add_child", node)

func _create_viewport() -> void:
	viewport = Viewport.new()
	viewport.name = "Viewport"
	viewport.size = native_resolution
	viewport.usage = Viewport.USAGE_2D if usage == USAGE_2D else Viewport.USAGE_3D
	viewport.transparent_bg = true if use_transparency else false
	viewport.render_target_clear_mode = Viewport.CLEAR_MODE_ALWAYS if use_transparency else Viewport.CLEAR_MODE_NEVER
	viewport.render_target_update_mode = Viewport.UPDATE_ALWAYS
	viewport.render_target_v_flip = true
	viewport.size_override_stretch = true
	viewport.msaa = Viewport.MSAA_DISABLED
	viewport.shadow_atlas_size = shadow_atlas
	
func _create_sampler() -> void:
	overlay = ColorRect.new()
	overlay.name = "SamplerOverlay"
	sampler_material = ShaderMaterial.new()
	sampler_material.shader = sampler_shader
	overlay.material = sampler_material
	overlay.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(overlay)

func _set_shader_texture() -> void:
	yield(VisualServer, "frame_post_draw")
	var view_texture : Texture = viewport.get_texture()
	view_texture.flags = 0
	view_texture.viewport_path = viewport.get_path()
	sampler_material.set_shader_param("viewport", view_texture)
	#sampler_material.set_shader_param("use_greenscreen", use_greenscreen)
	change_scale_factor(scale_factor)
	#set_process_input(true)
	#set_process_unhandled_input(true)
	
func _set_shader_resolution() -> void:
	if sampler_material:
		sampler_material.set_shader_param("view_resolution", viewport_size)
	
func _get_screen_size() -> void:
	#var window = OS.window_size
	var window = GlUtility.get_precalculated_desired_window_size()
	native_resolution = window
	native_aspect_ratio = native_resolution.x / native_resolution.y

func _set_viewport_size() -> void:
	var res_float = native_resolution * scale_factor
	viewport_size = Vector2(round(res_float.x), round(res_float.y))
	var aspect_setting = _get_aspect_setting()
	if native_aspect_ratio and original_aspect_ratio and (aspect_setting != "ignore" and aspect_setting != "expand"):
		var aspect_diff = native_aspect_ratio / original_aspect_ratio
		if usage == USAGE_2D:
			if aspect_diff > 1.0 + epsilon and aspect_setting == "keep_width":
				viewport_size = Vector2(round(res_float.y * native_aspect_ratio), round(res_float.y))
			elif aspect_diff < 1.0 - epsilon and aspect_setting == "keep_height":
				viewport_size = Vector2(round(res_float.x), round(res_float.y / native_aspect_ratio))	
		elif usage == USAGE_3D:
			if aspect_diff > 1.0 + epsilon:
				viewport_size = Vector2(round(res_float.x / aspect_diff), round(res_float.y))
			elif aspect_diff < 1.0 - epsilon:
				viewport_size = Vector2(round(res_float.x), round(res_float.y * aspect_diff))
	
func _resize_viewport() -> void:
	if viewport:
		viewport.size = viewport_size
			
func _scale_viewport_canvas() -> void:
	if viewport:
		var aspect_setting = _get_aspect_setting()
		var aspect_diff = native_aspect_ratio / original_aspect_ratio
		if aspect_setting == "ignore":
			viewport.set_size_override(true, original_resolution)
		elif aspect_setting == "expand":
			viewport.set_size_override(true, native_resolution)
		else:
			if usage == USAGE_2D:
				if aspect_diff < 1.0 - epsilon and aspect_setting == "keep_width":
					viewport.set_size_override(true, Vector2(round(original_resolution.x), round(original_resolution.x / native_aspect_ratio)))
				elif aspect_diff > 1.0 + epsilon and aspect_setting == "keep_height":
					viewport.set_size_override(true, Vector2(round(original_resolution.y * native_aspect_ratio), round(original_resolution.y)))
				else:
					viewport.set_size_override(true, original_resolution)
			elif usage == USAGE_3D:
				if aspect_diff > 1.0 + epsilon:
					viewport.set_size_override(true, Vector2(round(original_resolution.x * aspect_diff), round(original_resolution.y)))
				elif aspect_diff < 1.0 - epsilon:
					viewport.set_size_override(true, Vector2(round(original_resolution.x), round(original_resolution.y / aspect_diff)))
			
func _set_sampler_size() -> void:
	if overlay:
		var stretch_setting = _get_stretch_setting()
		var aspect_setting = _get_aspect_setting()
		var aspect_diff = native_aspect_ratio / original_aspect_ratio
		if usage == USAGE_2D:
			if aspect_diff < 1.0 - epsilon and aspect_setting == "keep_width":
				overlay.rect_size = Vector2(round(original_resolution.x), round(original_resolution.x / native_aspect_ratio))
			elif aspect_diff > 1.0 + epsilon and aspect_setting == "keep_height":
				overlay.rect_size = Vector2(round(original_resolution.y * native_aspect_ratio), round(original_resolution.y))
			else:
				overlay.rect_size = Vector2(round(original_resolution.x), round(original_resolution.y))
		elif usage == USAGE_3D:
			overlay.rect_size = Vector2(round(native_resolution.x), round(native_resolution.y))
			if aspect_diff > 1.0 + epsilon:
				overlay.rect_size.x = round(native_resolution.y * original_aspect_ratio)
			elif aspect_diff < 1.0 - epsilon:
				overlay.rect_size.y = round(native_resolution.x / original_aspect_ratio)
		var overlay_size = overlay.rect_size
		var screen_size = Vector2(0.0, 0.0)
		if usage == USAGE_2D:
			screen_size = original_resolution
		elif usage == USAGE_3D:
			screen_size = native_resolution
		if stretch_setting == "disabled" or usage == USAGE_2D:
			if aspect_setting == "keep":
				overlay.rect_position.x = 0
				overlay.rect_position.y = 0
			elif aspect_setting == "keep_width" or aspect_setting == "keep_height":
				overlay.rect_position.x = 0
				overlay.rect_position.y = 0
				if usage == USAGE_3D:
					if aspect_diff > 1.0 + epsilon:
						overlay.rect_position.x = round((screen_size.x * aspect_diff - overlay_size.x) * 0.5)
					elif aspect_diff < 1.0 - epsilon:
						overlay.rect_position.y = round((screen_size.y / aspect_diff - overlay_size.y) * 0.5)
			elif aspect_setting == "expand":
				if usage == USAGE_3D:
					overlay.rect_size = screen_size
				elif aspect_diff > 1.0 + epsilon:
					overlay.rect_size = Vector2(round(screen_size.x * aspect_diff), round(screen_size.y))
				elif aspect_diff < 1.0 - epsilon:
					overlay.rect_size = Vector2(round(screen_size.x), round(screen_size.y / aspect_diff))
				else:
					overlay.rect_size = screen_size
			elif aspect_setting == "ignore":
				if usage == USAGE_3D:
					overlay.rect_size = screen_size
		elif stretch_setting == "viewport":
			overlay.rect_size = native_resolution
		elif stretch_setting == "2d":
			overlay.rect_size = original_resolution
			overlay_size = overlay.rect_size
			overlay.rect_position.x = 0
			overlay.rect_position.y = 0
			if aspect_setting == "expand":
				if aspect_diff > 1.0 + epsilon:
					overlay.rect_size = Vector2(round(original_resolution.y * native_aspect_ratio), round(original_resolution.y))
				elif aspect_diff < 1.0 - epsilon:
					overlay.rect_size = Vector2(round(original_resolution.x), round(original_resolution.x / native_aspect_ratio))
			elif aspect_setting == "keep_width":
				overlay.rect_position.x = 0.0
				if aspect_diff < 1.0 - epsilon:
					overlay.rect_position.y = round((overlay_size.y / aspect_diff - overlay_size.y) * 0.5)
			elif aspect_setting == "keep_height":
				overlay.rect_position.y = 0.0
				if aspect_diff > 1.0 + epsilon:
					overlay.rect_position.x = round((overlay_size.x * aspect_diff - overlay_size.x) * 0.5)
				
func change_scale_factor(val) -> void:
	scale_factor = val
	_on_window_resize()
	
func change_smoothness(val) -> void:
	smoothness = val
	if sampler_material:
		sampler_material.set_shader_param("smoothness", smoothness)
		
func change_msaa(val) -> void:
	msaa = val
	if viewport:
		viewport.msaa = msaa
		
func change_fxaa(val) -> void:
	fxaa = val
	if viewport:
		viewport.fxaa = fxaa
		
func change_shadow_atlas(val) -> void:
	shadow_atlas = val

func set_image_alpha(val):
	if is_instance_valid(overlay):
		overlay.modulate.a = float(val)

func _on_window_resize() -> void:
	_get_screen_size()
	_set_viewport_size()
	_resize_viewport()
	_scale_viewport_canvas()
	_set_shader_resolution()
	_set_sampler_size()
	
func _get_aspect_setting():
	return ProjectSettings.get_setting("display/window/stretch/aspect")
	
func _get_stretch_setting():
	return ProjectSettings.get_setting("display/window/stretch/mode")

#func _input(event):
#	if viewport and is_inside_tree():
#		pass
		#viewport.input(event)
		
#func _unhandled_input(event):
#	if viewport and is_inside_tree():
#		viewport.unhandled_input(event)
