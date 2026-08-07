@tool
class_name SuggestiveContours extends CompositorEffect

@export var edge_radius: int = 1
@export var edge_portion: float = 0.1
@export var edge_threshold: float = 0.1
@export var close_normal_threshold: float = 0.5
@export var far_normal_threshold: float = 0.5
@export var depth_threshold: float = 0.5
@export var cutoff_depth_normal_outline: float = 20
@export var transition_depth_normal_outline: float = 0.5
@export var cutoff_curvature_normal_outline: float = 0.5
@export var transition_curvature_normal_outline: float = 0.05
@export var line_color: Color = Color(0,0,0)
@export var highlight_color: Color = Color(1,1,1)
@export var suggestive_contours_enabled: bool = true
const sugg_con_bit: int = 1
@export var suggestive_highlight_enabled: bool = true
const sugg_high_bit: int = 2
@export var depth_lines_enabled: bool = true
const depth_bit: int = 4
@export var normal_lines_enabled: bool = true
const normal_bit: int = 8
@export var debug_enabled: bool = true
const debug_bit: int = 16
@export var measurement_debug_enabled: bool = true
const measurement_bit: int = 32
@export var selector_enabled: bool = true
const selector_bit: int = 64


var rd : RenderingDevice
var shader : RID
var pipeline : RID

func _init() -> void:
	# run on rendering thread so main thread isn blocked
	RenderingServer.call_on_render_thread(initialize_compute_shader)
	needs_normal_roughness = true;

func _notification(what: int) -> void:
	# want to free resources before they are deleted
	# ppeline is freed when shader is freed
	if what == NOTIFICATION_PREDELETE and shader.is_valid():
		RenderingServer.free_rid(shader)
		
func _render_callback(effect_callback_type: int, render_data: RenderData) -> void:
	if not rd: return
	
	var scene_buffers : RenderSceneBuffersRD = render_data.get_render_scene_buffers()
	var scene_data : RenderSceneDataRD = render_data.get_render_scene_data()
	if not scene_buffers or not scene_data: return
	
	var inv_proj_mat : Projection = scene_data.get_cam_projection().inverse()
	
	var size : Vector2i = scene_buffers.get_internal_size()
	# if size on either axis is 0, can create any work groups
	if size.x == 0 or size.y == 0: return
	
	var x_groups : int = size.x;
	var y_groups : int = size.y;
	

	var push_constants : PackedByteArray = create_push_constants(size, inv_proj_mat)
	
	# create multiple views in case we are doing stereo rendering for VR
	for view in scene_buffers.get_view_count(): 
		var screen_tex : RID = scene_buffers.get_color_layer(view)

		# create uniform for passing screen texture data
		var uniform_screen : RDUniform = RDUniform.new()
		uniform_screen.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
		uniform_screen.binding = 0
		uniform_screen.add_id(screen_tex)
		
		needs_normal_roughness = true;
		
		var sampler_state : RDSamplerState = RDSamplerState.new()
		sampler_state.min_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
		sampler_state.mag_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
		var normal_sampler : RID = rd.sampler_create(sampler_state)
		
		var normal_tex : RID = scene_buffers.get_texture("forward_clustered", "normal_roughness")
		if not normal_tex: return
		
		# create uniform for passing screen normal texture data
		var uniform_normal : RDUniform = RDUniform.new()
		uniform_normal.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
		uniform_normal.binding = 1
		uniform_normal.add_id(normal_sampler)
		uniform_normal.add_id(normal_tex)
		
		var depth_tex : RID = scene_buffers.get_depth_layer(view)
		
		sampler_state = RDSamplerState.new()
		sampler_state.min_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
		sampler_state.mag_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
		var depth_sampler : RID = rd.sampler_create(sampler_state)
		
		# create uniform for passing screen normal texture data
		var uniform_depth : RDUniform = RDUniform.new()
		uniform_depth.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
		uniform_depth.binding = 2
		uniform_depth.add_id(depth_sampler)
		uniform_depth.add_id(depth_tex)
		
		var image_uniform_set : RID = UniformSetCacheRD.get_cache(shader, 0, [uniform_screen, uniform_normal, uniform_depth])
		
		var compute_list : int = rd.compute_list_begin()
		rd.compute_list_bind_compute_pipeline(compute_list, pipeline)
		rd.compute_list_bind_uniform_set(compute_list, image_uniform_set, 0)
		rd.compute_list_set_push_constant(compute_list,push_constants,push_constants.size())

		rd.compute_list_dispatch(compute_list, x_groups, y_groups, 1)
		rd.compute_list_end()

func initialize_compute_shader() -> void:
	rd = RenderingServer.get_rendering_device()
	if not rd: return
	
	# load in file from data
	var glsl_file : RDShaderFile = load("res://suggestive_contours.glsl")
	shader = rd.shader_create_from_spirv(glsl_file.get_spirv())
	pipeline = rd.compute_pipeline_create(shader)
	
	
func create_push_constants(size: Vector2i, inv_proj_mat: Projection) -> PackedByteArray:
	var push_constants_float = PackedFloat32Array()
	push_constants_float.append(size.x)
	push_constants_float.append(size.y)
	push_constants_float.append(edge_portion)
	push_constants_float.append(edge_threshold)
	#4
	push_constants_float.append(inv_proj_mat[2].w)
	push_constants_float.append(inv_proj_mat[3].w)
	push_constants_float.append(close_normal_threshold)
	push_constants_float.append(far_normal_threshold)
	#8
	push_constants_float.append(cutoff_depth_normal_outline)
	push_constants_float.append(transition_depth_normal_outline)
	push_constants_float.append(cutoff_curvature_normal_outline)
	push_constants_float.append(transition_curvature_normal_outline)
	#12
	push_constants_float.append(depth_threshold)
	push_constants_float.append(0)
	push_constants_float.append(0)
	push_constants_float.append(0)
	push_constants_float.append(line_color.r)
	push_constants_float.append(line_color.g)
	push_constants_float.append(line_color.b)
	push_constants_float.append(0)
	#16
	push_constants_float.append(highlight_color.r)
	push_constants_float.append(highlight_color.g)
	push_constants_float.append(highlight_color.b)
	
	
	var push_constants_byte : PackedByteArray = push_constants_float.to_byte_array()
	var radius_array : PackedInt32Array = PackedInt32Array()
	radius_array.append(edge_radius)
	var radius_array_bytes = radius_array.to_byte_array()
	push_constants_byte.append_array(radius_array_bytes)
	var booleans_packed: int = 0
	if suggestive_contours_enabled:
		booleans_packed |= sugg_con_bit
	if suggestive_highlight_enabled:
		booleans_packed |= sugg_high_bit
	if depth_lines_enabled:
		booleans_packed |= depth_bit
	if normal_lines_enabled:
		booleans_packed |= normal_bit
	if debug_enabled:
		booleans_packed |= debug_bit
	if measurement_debug_enabled:
		booleans_packed |= measurement_bit
	if selector_enabled:
		booleans_packed |= selector_bit
	var packed_boolean_array : PackedInt32Array = PackedInt32Array()
	packed_boolean_array.append(booleans_packed)
	var packed_boolean_array_bytes : PackedByteArray = packed_boolean_array.to_byte_array()
	push_constants_byte.append_array(packed_boolean_array_bytes)
	return push_constants_byte

	
