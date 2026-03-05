@tool
class_name DiscontinuityLines extends CompositorEffect

@export var edge_threshold: float = 0.9

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
	
	var push_constants : PackedFloat32Array = PackedFloat32Array()
	push_constants.append(size.x)
	push_constants.append(size.y)
	push_constants.append(inv_proj_mat[2].w)
	push_constants.append(inv_proj_mat[3].w)
	push_constants.append(edge_threshold)
	# need to pack to fill sufficient bytes
	push_constants.append(0.0)
	push_constants.append(0.0)
	push_constants.append(0.0)
	
	# create multiple views in case we are doing stereo rendering for VR
	for view in scene_buffers.get_view_count(): 
		var screen_tex : RID = scene_buffers.get_color_layer(view)

		# create uniform for passing screen texture data
		var uniform_screen : RDUniform = RDUniform.new()
		uniform_screen.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
		uniform_screen.binding = 0
		uniform_screen.add_id(screen_tex)
		
		needs_normal_roughness = true;
		var normal_tex : RID = scene_buffers.get_texture("forward_clustered", "normal_roughness")
		if not normal_tex: return
		
		# create uniform for passing screen normal texture data
		var uniform_normal : RDUniform = RDUniform.new()
		uniform_normal.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
		uniform_normal.binding = 1
		uniform_normal.add_id(normal_tex)
		
		var depth_tex : RID = scene_buffers.get_depth_layer(view);
		
		var sampler_state : RDSamplerState = RDSamplerState.new()
		sampler_state.min_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
		sampler_state.mag_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
		var linear_sampler : RID = rd.sampler_create(sampler_state)
		
		# create uniform for passing screen normal texture data
		var uniform_depth : RDUniform = RDUniform.new()
		uniform_depth.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
		uniform_depth.binding = 2
		uniform_depth.add_id(linear_sampler)
		uniform_depth.add_id(depth_tex)
		
		var image_uniform_set : RID = UniformSetCacheRD.get_cache(shader, 0, [uniform_screen, uniform_normal, uniform_depth])
		
		var compute_list : int = rd.compute_list_begin()
		rd.compute_list_bind_compute_pipeline(compute_list, pipeline)
		rd.compute_list_bind_uniform_set(compute_list, image_uniform_set, 0)
		rd.compute_list_set_push_constant(compute_list,push_constants.to_byte_array(),push_constants.size() * 4)
		rd.compute_list_dispatch(compute_list, x_groups, y_groups, 1)
		rd.compute_list_end()

func initialize_compute_shader() -> void:
	rd = RenderingServer.get_rendering_device()
	if not rd: return
	
	# load in file from data
	var glsl_file : RDShaderFile = load("res://discontinuity_lines.glsl")
	shader = rd.shader_create_from_spirv(glsl_file.get_spirv())
	pipeline = rd.compute_pipeline_create(shader)
	

	
